# bootstrap_capn_secret

Materialise the LXD identity Secret CAPN reads to talk to the host
LXD daemon. Plan §13.11.

## Scope

* enable LXD HTTPS API listener on the LXD-managed internal bridge IP
  so the bootstrap LXC can reach `/1.0/...` over the project's
  internal network and nothing leaks onto external NICs;
* generate a self-signed client TLS cert/key with community.crypto;
* trust that cert in LXD as a `client`-type entry restricted to the
  project named by `k8s_lab_project_name` — CAPN cannot touch foreign
  projects;
* render + apply the CAPN identity Secret in **every** namespace
  listed in `bootstrap_capn_secret_namespaces` (sourced from
  `k8s_lab_capn_identity_namespaces`, plan §8 default
  `["capi-clusters"]`). Each Secret carries the five keys per
  [identity-secret.html][1]: `server`, `server-crt`, `client-crt`,
  `client-key`, `project`. The role also ensures each target
  namespace exists before applying the Secret;
* attach `clusterctl.cluster.x-k8s.io/move: "true"` label (default)
  so `clusterctl move` carries the Secrets across to the post-pivot
  management cluster. Pivot is mandatory in the canonical k8s-lab
  flow (plan §3 + §10); flip
  `bootstrap_capn_secret_pivot_enabled=false` only for ad-hoc
  substrate-only test runs.

The Secret is **not** placed in the CAPN controller namespace
(`capn-system`). CAPN v1alpha2 `LXCCluster.spec.secretRef` does not
carry a namespace field — CAPN looks the Secret up in the namespace of
the LXCCluster CR (i.e. the workload Cluster CR's own namespace), so
the role fans the Secret out across every workload-cluster namespace.

## Out of scope

* publishing the bootstrap API on a host port — opt-in LXD proxy
  device on the bootstrap instance, plan §15.5; host firewall is
  out-of-project-scope, plan §11.4;
* exporting the host-side kubeconfig to the runner as
  `.artifacts/mgmt.kubeconfig` (`export_artifacts`, plan §15.6);
* Cluster CR lifecycle (Phase 5+, plan §16).

## Idempotence

* LXD `core.https_address` — read live config, PATCH only on drift,
  poll until the listener accepts requests;
* client cert — `community.crypto.{openssl_privatekey, openssl_csr,
  x509_certificate}` are file-state idempotent;
* LXD trust store — probed by SHA256 fingerprint; POST only when the
  entry is absent. Existing entry with mismatched project restriction
  fails loud rather than silently relaxing scope;
* target namespaces — `kubernetes.core.k8s` server-side apply is a
  no-op when the Namespace already exists;
* Secret apply — server-side apply with `apply: true` is reconciling
  per namespace; the rendered manifest is byte-stable for the same
  inputs so `unchanged` is the steady-state output across the entire
  fanout. Pivot label flip via `bootstrap_capn_secret_pivot_enabled`
  propagates cleanly through every target namespace in one rerun.

Empty `bootstrap_capn_secret_namespaces` (and equivalently
`k8s_lab_capn_identity_namespaces: []`) is a valid configuration:
HTTPS listener + LXD trust still execute (substrate-level concerns
that have no per-cluster fanout), and Secret apply / healthchecks
short-circuit. Useful for ad-hoc reruns where the operator only wants
to refresh the host-side prerequisites.

## Substrate-required vs. tunable

Memory rule `feedback_required_values_hardcoded.md`. `vars/main.yml`
holds everything whose empty / wrong override would silently break
Stage 1 — the public surface in `defaults/main.yml` cannot reach
these values:

* `_bootstrap_capn_secret_required_lxd_https_port` (`8443`) — the
  CAPN-wide port convention; CAPN tutorials and host firewall rules
  in §15.5 target it;
* `_bootstrap_capn_secret_required_keys` — the five identity-spec
  data keys CAPN demands;
* `_bootstrap_capn_secret_required_trust_type` (`client`) — only
  trust type that honours `restricted: true + projects: [<list>]`;
* `_bootstrap_capn_secret_lxd_socket`,
  `_bootstrap_capn_secret_lxd_server_cert_path` — snap-LXD invariants
  fixed by lxd_host's snap install.

Public defaults expose only legitimately tunable surface: cert
metadata (CN, country, organization, validity, key size/type),
staging paths, the auto-resolve override
(`bootstrap_capn_secret_lxd_https_bind_address`), and wait timing.

Four public defaults source from the project-wide §8 contract so a
single global flip stays coordinated with downstream consumers:

* `bootstrap_capn_secret_name` ← `k8s_lab_infrastructure_secret_name`
  — must match the Cluster CR's `identityRef.name` in §16.x;
* `bootstrap_capn_secret_namespaces` ← `k8s_lab_capn_identity_namespaces`
  — Secret fanout target list, must include every namespace where
  workload Cluster CRs (and thus LXCCluster CRs) will be created;
* `bootstrap_capn_secret_lxd_project` ← `k8s_lab_project_name` —
  CAPN reads this on every Cluster reconcile to scope every
  LXCMachine call;
* `bootstrap_capn_secret_internal_network_name` ←
  `k8s_lab_internal_network_name` — drives auto-resolution of
  `core.https_address` to the bridge gateway IPv4.

## Testing

Molecule scenario: `tests/molecule/bootstrap-capn-secret/`. Runs the
full meta-dep chain end-to-end on a Vagrant VM (plan §9.1):
`base_system → … → bootstrap_clusterctl → bootstrap_capn_secret`.

[1]: https://capn.linuxcontainers.org/reference/identity-secret.html
