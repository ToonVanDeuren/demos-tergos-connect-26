#!/usr/bin/env bash
# Stand up the whole demo: a kind control plane with Crossplane + providers (30s
# drift polling, change logs, watches), an AKS Automatic workload cluster with a
# container registry and the platform Gateway, the cross-cluster wiring, and the
# platform (one XRD, one composition). Demo 1 runs on the same control plane.
#
# Prereqs: kind, kubectl, kubelogin, helm, jq, az >= 2.86.0 (logged in), and:
#   az ad sp create-for-rbac --sdk-auth --role Owner \
#     --scopes "/subscriptions/$(az account show --query id -o tsv)" > azure-creds.json
#     (Contributor cannot create role assignments)
#   github-creds.json: {"token": "<PAT>", "owner": "<user>"}
#     The token needs the repo, workflow and delete_repo scopes. `owner` must own
#     the demos-tergos-connect-26-app-template repository.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDS="${AZURE_CREDS:-$HERE/azure-creds.json}"
GITHUB_CREDS="${GITHUB_CREDS:-$HERE/github-creds.json}"
CTL="kind-control-plane"   # kube-context for the control-plane cluster
LOCATION="westeurope"
RG="rg-tergos-demo"
AKS="aks-tergos-demo"      # also the kube-context for the workload cluster

for c in kind kubectl kubelogin helm jq az; do
  command -v "$c" >/dev/null || { echo "ERROR: '$c' not found in PATH"; exit 1; }
done
[ -f "$CREDS" ] || {
  echo "ERROR: Azure creds not found at $CREDS"
  echo "       create them with: az ad sp create-for-rbac --sdk-auth --role Owner --scopes /subscriptions/<id> > azure-creds.json"
  exit 1
}
[ -f "$GITHUB_CREDS" ] || {
  echo "ERROR: GitHub creds not found at $GITHUB_CREDS"
  echo "       create it with: {\"token\": \"<PAT>\", \"owner\": \"<user>\"}"
  exit 1
}

echo "==> 1/7 creating the kind control-plane cluster"
kind get clusters | grep -qx control-plane || kind create cluster --name control-plane

echo "==> 2/7 installing Crossplane on the control-plane cluster"
helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install crossplane crossplane-stable/crossplane \
  --kube-context "$CTL" \
  --namespace crossplane-system --create-namespace \
  --set 'args={--poll-interval=30s}' --wait
kubectl --context "$CTL" apply -f - <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: platform-system}   # cluster-scoped App composes its MRs here
YAML

echo "==> 3/7 installing runtime configs, providers + functions (waiting for Healthy)"
kubectl --context "$CTL" apply -f "$HERE/01-setup/runtimeconfigs.yaml"
kubectl --context "$CTL" apply -f "$HERE/01-setup/providers.yaml"
kubectl --context "$CTL" apply -f "$HERE/01-setup/functions.yaml"
kubectl --context "$CTL" wait --for=condition=Healthy provider --all --timeout=600s
kubectl --context "$CTL" wait --for=condition=Healthy function --all --timeout=300s

echo "==> 4/7 wiring Azure + GitHub credentials"
kubectl --context "$CTL" create secret generic azure-creds \
  -n crossplane-system --from-file=creds="$CREDS" \
  --dry-run=client -o yaml | kubectl --context "$CTL" apply -f -
kubectl --context "$CTL" create secret generic github-creds \
  -n crossplane-system --from-file=credentials="$GITHUB_CREDS" \
  --dry-run=client -o yaml | kubectl --context "$CTL" apply -f -
kubectl --context "$CTL" apply -f "$HERE/02-config/azure-providerconfigs.yaml"
kubectl --context "$CTL" apply -f "$HERE/02-config/github-providerconfig.yaml"

echo "==> 5/7 creating the AKS Automatic workload cluster and its registry (takes a while)"
TENANT_ID="$(jq -r .tenantId "$CREDS")"
SUBSCRIPTION_ID="$(jq -r .subscriptionId "$CREDS")"
CLIENT_ID="$(jq -r .clientId "$CREDS")"
GITHUB_OWNER="$(jq -r .owner "$GITHUB_CREDS")"
ACR="acrtergos${SUBSCRIPTION_ID:0:8}"   # registry names are global: alphanumeric, unique
az group create --name "$RG" --location "$LOCATION" -o none
az aks show -g "$RG" -n "$AKS" -o none 2>/dev/null \
  || az aks create -g "$RG" -n "$AKS" --sku automatic -o none
AKS_ID="$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)"
# the nodes pull with their kubelet identity, so no image pull secret is needed
az acr show -n "$ACR" -o none 2>/dev/null \
  || az acr create -g "$RG" -n "$ACR" --sku Basic -o none
az aks update -g "$RG" -n "$AKS" --attach-acr "$ACR" -o none
ACR_ID="$(az acr show -n "$ACR" --query id -o tsv)"
# provider-kubernetes signs in as the service principal
az role assignment create --assignee "$CLIENT_ID" --scope "$AKS_ID" \
  --role "Azure Kubernetes Service RBAC Cluster Admin" -o none
az aks get-credentials -g "$RG" -n "$AKS" --file "$HERE/.workload.kubeconfig" --overwrite-existing
kubectl --context "$CTL" create secret generic cluster-config \
  -n crossplane-system --from-file=kubeconfig="$HERE/.workload.kubeconfig" \
  --dry-run=client -o yaml | kubectl --context "$CTL" apply -f -
kubectl --context "$CTL" apply -f "$HERE/02-config/kubernetes-providerconfig.yaml"
# your own kubectl, for the commands in demo-script.md
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

echo "==> 6/7 installing the platform-owned Gateway on the workload cluster"
# New Automatic clusters have this from AKS 1.36; older ones need it enabled.
kubectl --context "$AKS" get gatewayclass approuting-istio >/dev/null 2>&1 \
  || az aks update -g "$RG" -n "$AKS" --enable-gateway-api --enable-app-routing-istio -o none
kubectl --context "$AKS" wait --for=condition=Accepted gatewayclass/approuting-istio --timeout=300s
kubectl --context "$AKS" apply -f "$HERE/02-config/workload-gateway.yaml"
kubectl --context "$AKS" wait --for=condition=Programmed gateway/platform -n platform-gateway --timeout=600s
GATEWAY_IP="$(kubectl --context "$AKS" get gateway platform -n platform-gateway -o jsonpath='{.status.addresses[0].value}')"

echo "==> 7/7 publishing the platform EnvironmentConfig and the platform"
# `platform`: the values only known at setup time, plus platform-wide settings.
# Everything a composition needs that is not intent lives here, never in a template.
kubectl --context "$CTL" apply -f - <<YAML
apiVersion: apiextensions.crossplane.io/v1beta1
kind: EnvironmentConfig
metadata:
  name: platform
data:
  platform:
    tenantId: "$TENANT_ID"
    subscriptionId: "$SUBSCRIPTION_ID"
    location: $LOCATION
    resourceGroupName: $RG
    clusterName: $AKS
    clusterId: $AKS_ID
    registryName: $ACR
    registryId: $ACR_ID
    appsDomain: $GATEWAY_IP.nip.io
    managedResourcesNamespace: platform-system
    github:
      owner: $GITHUB_OWNER
      templates:
        go: demos-tergos-connect-26-app-template
    tags:
      managed-by: crossplane
YAML
kubectl --context "$CTL" apply -k "$HERE/03-platform/app"

cat <<MSG

Platform is up. Next, pre-stage BEFORE the talk:
  kubectl --context $CTL apply -f 04-examples/app-orders-api.yaml -f 04-examples/app-invoices-api.yaml
  kubectl --context $CTL get apps -w
  gh release create v0.1.0 -R $GITHUB_OWNER/orders-api --generate-notes
  gh release create v0.1.0 -R $GITHUB_OWNER/invoices-api --generate-notes

On stage: app-rejected, app-payments-api, a release, 05-rollout/rollout.sh. See demo-script.md.
MSG
