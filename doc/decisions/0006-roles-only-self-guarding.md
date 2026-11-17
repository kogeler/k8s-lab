# 0006. Six self-guarding roles and reference playbooks, no deployment playbooks

Status: Accepted, 2026-11-16

## Context

Single-purpose roles chained through meta-dependencies pull every earlier role into a play:
applying a late one alone on a pivoted host would bring the bootstrap cluster back. A production playbook is copied from the repository's example and adapted, and
safety that lives in the example's order and conditions is lost by the first adaptation.

## Decision

- Six roles, each with one lifetime: `host` (packages, kernel, binaries), `lxd` (snap, bridge,
  project, pool, network, listener, profiles), `bootstrap` (the transient cluster; entry point
  `destroy`), `clusterctl` (providers on any management API; entry point `pivot`),
  `capn_identity`, `management_cluster` (`mgmt-1`; entry point `state`).
- No deployment playbooks. [`tests/playbooks/`](../../tests/playbooks/) holds the reference: a
  flat list of role invocations without conditions or per-call variables. A deployment copies
  it and changes `hosts:` and its inventory.
- Every role guards itself. `management_cluster : state` publishes `k8s_lab_management_state`
  (`absent`, `bootstrapping`, `self_hosted`) and refuses when instances of `mgmt-1` exist
  without either. `bootstrap` and `clusterctl : pivot` end at once on `self_hosted`;
  `bootstrap : destroy` refuses while the bootstrap API holds a Cluster; `lxd` never restarts
  an instance, re-addresses a network with instances or takes a used block device;
  `clusterctl` never downgrades a provider; a role listed twice converges once per managing API.
- Meta-dependencies only for hard prerequisites (`lxd` on `host`, `bootstrap` on `lxd`); a
  transient role is never a dependency of a permanent one.
- One house style: `tasks/main.yml` dispatches one file per area behind `<role>_enabled` and
  `<role>_flow_control_<area>`, tagged in kebab and snake case; task names
  `<role-kebab> | <area> | <action>`; inputs `<role>_*` in `defaults/main.yml`, internals
  `_<role>_*`; `meta/argument_specs.yml` declares every input
  ([roles.md](../reference/roles.md)); key material and kubeconfigs only under `no_log`.

## Consequences

- The reference playbook is safe to run any number of times on a live, pivoted host; the e2e
  scenario's second full run changes nothing and keeps every instance and Machine.
- A role applied alone or out of order does nothing or refuses with a message (the e2e verify
  applies each transient entry point alone on a pivoted host); a missing one goes unnoticed.
- Every run pays for the guards' reads of LXD and the managing API, and the `state` entry point
  must run first; the roles that need it fail without it and name it.
- Values a real host must choose are role inputs; `tests/playbooks/alt-vars.yml` changes every
  name, address, port and path and passes the substrate and bootstrap scenarios.
