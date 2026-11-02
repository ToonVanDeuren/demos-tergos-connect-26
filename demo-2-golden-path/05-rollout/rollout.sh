#!/usr/bin/env bash
# Beat 4: a new requirement lands. One new step in the composition, and every
# App converges on it. No repository is touched by hand and no team is asked.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl --context kind-control-plane apply -k "$HERE"
