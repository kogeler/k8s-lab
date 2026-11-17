#!/usr/bin/env bash
# Print the state of a host after a failed run: the host, LXD and its storage,
# every instance, the bootstrap cluster, mgmt-1 and every workload cluster it
# manages. Run it on the host (root through sudo). Every probe tolerates
# failure so one broken layer never hides the rest; no kubeconfig or Secret
# content is printed.
#
# Usage: scripts/collect-diagnostics.sh [OPT_ROOT]
#   OPT_ROOT  k8s_lab_opt_root on the host (default /opt/capi-lab)
set -u -o pipefail

opt_root=${1:-/opt/capi-lab}
boot_kc=$opt_root/etc/bootstrap.kubeconfig
mgmt_kc=$opt_root/etc/mgmt.kubeconfig
kubectl_bin=$opt_root/bin/kubectl
[ -x "$kubectl_bin" ] || kubectl_bin=$(command -v kubectl || echo kubectl)
lxc=/snap/bin/lxc
[ -x "$lxc" ] || lxc=lxc
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

say() { printf '\n=== %s ===\n' "$*"; }
k() { local kc=$1; shift; sudo "$kubectl_bin" --kubeconfig "$kc" --request-timeout=15s "$@"; }

# Nodes with their pressure conditions, the Pods that do not run, their
# description and logs, the latest events.
cluster_state() {
  local name=$1 kc=$2
  say "$name: nodes"
  k "$kc" get nodes -o wide
  k "$kc" get nodes -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,DISK:.status.conditions[?(@.type=="DiskPressure")].status,MEMORY:.status.conditions[?(@.type=="MemoryPressure")].status,PID:.status.conditions[?(@.type=="PIDPressure")].status'
  say "$name: pods"
  k "$kc" get pods -A -o wide
  k "$kc" get pods -A --no-headers 2>/dev/null |
    awk '$4 != "Running" && $4 != "Completed" { print $1, $2 }' |
    while read -r ns pod; do
      say "$name: $ns/$pod"
      k "$kc" describe -n "$ns" pod "$pod" | tail -60
      k "$kc" logs -n "$ns" "$pod" --all-containers --tail=100
    done
  say "$name: events (last 80)"
  k "$kc" get events -A --sort-by=.lastTimestamp | tail -80
}

# ---- host --------------------------------------------------------------------
say "host: df -h"; df -h
say "host: free -m"; free -m
say "host: loop devices"; sudo losetup -a
say "host: failed units"; sudo systemctl --failed
say "host: journal errors (last 200)"
sudo journalctl --boot --priority=err --no-pager | tail -200
say "host: iptables policies"
for chain in INPUT FORWARD OUTPUT; do sudo iptables -S "$chain" | head -1; done
say "host: iptables nat (first 50)"; sudo iptables -t nat -S | head -50
say "host: nftables tables"; sudo nft list tables
say "host: nftables inet lxd"; sudo nft list table inet lxd | head -80
say "host: forwarding"; sudo sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding

# ---- LXD ---------------------------------------------------------------------
say "LXD: daemon"; sudo "$lxc" info | head -20
say "LXD: projects"; sudo "$lxc" project list
say "LXD: storage"
sudo "$lxc" storage list
sudo "$lxc" storage list --format csv -c n 2>/dev/null |
  while read -r pool; do [ -n "$pool" ] && sudo "$lxc" storage info "$pool" | head -6; done
say "LXD: instances"; sudo "$lxc" list --all-projects
# Columns: n = name, e = project (P would be the profiles).
sudo "$lxc" list --all-projects --format csv -c ne 2>/dev/null |
  while IFS=, read -r name project; do
    [ -n "$name" ] || continue
    say "LXD: $project/$name"
    sudo "$lxc" info --project "$project" "$name" | head -40
    say "LXD: $project/$name addresses, routes, disk"
    sudo "$lxc" exec --project "$project" "$name" -- ip -br addr
    sudo "$lxc" exec --project "$project" "$name" -- ip route
    sudo "$lxc" exec --project "$project" "$name" -- df -h /
    say "LXD: $project/$name egress (TCP/443 to registry-1.docker.io)"
    sudo "$lxc" exec --project "$project" "$name" -- \
      timeout 10 curl -sS -o /dev/null -w '%{http_code}\n' https://registry-1.docker.io/v2/
    say "LXD: $project/$name journal errors"
    sudo "$lxc" exec --project "$project" "$name" -- journalctl --no-pager -p err -n 80
  done

# ---- bootstrap cluster -------------------------------------------------------
if sudo test -r "$boot_kc"; then
  cluster_state bootstrap "$boot_kc"
else
  say "bootstrap: no kubeconfig at $boot_kc"
fi

# ---- mgmt-1 and the clusters it manages --------------------------------------
if sudo test -r "$mgmt_kc"; then
  say "mgmt-1: Cluster API objects"
  k "$mgmt_kc" get clusters,kcp,md,ma -A -o wide | head -80
  cluster_state mgmt-1 "$mgmt_kc"
  for deploy in capi-system/capi-controller-manager capn-system/capn-controller-manager \
      capi-kubeadm-control-plane-system/capi-kubeadm-control-plane-controller-manager \
      capi-kubeadm-bootstrap-system/capi-kubeadm-bootstrap-controller-manager; do
    say "mgmt-1: logs of $deploy (last 100)"
    k "$mgmt_kc" -n "${deploy%%/*}" logs "deploy/${deploy#*/}" --tail=100
  done
  # Every Cluster but the one mgmt-1 is: its kubeconfig Secret, whose server is
  # the cluster's load balancer on the internal network, reachable from here.
  self=$(k "$mgmt_kc" get nodes -o jsonpath='{.items[0].metadata.annotations.cluster\.x-k8s\.io/cluster-name}' 2>/dev/null)
  k "$mgmt_kc" get clusters -A --no-headers -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name 2>/dev/null |
    while read -r ns name; do
      [ "$name" != "$self" ] || continue
      kc=$scratch/$name.kubeconfig
      if (umask 077; k "$mgmt_kc" -n "$ns" get secret "$name-kubeconfig" -o jsonpath='{.data.value}' | base64 -d > "$kc"); then
        cluster_state "$name" "$kc"
      else
        say "$name: no kubeconfig Secret"
      fi
    done
else
  say "mgmt-1: no kubeconfig at $mgmt_kc"
fi
exit 0
