#!/usr/bin/env bash
# Tear the demos down.
#   ./teardown.sh --platform   demo 2 only (the Apps and AKS); the control plane and
#                              demo 1 stay, so platform.sh can bring demo 2 back
#   ./teardown.sh              everything
#
# The Apps go first, while the control plane still runs: Crossplane deletes their
# repositories and Azure resources. Deleting the kind cluster first would orphan them.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VAULT="kv-crossplane-demo-1-bec"   # keep in sync with demo-1-managed-resources/02-keyvault.yaml
ALL=true
[ "${1:-}" = "--platform" ] && ALL=false

if kind get clusters | grep -qx control-plane; then
  step "deleting the Apps (Crossplane removes their repositories and cloud resources)"
  kubectl --context "$CTL" delete apps.platform.toon.consulting --all \
    --wait --timeout=600s 2>/dev/null || true
  # the App is gone at once; Crossplane deletes what it composed afterwards, so wait for that
  for _ in $(seq 1 60); do
    [ -z "$(kubectl --context "$CTL" get managed -n platform-system -o name 2>/dev/null)" ] && break
    sleep 10
  done
  if $ALL; then
    step "deleting demo 1"
    kubectl --context "$CTL" delete -f "$ROOT/demo-1-managed-resources/02-keyvault.yaml" \
      -f "$ROOT/demo-1-managed-resources/01-resourcegroup.yaml" --ignore-not-found --wait --timeout=600s || true
  fi
  step "anything left in the control plane?"
  kubectl --context "$CTL" get managed -A --no-headers 2>/dev/null || true
fi

step "deleting AKS, the registry and their resource group"
az group delete -n "$RG" --yes || true
rm -f "$SETUP/.workload.kubeconfig"
# and the context platform.sh added to your kubeconfig
kubectl config delete-context "$AKS" >/dev/null 2>&1 || true
kubectl config delete-cluster "$AKS" >/dev/null 2>&1 || true
kubectl config delete-user "clusterUser_${RG}_${AKS}" >/dev/null 2>&1 || true

if $ALL; then
  step "purging the soft-deleted key vault, so its name is free next time"
  az keyvault purge --name "$VAULT" 2>/dev/null || true
  step "deleting the kind cluster"
  kind delete cluster --name control-plane || true
fi

echo "Done."
