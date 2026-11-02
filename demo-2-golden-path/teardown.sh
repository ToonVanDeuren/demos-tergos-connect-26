#!/usr/bin/env bash
# Tear the demo down. Order matters:
#   1. delete the composites and wait, so Crossplane removes the repositories and
#      the Azure resources (deleting the kind cluster first would orphan them)
#   2. purge the soft-deleted demo 1 vault so its name is free for the next run
#   3. delete the resource group holding AKS and the registry, then the kind cluster
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTL="kind-control-plane"
RG="rg-tergos-demo"

if kind get clusters | grep -qx control-plane; then
  echo "==> deleting composites (Crossplane removes the repositories and cloud resources)"
  kubectl --context "$CTL" delete apps.platform.toon.consulting --all --wait=true --timeout=600s || true
  kubectl --context "$CTL" delete -f "$HERE/../demo-1-managed-resources/keyvault.yaml" -f "$HERE/../demo-1-managed-resources/resourcegroup.yaml" --ignore-not-found --wait=true --timeout=600s || true
  echo "==> anything left behind in the control plane? (should be empty)"
  kubectl --context "$CTL" get managed -A 2>/dev/null | grep -v '^NAME' || true
fi

echo "==> purging the soft-deleted key vault (frees the name for the next run)"
az keyvault purge --name kv-crossplane-demo-1-weu 2>/dev/null || true

echo "==> deleting the AKS cluster, the registry and their resource group"
az group delete --name "$RG" --yes || true

echo "==> deleting the kind cluster"
kind delete cluster --name control-plane || true
rm -f "$HERE/.workload.kubeconfig"

echo "Done."
