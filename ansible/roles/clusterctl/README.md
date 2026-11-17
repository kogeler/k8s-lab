# clusterctl

## Purpose

The Cluster API providers (core, kubeadm bootstrap, kubeadm control plane, CAPN) on
whichever API manages mgmt-1, and the pivot onto mgmt-1 (`tasks_from: pivot`). One
implementation for the bootstrap cluster, for mgmt-1 and for provider upgrades.

## Requirements

- The `clusterctl` and `kubectl` binaries from `host`; a kubeconfig on the host.
- The published facts of `management_cluster` with `tasks_from: state`.

## Inputs

Declared in `meta/argument_specs.yml`, per entry point; the versions, names and
paths default to common variables and published facts
([variable contract](../../../doc/variable-contract.md)), the timeouts to literals.
`clusterctl_enabled` and `clusterctl_flow_control_{config,providers}`.

## What it changes

- `<opt_root>/etc/clusterctl/clusterctl.yaml`: the CAPN provider URL,
  `CLUSTER_TOPOLOGY`, and the optional cert-manager timeout.
- On the API behind `clusterctl_kubeconfig`: `clusterctl init` for missing
  providers, `clusterctl upgrade apply` for providers older than their pins, both
  with explicit versions and `--wait-providers`.
- `pivot`: the same against mgmt-1, then `clusterctl move` of the namespace.

## Re-running

Safe: with the pins unchanged nothing runs. A newer pin in the common variables
upgrades the providers in place (`CLUSTER_TOPOLOGY` comes from the config, so the
gate survives the upgrade); an installed provider newer than its pin fails the
role, since clusterctl cannot downgrade. The pivot runs only while the Cluster is
on the source; afterwards the play re-reads the management state.

## Removing

Nothing removes this; `clusterctl delete --all` would remove the providers.

## Tested by

`tests/molecule/bootstrap` (providers on the bootstrap cluster) and
`tests/molecule/e2e-local` (the pivot, providers on mgmt-1, the re-run).
