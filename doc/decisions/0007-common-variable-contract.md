# 0007. Common variables `k8s_lab_*` are a checked contract; there is no globals role

Status: Accepted, 2026-11-16

## Context

Several roles, and Terraform, must agree on some values: the LXD project, the management
cluster's name, the cluster namespace, the CAPN identity Secret's name, the address published
APIs listen on, the version pins. Read as `{{ k8s_lab_opt_root | default('/opt/capi-lab') }}`
in many places, a missing value goes unnoticed and a documented list drifts from what the
roles read. Whoever writes a
deployment's variables needs one list that is true.

## Decision

- Common variables are named `k8s_lab_*`, defined by no role and all required: a default in a
  shared place would let a deployment run without choosing a value two components must agree
  on. A deployment sets them in `group_vars/all.yml` next to its playbook; the reference is
  [`tests/playbooks/group_vars/all.yml`](../../tests/playbooks/group_vars/all.yml).
- A role reads a common variable only in `defaults/main.yml`, as the default of its own input
  (`lxd_project_name: "{{ k8s_lab_project_name }}"`), and declares it as required in
  `meta/argument_specs.yml`.
- Apart from the version pins, kept together on purpose, a value with one reader is a role
  input (the internal network's addresses, the bootstrap API port). Inputs without a sensible
  default are required:
  `lxd_uplink_interface`, `lxd_storage_source`, `management_cluster_external_ipv6_prefix`,
  `management_cluster_metallb_vip_range_v6`.
- Facts roles publish for each other carry the prefix too: `k8s_lab_management_state` and the
  host and runner paths of the managing API's kubeconfig.
- [variable-contract.md](../variable-contract.md) lists all of it; its tables are generated
  from the roles. `make check`
  ([`check_variable_contract.py`](../../scripts/check_variable_contract.py)) fails when the
  page is stale, or a common variable is set but unread, read but unset, read outside
  `defaults/`, undeclared, or declared differently by two roles.

## Consequences

- One page answers "what must a deployment set", one search answers "who reads it".
- Seventeen common variables and four required inputs have no default: a missing one fails at
  role start, by name. A deployment can still give one role a different view through that
  role's input.
- A variable change is one change across the role, the reference file and the contract page,
  or `make check` fails.
