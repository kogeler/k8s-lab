# 0013. Calico with VXLAN and nftables, MetalLB in native L2 mode, each as two releases

Status: Accepted, 2026-11-16

## Context

`mgmt-1` and the workload clusters are dual-stack and need network policy, on unprivileged
nodes on one host: there is no router to peer with, no privilege for an eBPF dataplane, and
the internal network has no route back to the Pod CIDRs. VIPs must be announced on the external segment, on `eth1`. The
custom resources that configure each add-on need CRDs that appear only once its upstream
release runs: Calico's operator creates them at start, and MetalLB's chart ships them as
templates, so a pool in the same release does not validate at install. Calico's CRD chart as
a Helm release would exceed the 1 MiB limit of a release record.

## Decision

- Calico through the tigera operator, as two releases: `cni-calico` (the operator only; it
  creates its CRDs) and, after a read-only wait for those CRDs, `cni-calico-config` (the
  `Installation`, the `APIServer` and Gate B).
- The `Installation`: BGP off; VXLAN for both pools, Calico's only encapsulation for IPv6; the
  nftables dataplane, with kube-proxy in nftables mode; outgoing NAT on both families, so that
  Cluster API on `mgmt-1` reaches the workload API servers. The pools list every field the
  operator defaults, so Helm's server-side apply does not conflict with it on upgrade.
- The operator tolerates the `NoSchedule` taints it needs before the CNI is up, but not the
  cordon: upstream's blanket `NoSchedule` toleration lets a drained operator Pod return to
  the node being drained, so the drain never ends.
- MetalLB in native L2 mode as two releases: `metallb` (upstream with FRR and frr-k8s off;
  upstream's default is frr-k8s) and, once a server-side dry run proves the webhook answers,
  `metallb-config`: an IPv6 pool, an `L2Advertisement` on `eth1` from workers only (the
  interface selector alone does not decide which node leads an address), and Gate A.
- One implementation of each. Another CNI or load balancer is a new wrapper chart and a module
  change, not a toggle.

## Consequences

- Pod traffic between nodes is encapsulated; Pod egress is NAT'ed on the node and again by
  LXD on the host.
- No BGP, no eBPF dataplane. In L2 mode one worker answers neighbor discovery for each VIP:
  the external segment must be one L2 domain that reaches every worker's `eth1`.
- Calico's CRDs belong to its operator, not to a Helm release. An upgrade moves a wrapper
  chart's dependency ([upgrade-addons.md](../runbooks/upgrade-addons.md)); Gate B waits until
  the operator reports the new Calico version.
