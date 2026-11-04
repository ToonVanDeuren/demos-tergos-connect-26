#!/usr/bin/env bash
# Beat 4: a new requirement lands. One new step in the composition, and every
# App converges on it. No repository is touched by hand and no team is asked.
#
# app.composition.yaml is platform/app.composition.yaml plus that one step, and
# app.composition.diff shows the difference. When the platform composition
# changes, make the same change here and regenerate the diff, from demo-2-golden-path/:
#   diff -u --label platform/app.composition.yaml --label rollout/app.composition.yaml \
#     platform/app.composition.yaml rollout/app.composition.yaml > rollout/app.composition.diff
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl --context kind-control-plane apply -f "$HERE/app.composition.yaml"
