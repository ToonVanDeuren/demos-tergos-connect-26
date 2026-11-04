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
# GitHub puts the owner's ID in the OIDC subject, so the federated credentials need it
GITHUB_OWNER_ID="$(curl -sf "https://api.github.com/users/$GITHUB_OWNER" | jq -r .id)"
ACR="acrtergos${SUBSCRIPTION_ID:0:8}"   # registry names are global: alphanumeric, unique

# the system nodes run outside the subscription (--enable-hosted-system), but the
# nodes AKS Automatic adds for the apps need quota
VCPU_LIMIT="$(az vm list-usage -l "$LOCATION" --query "[?name.value=='cores'].limit | [0]" -o tsv)"
[ "${VCPU_LIMIT:-0}" -ge 24 ] \
  || echo "WARNING: the vCPU quota in $LOCATION is ${VCPU_LIMIT:-unknown}; AKS Automatic may leave pods Pending"

step "creating the registry, the monitoring workspaces and AKS Automatic (takes a while)"
az group create -n "$RG" -l "$LOCATION" -o none
ACR_ID="$(az acr show -n "$ACR" --query id -o tsv 2>/dev/null \
  || az acr create -g "$RG" -n "$ACR" --sku Basic --query id -o tsv)"
# AKS Automatic turns monitoring on. Without these, az creates the workspaces in
# default resource groups (the logs one in East US), and teardown.sh misses them.
LOGS_ID="$(az monitor log-analytics workspace show -g "$RG" -n log-tergos-demo --query id -o tsv 2>/dev/null \
  || az monitor log-analytics workspace create -g "$RG" -n log-tergos-demo -l "$LOCATION" --query id -o tsv)"
METRICS_ID="$(az monitor account show -g "$RG" -n amw-tergos-demo --query id -o tsv 2>/dev/null \
  || az monitor account create -g "$RG" -n amw-tergos-demo -l "$LOCATION" --query id -o tsv)"
# --enable-hosted-system: the system nodes run outside the subscription and need no
#   vCPU quota (otherwise 16 in one D-series family)
# --attach-acr: the nodes pull with their own identity, so there is no image pull secret
# az can exit non-zero after the cluster is up: it also adds Prometheus rule groups,
# which some regions (Belgium Central) do not offer. So check the cluster itself.
az aks show -g "$RG" -n "$AKS" -o none 2>/dev/null \
  || az aks create -g "$RG" -n "$AKS" --sku automatic --enable-hosted-system --attach-acr "$ACR" \
       --enable-gateway-api --enable-app-routing-istio \
       --workspace-resource-id "$LOGS_ID" --azure-monitor-workspace-resource-id "$METRICS_ID" -o none \
  || true
[ "$(az aks show -g "$RG" -n "$AKS" --query provisioningState -o tsv)" = "Succeeded" ] \
  || die "AKS is not up; see: az aks show -g $RG -n $AKS"
AKS_ID="$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)"

step "connecting the control plane to AKS and GitHub"
# AKS Automatic authorizes kubectl with Azure RBAC: being Owner of the subscription
# is not enough. provider-kubernetes signs in as the service principal, and you need
# it too, for the next step and for demo-script.md.
az role assignment create --assignee "$CLIENT_ID" --scope "$AKS_ID" \
  --role "Azure Kubernetes Service RBAC Cluster Admin" -o none
az role assignment create --assignee-object-id "$(az ad signed-in-user show --query id -o tsv)" \
  --assignee-principal-type User --scope "$AKS_ID" \
  --role "Azure Kubernetes Service RBAC Cluster Admin" -o none
az aks get-credentials -g "$RG" -n "$AKS" --file "$SETUP/.workload.kubeconfig" --overwrite-existing
secret_from_file cluster-config kubeconfig "$SETUP/.workload.kubeconfig"
secret_from_file github-creds credentials "$GITHUB_CREDS"
kubectl --context "$CTL" apply -f "$SETUP/manifests/kubernetes-providerconfig.yaml" \
  -f "$SETUP/manifests/github-providerconfig.yaml"

step "installing the platform Gateway on AKS"
# your own kubectl gets AKS too, for this step and for demo-script.md
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli --context "$AKS"   # only this context, not all of them
kubectl config use-context "$CTL" >/dev/null   # get-credentials switched it; the demos expect kind
# a new role assignment can take a few minutes to work
for _ in $(seq 1 30); do
  [ "$(kubectl --context "$AKS" auth can-i get gatewayclasses 2>/dev/null)" = "yes" ] && break
  sleep 10
done
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
      ownerId: "$GITHUB_OWNER_ID"
      templates:
        go: demos-tergos-connect-26-app-template
    tags:
      managed-by: crossplane
YAML
kubectl --context "$CTL" apply -k "$ROOT/demo-2-golden-path/platform"

cat <<MSG

Platform is up, with the apps at $GATEWAY_IP.nip.io.
Follow demo-2-golden-path/demo-script.md.
MSG
