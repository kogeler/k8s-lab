# Change the external IPv6 prefix

## When to use

The external network the nodes' `eth1` is on moves to another IPv6 prefix
(a new allocation from the provider, a renumbering). The prefix is in every
node's template (the on-link route of `eth1`), in kube-proxy's
`nodePortAddresses`, and in every cluster's MetalLB VIP range, so every
cluster on the segment changes with it.

## Preconditions

- The router of the external network advertises the new prefix (and stops
  advertising the old one). Nodes take their `eth1` addresses from its router
  advertisements.
- New VIP ranges inside the new prefix, one per cluster, none overlapping.
- Every machine of every cluster will be replaced (the template changes); the
  clusters are `Available` and the host has room for one extra machine per
  cluster during the rollouts.
- Services that hold a VIP get a new one from the new range.

## Steps

1. In `group_vars/all.yml`: the new prefix and `mgmt-1`'s range in it.

   ```yaml
   management_cluster_external_ipv6_prefix: "2001:db8:44:100::/64"
   management_cluster_metallb_vip_range_v6: "2001:db8:44:100::200-2001:db8:44:100::2ff"
   ```

2. In each workload cluster's `<root>/addons/terraform.tfvars`: its range in
   the new prefix. (The cluster root reads the prefix from the handoff file.)

   ```hcl
   metallb = {
     pool = { rangeV6 = "2001:db8:44:100::300-2001:db8:44:100::3ff" }
   }
   ```

3. Run `<playbook>`: `mgmt-1`'s node templates change and all its machines are
   replaced, its MetalLB pool moves, the handoff file carries the new prefix,
   the gates check the result.
4. Apply each workload cluster's roots: the cluster root replaces every
   machine, the add-on root moves the pool, waits for the rollout and runs the
   gates.

   ```bash
   terraform -chdir=<root>/cluster apply
   terraform -chdir=<root>/addons apply
   ```

5. On every cluster, point kube-proxy's `nodePortAddresses` at the new prefix
   and restart kube-proxy. Only `kubeadm init` writes this ConfigMap; a
   replaced machine does not.

   ```bash
   KC=<cluster kubeconfig>                    # $MGMT for mgmt-1
   kubectl --kubeconfig $KC -n kube-system get configmap kube-proxy -o jsonpath='{.data.config\.conf}' > config.conf
   sed -i 's|- 2001:db8:42:100::/64$|- 2001:db8:44:100::/64|' config.conf
   kubectl --kubeconfig $KC -n kube-system patch configmap kube-proxy --type merge \
     -p "$(jq -n --rawfile c config.conf '{data: {"config.conf": $c}}')"
   kubectl --kubeconfig $KC -n kube-system rollout restart daemonset kube-proxy
   kubectl --kubeconfig $KC -n kube-system rollout status daemonset kube-proxy --timeout=5m
   ```

## Verify

- Every node's `eth1` has an address in the new prefix only
  (`lxc query /1.0/instances/<node>/state?project=$PROJECT` on the host).
- A LoadBalancer Service gets a VIP in the new range and answers from outside
  the external link; a NodePort answers on a node's `eth1` address and not on
  its `eth0` address.
- `kubectl --kubeconfig <cluster kubeconfig> -n kube-system get configmap kube-proxy -o jsonpath='{.data.config\.conf}'`
  shows the new prefix under `nodePortAddresses`.

## Rollback

The same procedure with the old prefix — another rollout of every machine.

## Tested

2026-11-16, harness: `2001:db8:42:100::/64` → `2001:db8:44:100::/64`, the
harness router re-configured first. One playbook run (11 minutes): all three
`mgmt-1` machines replaced, its gates passed after 5 min 17 s; `lab-default`:
cluster root 9 s, add-on root 3 min 46 s, all five machines replaced, gates
passed. Every node's `eth1` then had an address in the new prefix only. Before
step 5 a NodePort on a node's new `eth1` address was refused (kube-proxy still
listened on the old prefix) while the VIPs answered; after step 5 on both
clusters: VIP from the host and from a client behind the router, NodePort on
`eth1`, no NodePort on `eth0` — all as expected.
