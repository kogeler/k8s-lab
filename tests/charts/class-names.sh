#!/usr/bin/env bash
# Render check of charts/capi-cluster-class object names (part of `make check`):
# the same values give the same names; a changed template value renames exactly
# that template; the ClusterClass keeps the cluster's name; reserved kubelet
# arguments are refused.
# Usage: tests/charts/class-names.sh [helm]
set -euo pipefail
helm=${1:-helm}
chart=$(cd "$(dirname "$0")/../../charts/capi-cluster-class" && pwd)
base=(-f "$chart/ci/default-values.yaml")

names() {
  "$helm" template k8s-lab-ci-class "$chart" "${base[@]}" "$@" \
    | awk '/^kind:/ {kind = $2} /^  name:/ {print kind, $2}' | sort
}

# Prints the objects (name without its hash) whose names differ between two renders.
changed() {
  { diff <(echo "$1") <(echo "$2") || true; } \
    | awk '/^[<>]/ {sub(/-[0-9a-f]+$/, "", $3); print $3}' | sort -u | tr '\n' ' '
}

expect() {
  local what=$1 want=$2 got
  got=$(changed "$reference" "$3")
  if [ "$got" != "$want" ]; then
    echo "class-names: $what: renamed '$got', expected '$want'" >&2
    exit 1
  fi
}

reference=$(names)
echo "$reference"
grep -qx 'ClusterClass k8s-lab-ci' <<<"$reference" || { echo "class-names: ClusterClass is not named after the cluster" >&2; exit 1; }

expect "same values" "" "$(names)"
expect "a control-plane kubelet argument" "k8s-lab-ci-kcp " \
  "$(names --set-json 'controlPlane.kubeletExtraArgs=[{"name":"max-pods","value":"120"}]')"
expect "the control-plane flavor" "k8s-lab-ci-cp " "$(names --set controlPlane.flavor=c4-m8)"
expect "the worker flavor" "k8s-lab-ci-md-0 " "$(names --set worker.flavor=c2-m4)"
expect "a worker command" "k8s-lab-ci-md-0-boot " "$(names --set-json 'worker.preKubeadmCommands=["true"]')"
expect "the load-balancer flavor" "k8s-lab-ci-infra " "$(names --set loadBalancer.flavor=c1-m1)"

if names --set-json 'worker.kubeletExtraArgs=[{"name":"node-ip","value":"10.0.0.1"}]' >/dev/null 2>&1; then
  echo "class-names: a reserved kubelet argument was accepted" >&2
  exit 1
fi
echo "class-names: ok"
