# bootstrap

## Purpose

The transient k3s cluster that installs the Cluster API providers and creates
mgmt-1, and its guarded removal (`tasks_from: destroy`). It does nothing once
mgmt-1 manages itself.

## Requirements

- Role `lxd` (a dependency: the project, network and the `capi-base` /
  `capi-bootstrap` profiles), and the k3s and kubectl binaries from `host`.
- The published fact `k8s_lab_management_state`: run `management_cluster` with
  `tasks_from: state` first.
- Collection `community.general`.

## Inputs

Declared in `meta/argument_specs.yml`; every `bootstrap_*` input defaults to a
common variable ([variable contract](../../../doc/variable-contract.md)) or to a
value that suits a real host. `bootstrap_enabled` and one
`bootstrap_flow_control_<area>` per area (`instance`, `k3s`, `kubeconfig`).

## What it changes

- LXD: instance `<bootstrap_instance_name>` in the project, from `debian/13/cloud`,
  with a proxy device `k3s-api` that publishes the k3s API on
  `<bootstrap_api_listen_address>:<bootstrap_api_port>` of the host.
- In the instance: `/usr/local/bin/k3s`, `/etc/rancher/k3s/config.yaml` (dual-stack,
  no ingress, load balancer or network policy), the `k3s` unit.
- `<opt_root>/etc/bootstrap/` (staging) and `<opt_root>/etc/bootstrap.kubeconfig` on
  the host, `<artifacts_dir>/bootstrap.kubeconfig` on the runner: the same content,
  pointing at the published API.

## Re-running

While mgmt-1 is not self-hosted, a re-run resumes: files are pushed only when their
checksum differs, k3s is started once and restarted only after such a push. On a
self-hosted mgmt-1 the role ends at once.

## Removing

`tasks_from: destroy` refuses unless the management state is `self_hosted` and the
bootstrap API holds no `Cluster`, and fails when LXD does not answer; then it
deletes the instance, both kubeconfigs and the staging directory.

## Tested by

`tests/molecule/bootstrap` (`verify/instance.yml`, `verify/runner.yml`) and
`tests/molecule/e2e-local` (the removal, and the re-run on a pivoted host).
