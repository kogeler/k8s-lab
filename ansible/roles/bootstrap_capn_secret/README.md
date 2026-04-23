# bootstrap_capn_secret

Materialise the LXD identity Secret CAPN reads to talk to the host
LXD daemon. Plan §15.4.

## Scope

* enable LXD HTTPS API listener on the capi-int bridge IP so the
  bootstrap LXC can reach `/1.0/...` over the project's internal
  network and nothing leaks onto external NICs;
* generate a self-signed client TLS cert/key with community.crypto;
* trust that cert in LXD as a `client`-type entry restricted to
  project `capi-lab` — CAPN cannot touch foreign projects;
* render + `kubectl apply` the CAPN identity Secret in `capn-system`
  with the five required keys (`server`, `server-crt`, `client-crt`,
  `client-key`, `project`) per
  [identity-secret.html][1];
* attach `clusterctl.cluster.x-k8s.io/move: "true"` label only when
  `bootstrap_capn_secret_pivot_enabled=true` so `clusterctl move`
  carries the Secret across to the post-pivot management cluster.

## Out of scope

* publishing the bootstrap API on a host port — opt-in LXD proxy
  device on the bootstrap instance, plan §15.5; host firewall is
  out-of-project-scope, plan §11.4;
* exporting `bootstrap.kubeconfig` to the runner side
  (`export_artifacts`, plan §15.6);
* Cluster CR lifecycle (Phase 5+).

## Idempotence

* LXD `core.https_address` — read live config, PATCH only on drift,
  poll until the listener accepts requests;
* client cert — `community.crypto.{openssl_privatekey, openssl_csr,
  x509_certificate}` are file-state idempotent;
* LXD trust store — probed by SHA256 fingerprint; POST only when
  the entry is absent. Existing entry with mismatched project
  restriction fails loud rather than silently relaxing scope;
* Secret apply — `kubectl apply -f` is server-side reconciling; the
  rendered manifest is byte-stable for the same inputs so
  `unchanged` is the steady-state output.

## Substrate-required vs. tunable

Memory rule `feedback_required_values_hardcoded.md`. `vars/main.yml`
holds everything whose empty / wrong override would silently break
Stage 1 — the public surface in `defaults/main.yml` cannot reach
these values:

* `_bootstrap_capn_secret_required_namespace` (`capn-system`) — fixed
  by the upstream CAPN release manifest (v0.8.x);
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

Two public defaults source from the project-wide §8 contract so a
single global flip stays coordinated with downstream consumers:

* `bootstrap_capn_secret_name` ← `k8s_lab_infrastructure_secret_name` —
  must match the Cluster CR's `identityRef.name` in Phase 5+
  (`§16.4` / `§16.5`);
* `bootstrap_capn_secret_pivot_enabled` ← `k8s_lab_pivot_enabled` —
  drives the `clusterctl.cluster.x-k8s.io/move=true` label that
  `clusterctl move` (`§18`) follows.

## Testing

Molecule scenario: `tests/molecule/bootstrap-capn-secret/`. Runs the
full meta-dep chain end-to-end on a Vagrant VM (plan §9.1):
`base_system → … → bootstrap_clusterctl → bootstrap_capn_secret`.

[1]: https://capn.linuxcontainers.org/reference/identity-secret.html
