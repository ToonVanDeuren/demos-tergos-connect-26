#!/usr/bin/env bash
# Everything demo 2 needs on top of the control plane (run control-plane.sh first):
# AKS Automatic with a registry and the platform Gateway, the wiring from the control
# plane to AKS and GitHub, and the platform (demo-2-golden-path/platform/).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need_tools kubectl kubelogin jq az
check_subscription
[ -f "$GITHUB_CREDS" ] || die "$GITHUB_CREDS not found; see 'Run it yourself' in README.md"
kubectl --context "$CTL" get providers.pkg.crossplane.io >/dev/null 2>&1 \
  || die "no control plane at $CTL; run control-plane.sh first"

TENANT_ID="$(jq -r .tenantId "$AZURE_CREDS")"
SUBSCRIPTION_ID="$(jq -r .subscriptionId "$AZURE_CREDS")"
CLIENT_ID="$(jq -r .clientId "$AZURE_CREDS")"
GITHUB_OWNER="$(jq -r .owner "$GITHUB_CREDS")"
ACR="acrtergos${SUBSCRIPTION_ID:0:8}"   # registry names are global: alphanumeric, unique

# AKS Automatic runs 3 system nodes of 4 vCPUs, plus the nodes it adds for workloads
VCPU_LIMIT="$(az vm list-usage -l "$LOCATION" --query "[?name.value=='cores'].limit | [0]" -o tsv)"
[ "${VCPU_LIMIT:-0}" -ge 24 ] \
  || echo "WARNING: the vCPU quota in $LOCATION is ${VCPU_LIMIT:-unknown}; AKS Automatic may leave pods Pending"

step "creating the registry and AKS Automatic (takes a while)"
az group create -n "$RG" -l "$LOCATION" -o none
ACR_ID="$(az acr show -n "$ACR" --query id -o tsv 2>/dev/null \
  || az acr create -g "$RG" -n "$ACR" --sku Basic --query id -o tsv)"
# --attach-acr: the nodes pull with their own identity, so there is no image pull secret
AKS_ID="$(az aks show -g "$RG" -n "$AKS" --query id -o tsv 2>/dev/null \
  || az aks create -g "$RG" -n "$AKS" --sku automatic --attach-acr "$ACR" \
       --enable-gateway-api --enable-app-routing-istio --query id -o tsv)"

step "connecting the control plane to AKS and GitHub"
# provider-kubernetes signs in as the service principal, authorized with Azure RBAC
az role assignment create --assignee "$CLIENT_ID" --scope "$AKS_ID" \
  --role "Azure Kubernetes Service RBAC Cluster Admin" -o none
az aks get-credentials -g "$RG" -n "$AKS" --file "$SETUP/.workload.kubeconfig" --overwrite-existing
secret_from_file cluster-config kubeconfig "$SETUP/.workload.kubeconfig"
secret_from_file github-creds credentials "$GITHUB_CREDS"
kubectl --context "$CTL" apply -f "$SETUP/manifests/kubernetes-providerconfig.yaml" \
  -f "$SETUP/manifests/github-providerconfig.yaml"

step "installing the platform Gateway on AKS"
# your own kubectl gets AKS too, for this step and for demo-script.md
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
kubectl --context "$AKS" wait --for=condition=Accepted --timeout=300s gatewayclass/approuting-istio
kubectl --context "$AKS" apply -f "$SETUP/manifests/workload-gateway.yaml"
kubectl --context "$AKS" wait --for=condition=Programmed --timeout=600s \
  gateway/platform -n platform-gateway
GATEWAY_IP="$(kubectl --context "$AKS" get gateway platform -n platform-gateway \
  -o jsonpath='{.status.addresses[0].value}')"

step "installing the platform"
# The values only known now, plus platform-wide settings. Everything a composition
# needs that is not intent lives here, never in a template.
kubectl --context "$CTL" apply -f - <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: platform-system   # the cluster-scoped App composes its resources here
---
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
kubectl --context "$CTL" apply -k "$ROOT/demo-2-golden-path/platform"

cat <<MSG

Platform is up. Pre-stage two apps BEFORE the talk, from demo-2-golden-path/:
  kubectl --context $CTL apply -f examples/app-orders-api.yaml -f examples/app-invoices-api.yaml
  kubectl --context $CTL get apps -w
  gh release create v0.1.0 -R $GITHUB_OWNER/orders-api --generate-notes
  gh release create v0.1.0 -R $GITHUB_OWNER/invoices-api --generate-notes

Then follow demo-2-golden-path/demo-script.md.
MSG
