# bootstrap_clusterctl

Run `clusterctl init` against the bootstrap k3s cluster to install
cert-manager, the core Cluster API providers and the CAPN
(`cluster-api-provider-incus`) infrastructure provider. Plan §15.3.

## Scope

* materialise a host-side kubeconfig pointing at the bootstrap
  container's eth0 IPv4 (rewriting k3s' default `127.0.0.1` server URL);
* render a pinned `clusterctl.yaml` declaring the CAPN provider entry;
* run `clusterctl init --infrastructure incus:<version>` once
  (idempotently — pre-checks for an existing CAPN controller
  Deployment and skips if present);
* wait for cert-manager + CAPI/CAPN controller Deployments to report
  Available;
* assert `clusterctl get providers` lists all four expected provider
  types.

## Out of scope

* publishing the bootstrap API outside the host — opt-in LXD proxy
  device on the bootstrap instance, plan §15.5; host firewall is
  out-of-project-scope, plan §11.4;
* creating the LXD identity Secret CAPN reads to talk to the host
  daemon (`bootstrap_capn_secret`, plan §15.4);
* exporting `bootstrap.kubeconfig` to the runner side
  (`export_artifacts`, plan §15.6).

## Execution model

clusterctl + kubectl land on the LXD host through `binary_fetch` (plan
§15.1). This role drives them from the host — never from inside the
bootstrap container — using a kubeconfig fetched via `lxc file pull`
and rewritten so `clusters[].cluster.server` points at the container's
eth0 IPv4 instead of the in-container `127.0.0.1`. Same SSH→host
boundary that `bootstrap_k3s` uses, no extra connection plugin needed.

## Idempotence

`clusterctl init` is not idempotent (a second invocation against an
already-initialised cluster fails with `there is already an instance
of the "<provider>" provider installed`). The role pre-checks the
CAPN controller Deployment via kubectl: if it exists, `clusterctl
init` is skipped entirely. The healthcheck pass still re-asserts
every provider Deployment is Available, so the second converge
remains a useful drift detector.

## Substrate-required vs. tunable

Memory rule `feedback_required_values_hardcoded.md`. `vars/main.yml`
holds everything whose empty / wrong override would silently break
Stage 1 — the public surface in `defaults/main.yml` cannot reach
these values:

* `_bootstrap_clusterctl_required_provider_name` (`incus`) —
  embedded in `clusterctl init --infrastructure <name>:<ver>` and
  in the rendered clusterctl.yaml entry; the upstream CAPN registry
  only knows that name;
* `_bootstrap_clusterctl_required_deployments` and
  `_bootstrap_clusterctl_required_cert_manager_deployments` — the
  4 + 3 controller Deployments healthchecks wait on; missing any
  means the management cluster is dead-on-arrival;
* `_bootstrap_clusterctl_lxd_socket` and
  `_bootstrap_clusterctl_lxc_cli` — snap-LXD invariants fixed by
  lxd_host's snap install;
* `_bootstrap_clusterctl_container_kubeconfig_path`
  (`/etc/rancher/k3s/k3s.yaml`) — k3s always writes here.

Public defaults expose only legitimately tunable surface: CAPN
version pin, provider URL (overridable for airgap mirrors),
ClusterClass topology toggle, extra providers / init flags / wait
deployments, timeouts, paths owned by the role itself.

## Public variables

See `defaults/main.yml` for the full list with inline rationale.

## Testing

Molecule scenario: `tests/molecule/bootstrap_clusterctl/`. Runs the
full meta-dep chain end-to-end on a Vagrant VM (plan §9.1):
`base_system → lxd_host → lxd_project → lxd_storage_pools →
lxd_network_int_managed → lxd_profiles → binary_fetch →
lxd_bootstrap_instance → bootstrap_k3s → bootstrap_clusterctl`.
