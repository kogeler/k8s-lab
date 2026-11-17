# Architecture decisions

Why the repository is built the way it is: one record per decision, with its consequences.

| # | Decision | Status |
|---|---|---|
| [0001](0001-single-host-reusable-building-blocks.md) | One host, reusable building blocks; deployments live in a consumer repository | Accepted, 2026-11-16 |
| [0002](0002-unprivileged-lxc-nodes.md) | Nodes are unprivileged LXC system containers, with no privileged path | Accepted, 2026-11-16 |
| [0003](0003-lxd-snap-held-channel.md) | LXD comes from the snap on a pinned channel, with its automatic refreshes held | Accepted, 2026-11-16 |
| [0004](0004-bootstrap-cluster-and-mandatory-pivot.md) | A transient k3s bootstrap cluster in a container, then a mandatory pivot to `mgmt-1` | Accepted, 2026-11-16 |
| [0005](0005-one-owner-per-cluster.md) | One owner per cluster: Ansible for the host and `mgmt-1`, Terraform for workload clusters | Accepted, 2026-11-16 |
| [0006](0006-roles-only-self-guarding.md) | Six self-guarding roles and reference playbooks, no deployment playbooks | Accepted, 2026-11-16 |
| [0007](0007-common-variable-contract.md) | Common variables `k8s_lab_*` are a checked contract; there is no globals role | Accepted, 2026-11-16 |
| [0008](0008-helm-charts-only.md) | Helm charts carry every Kubernetes object the repository creates | Accepted, 2026-11-16 |
| [0009](0009-clusterclass-content-hash-names.md) | One ClusterClass per cluster, its templates named after a hash of their content | Accepted, 2026-11-16 |
| [0010](0010-terraform-two-roots.md) | A workload cluster is two provider-less modules applied from two roots | Accepted, 2026-11-16 |
| [0011](0011-dual-nic-network-contract.md) | Two NICs per node: `eth0` carries the node, `eth1` answers what arrives on it | Accepted, 2026-11-16 |
| [0012](0012-api-publication-lxd-proxy.md) | API servers are published through LXD proxy devices; the host firewall is out of scope | Accepted, 2026-11-16 |
| [0013](0013-calico-and-metallb.md) | Calico with VXLAN and nftables, MetalLB in native L2 mode, each as two releases | Accepted, 2026-11-16 |
| [0014](0014-acceptance-gates-as-helm-tests.md) | Acceptance gates and the convergence check are Helm tests | Accepted, 2026-11-16 |
| [0015](0015-pinned-verified-dependencies.md) | Every dependency is pinned at its latest stable release and verified | Accepted, 2026-11-16 |
| [0016](0016-test-strategy.md) | Tests follow the reference playbooks on a local VM; day-2 operations are executed runbooks | Accepted, 2026-11-16 |
