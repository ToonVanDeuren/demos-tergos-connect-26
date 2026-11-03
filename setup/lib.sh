# Shared by the setup scripts: the names everything uses, and a few helpers.
set -euo pipefail

SETUP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SETUP")"
AZURE_CREDS="${AZURE_CREDS:-$SETUP/azure-creds.json}"
GITHUB_CREDS="${GITHUB_CREDS:-$SETUP/github-creds.json}"

CTL="kind-control-plane"   # kube-context of the control plane (kind)
AKS="aks-tergos-demo"      # AKS cluster name, and the kube-context of the workload cluster
RG="rg-tergos-demo"        # resource group for AKS and the registry
LOCATION="belgiumcentral"

step() { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

need_tools() {
  for c in "$@"; do command -v "$c" >/dev/null || die "'$c' not found in PATH"; done
}

# az and the providers (azure-creds.json) must work on the same subscription
check_subscription() {
  [ -f "$AZURE_CREDS" ] || die "$AZURE_CREDS not found; see 'Run it yourself' in README.md"
  local want; want="$(jq -r .subscriptionId "$AZURE_CREDS")"
  [ "$(az account show --query id -o tsv)" = "$want" ] \
    || die "az is on '$(az account show --query name -o tsv)', but azure-creds.json is for $want. Run: az account set --subscription $want"
}

# create or update a secret in crossplane-system from a file: secret_from_file <name> <key> <file>
secret_from_file() {
  kubectl --context "$CTL" create secret generic "$1" -n crossplane-system --from-file="$2=$3" \
    --dry-run=client -o yaml | kubectl --context "$CTL" apply -f -
}
