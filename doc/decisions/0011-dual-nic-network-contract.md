# 0011. Two NICs per node: `eth0` carries the node, `eth1` answers what arrives on it

Status: Accepted, 2026-11-16

## Context

A node needs a network for itself (kubelet, control plane, Pod traffic, egress) and a way in
for clients outside the host: NodePorts and MetalLB VIPs on a public IPv6 prefix. Kept apart,
node traffic cannot leak onto the external segment. Left to the defaults, the split is
incomplete: router advertisements on `eth1` give a node a second IPv6 default route, replies
to clients in other prefixes leave through `eth0`, and kube-proxy answers NodePorts on the
node's primary address, on `eth0`.

## Decision

- `eth0` is on the LXD-managed bridge `capi-int` (dual-stack, DHCP, NAT through the host): the
  main table's only default route, the kubelet's node IPs, Pod and node traffic, egress.
- `eth1` is on the host bridge `br-ext6` over the host's uplink: IPv6 only, addressed by the
  external router's advertisements, whose routes systemd-networkd puts into table 4200. The
  external prefix stays on-link in the main table.
- Replies leave through the interface the request came in on. Connections that arrive on
  `eth1` get conntrack mark `0x100`, their replies carry it, and `fwmark 0x100/0x100 lookup
  4200` sends them out through `eth1`. A rule on the source address cannot do this: a reply
  from a VIP is forwarded Pod traffic, whose source becomes the VIP only after routing.
- The marks are two chains of the node's own in its `ip6 mangle` table, loaded in one
  `ip6tables-nft-restore --noflush` transaction by a unit the kubelet requires: inside each
  node's network namespace, never in the host's firewall. networkd keeps routing rules it did
  not create (`ManageForeignRoutingPolicyRules=no`).
- kube-proxy's `nodePortAddresses` is the external prefix: NodePorts answer on `eth1` only,
  none on IPv4. MetalLB announces on `eth1` ([0013](0013-calico-and-metallb.md)). The class
  chart's templates carry all of it; the prefix is the required
  `management_cluster_external_ipv6_prefix`, handed to Terraform in `handoff.json`.

## Consequences

- Role `host` loads `nft_compat`, `xt_connmark` and `xt_mark`; node images must ship
  `ip6tables-nft`. A node that cannot load the marks never joins, and its journal says why.
- A host firewall must not `flush ruleset` and must accept forwarded traffic of both bridges
  ([architecture.md](../architecture.md)).
- A prefix change replaces every machine of every cluster, and kube-proxy's ConfigMap, which
  only `kubeadm init` writes, is edited by hand
  ([change-external-prefix.md](../runbooks/change-external-prefix.md)).
- On a shared external segment the VIP ranges are reserved, and other tenants must not send
  router advertisements, which the nodes accept on `eth1`. A real provider router is the
  deployment's to check; the harness simulates one ([0016](0016-test-strategy.md)).
