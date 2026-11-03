#!/usr/bin/env bash
# The control plane both demos run on: a local kind cluster with Crossplane, the
# providers (15s drift polling, change logs, watches) and the Azure credentials.
# This is all demo 1 needs. Demo 2 needs platform.sh on top of it.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need_tools kind kubectl helm jq az
check_subscription

step "registering the Azure resource providers"
# a fresh subscription has none of these; the first create would fail
for ns in Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.KeyVault \
  Microsoft.ManagedIdentity Microsoft.Network Microsoft.Compute Microsoft.OperationalInsights \
  Microsoft.Insights Microsoft.Monitor Microsoft.AlertsManagement Microsoft.PolicyInsights; do
  az provider register --namespace "$ns" --wait -o none
done

step "creating the kind cluster"
kind get clusters | grep -qx control-plane || kind create cluster --name control-plane

step "installing Crossplane"
helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
helm repo update crossplane-stable >/dev/null
helm upgrade --install crossplane crossplane-stable/crossplane --kube-context "$CTL" \
  -n crossplane-system --create-namespace --set 'args={--poll-interval=30s}' --wait >/dev/null

step "installing the providers and functions (waits until Healthy)"
kubectl --context "$CTL" apply -f "$SETUP/manifests/runtimeconfigs.yaml"
# the family first: the Azure providers depend on it (see provider-family.yaml)
kubectl --context "$CTL" apply -f "$SETUP/manifests/provider-family.yaml"
kubectl --context "$CTL" wait --for=condition=Healthy --timeout=600s \
  providers.pkg.crossplane.io/provider-family-azure
kubectl --context "$CTL" apply -f "$SETUP/manifests/providers.yaml" \
  -f "$SETUP/manifests/functions.yaml"
kubectl --context "$CTL" wait --for=condition=Healthy --timeout=600s providers.pkg.crossplane.io --all
kubectl --context "$CTL" wait --for=condition=Healthy --timeout=300s functions.pkg.crossplane.io --all

step "wiring the Azure credentials"
secret_from_file azure-creds creds "$AZURE_CREDS"
kubectl --context "$CTL" apply -f "$SETUP/manifests/azure-providerconfigs.yaml"

cat <<MSG

Control plane is up. Demo 1 runs on it now:
  kubectl --context $CTL apply -f demo-1-managed-resources/
For demo 2, run setup/platform.sh next.
MSG
