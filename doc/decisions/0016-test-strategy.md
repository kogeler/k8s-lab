# 0016. Tests follow the reference playbooks on a local VM; day-2 operations are executed runbooks

Status: Accepted, 2026-11-16

## Context

The roles change a real host: packages, kernel modules, systemd-networkd, a block device, LXD.
The flow builds two clusters, pivots, then adds a third through Terraform. Lint proves little
about that. Scenarios per role miss what the roles do together; a workload cluster installed
by anything but the Terraform roots leaves the modules untested; an operation that is only
described (an upgrade, a rotation, a recovery) is not known to work.

## Decision

- Static and render checks are one target, `make check`: linters, the variable contract,
  `terraform test` with mocked providers, `helm template` into kubeconform, the class-name
  check, `mkdocs build --strict`. CI runs it on every push and pull request.
- Molecule scenarios follow the reference playbooks, not roles: `substrate`
  (`substrate.yml`), `bootstrap` (up to the CAPN identity) and `e2e-local` (`management.yml`,
  then the workload fixture through both Terraform roots). Each converges, converges again
  without a change, and checks behavior. `substrate` and `bootstrap` also pass with
  `tests/playbooks/alt-vars.yml`.
- The local test host is a Debian 13 VM under Vagrant and libvirt (12 GiB and 8 vCPUs by
  default), driven only through `make` (`vm-up`, `test-*`, `vm-destroy`).
- The e2e verify checks re-run safety (nothing re-created, each transient entry point alone a
  no-op), zero-diff plans, scaling and destroy through both roots, routing and NodePorts per
  node, and each cluster's VIP from the host and from a client in another prefix.
- The `gha` scenario is the e2e scenario with a GitHub Actions `ubuntu-26.04` runner as the
  host, on pull requests that touch code, on `main`, nightly and on demand. It rewrites the
  runner's swap, disks and network, so `make test-gha` and its playbooks refuse to run
  anywhere else.
- Every day-2 operation has a runbook ([runbooks](../runbooks/README.md)), drilled on the
  harness; its *Tested* line gives the date and what was not exercised.

## Consequences

- What the tests run is what a deployment runs: the roles, the modules, the charts.
- The e2e needs a machine with KVM and takes 15 to 20 minutes on a fresh VM; the VM holds
  `mgmt-1` and at most two small workload clusters.
- The external network is simulated on the test host (radvd on a veth pair, a client in a
  network namespace behind it); a real uplink and provider router stay untested.
- Runbooks are proven by one drill, not continuously. Not exercised, among others: an LXD
  channel change, the loss of `mgmt-1` as a whole, the control-plane rollout before
  certificate expiry; each runbook's *Tested* line names the rest.
