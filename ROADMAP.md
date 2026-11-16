# Roadmap

Work that is known and not done, with why it matters. Nothing here is
implemented; an item starts with an issue that agrees its design, and ends
with a decision record if it changes the architecture.

## Robustness found by the day-2 drills

- **Guard the add-on root against an unreachable cluster.** The Helm
  Terraform provider reads a release it cannot reach as deleted; an add-on
  apply while the cluster's API is down loses the releases from the state
  (recovery: [troubleshooting](doc/troubleshooting.md)). A plan-time check that
  the API answers would stop it before anything is lost.
- **Recovery from losing `mgmt-1` as a whole**, workload clusters still
  running: a new `mgmt-1`, `clusterctl move --from-directory` of the workload
  clusters' objects, re-adoption of their Helm releases. Outlined in
  [backup-restore.md](doc/runbooks/backup-restore.md), never exercised.
- **Scheduled backups** of `mgmt-1`'s etcd and its Cluster API objects instead
  of the manual runbook.
- **MachineHealthChecks** with a threshold that tolerates a host reboot (every
  node NotReady at once).
- **Tie the convergence check to a template change.** A change of the class
  values leaves the Cluster's generation as it is (only its class-revision
  annotation changes), so the check's conditions are already current for the
  old templates: it can pass in the moment before the topology controller has
  written the new template names into the control plane and the
  MachineDeployments. The time a Helm upgrade and the next apply take closes
  that gap in practice. Putting the class revision into the Cluster's spec
  (a field that raises its generation) or waiting for the template names
  closes it by design.
- **A Calico upgrade with Gate B's version wait in place**, and a MetalLB
  upgrade: not exercised yet for want of newer releases.
- **The variable-contract check per entry point.** It merges the inputs of a
  role's entry points, so an entry point that reads an input only another one
  declares passes; and it compares names, not an input's declared type with its
  default's.

## Upstream changes to adopt

- **Cluster API v1.15** (planned for December 2026): ClusterClass takes
  inline templates next to template references, which could replace the
  content-hash template objects; `ClusterTopology` on by default.
- **Material for MkDocs ends on 2027-05-05.** Its successor Zensical (beta)
  reads `mkdocs.yml`; the site's hook (`scripts/docs_hooks.py`) is not
  supported there yet.
- **vagrant-libvirt** has had no release since 0.12.2 (2023); the harness
  depends on it.
- **OpenTofu** as a second Terraform implementation in CI.
- **Dependency updates** stay manual (no Renovate): verify each pin upstream.

## Features

- **A private node-image path.** CAPN's image server publishes only some
  Kubernetes patch releases and may stop; building images with CAPN's image
  builder and serving them from a private simplestreams server removes both
  limits.
- **An alternative bootstrap cluster** (kind or a plain k3s container) where an
  LXC instance is not wanted.
- **Several MachineDeployments per cluster**: worker pools with their own
  size, image, labels and taints, upgraded one pool at a time.
- **Add-ons**: an ingress controller, a storage provisioner, cert-manager
  issuers for workloads, an observability stack — each its own chart.
- **Routed networks**: Pod IPv6 routed to the host instead of outgoing NAT
  (per-Pod traceability on the host); a BGP-routed external network with
  MetalLB in BGP mode instead of a router advertising one prefix.
- **HA assertions in the e2e verify**: replicas of every multi-replica
  component on different workers, one lease holder for leader-elected ones.
