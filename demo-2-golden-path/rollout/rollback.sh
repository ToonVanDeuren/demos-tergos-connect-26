#!/usr/bin/env bash
# Back to the original composition. The BranchProtection objects go with it.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl --context kind-control-plane apply -k "$HERE/../platform"
