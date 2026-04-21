#!/usr/bin/env bash
#
# Wait for a Kubernetes API endpoint to become usable.
#
# Consumed by later phases (plan §12, Phase 5.05 and §13.2 local E2E) after
# a target workload/management cluster kubeconfig has been materialized.
#
# Usage:
#   wait_for_cluster.sh <kubeconfig> [timeout-seconds]

set -euo pipefail

kubeconfig="${1:?kubeconfig path required}"
timeout="${2:-300}"
interval=5

if [[ ! -r "$kubeconfig" ]]; then
  echo "[wait_for_cluster] kubeconfig not found: $kubeconfig" >&2
  exit 2
fi

: "${KUBECTL:=kubectl}"

deadline=$(( $(date +%s) + timeout ))

echo "[wait_for_cluster] waiting up to ${timeout}s for API to report ready"
while (( $(date +%s) < deadline )); do
  if "$KUBECTL" --kubeconfig="$kubeconfig" --request-timeout=5s \
       get --raw='/readyz' >/dev/null 2>&1; then
    echo "[wait_for_cluster] API readyz OK"
    exit 0
  fi
  sleep "$interval"
done

echo "[wait_for_cluster] timed out waiting for API" >&2
exit 1
