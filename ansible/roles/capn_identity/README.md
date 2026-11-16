# capn_identity

## Purpose

The LXD client identity CAPN uses: a key and certificate on the host, a trust entry
restricted to the one LXD project, and the CAPN identity Secret on whichever API
manages mgmt-1 (the bootstrap cluster, later mgmt-1 itself). It does not configure
the LXD API listener (role `lxd`).

## Requirements

- LXD with its HTTPS listener (role `lxd`) on the host; the published facts of
  `management_cluster` with `tasks_from: state`.
- Collections `community.crypto` and `kubernetes.core`; the Kubernetes Python client on
  the runner.

## Inputs

Declared in `meta/argument_specs.yml`; the names, paths and the managing API default
to common variables and published facts
([variable contract](../../../doc/variable-contract.md)), the rest (rotation,
validity, namespaces) to literals.
`capn_identity_enabled` and `capn_identity_flow_control_{certificate,trust,secret}`.

## What it changes

- `<opt_root>/etc/capn_identity/client.key` (0600; outside the cluster's Secrets the only
  copy) and `client.crt`.
- LXD: a `client` trust entry named `k8slab-capn-<first 12 hex of its fingerprint>`,
  restricted to the project (LXD requires unique names, so two identities can be trusted
  side by side during a rotation).
- On the managing API: each namespace in `capn_identity_namespaces` and in it the
  Secret (`server`, `server-crt`, `client-crt`, `client-key`, `project`, label
  `clusterctl.cluster.x-k8s.io/move`), server-side applied with field manager `k8s-lab`.

## Re-running

Safe: an existing key and certificate are kept, the trust entry is added only when
its fingerprint is missing, the Secrets are re-applied. After the pivot the Secrets
are maintained on mgmt-1. Key material never appears in the log or in a fact file.

Rotation (`capn_identity_rotate: true`, or a missing key file) in one run: new key and
certificate → trusted next to the old one → Secrets updated → an LXD call with the
new certificate must succeed → trust entries of the same project named
`k8slab-capn-<12 hex>` with another fingerprint are removed. A rotation interrupted before the last step is completed by
the next run (the new key is kept, so it does not rotate again). CAPN reads the Secret on every reconcile; nothing restarts.

## Removing

Nothing removes this. To revoke by hand: `lxc config trust remove <fingerprint>` and
delete the Secrets.

## Tested by

`tests/molecule/bootstrap` (`verify/providers.yml`: Secret against the live LXD) and
`tests/molecule/e2e-local` (on mgmt-1 after the pivot: key mode, server-side apply, one
trust entry). Rotation was drilled by hand on the e2e harness: converge with
`capn_identity_rotate: true`, then a replaced worker Machine.
