# Upgrade Cluster API and CAPN

## When to use

A new release of Cluster API (core, kubeadm bootstrap, kubeadm control plane —
one version for all three) or of CAPN is to be adopted. cert-manager comes
along: `clusterctl` upgrades it to the version the new binary carries.

## Preconditions

- Release notes read for every version between the installed one and the
  target. Some upgrades carry their own step: CAPN v0.9.0, for example, asks
  for every Cluster API controller to be restarted after upgrading to it.
- The target versions support each other and the Kubernetes versions in use
  (Cluster API's support matrix, CAPN's compatibility table). `clusterctl`
  upgrades across at most three minor versions and never downgrades.
- Every cluster is stable:

  ```bash
  kubectl --kubeconfig $MGMT get clusters -A
  ```

  shows `AVAILABLE True` for each.
- A backup of `mgmt-1` ([backup-restore.md](backup-restore.md)): the
  controllers being replaced run on `mgmt-1` itself.

## Steps

1. Read what is installed:

   ```bash
   kubectl --kubeconfig $MGMT get providers.clusterctl.cluster.x-k8s.io -A \
     -o custom-columns=NAME:.metadata.name,TYPE:.type,VERSION:.version --no-headers
   ```

2. Raise the pins in `group_vars/all.yml`: `k8s_lab_clusterctl_version` (the
   three Cluster API providers and the `clusterctl` binary) together with
   `k8s_lab_clusterctl_sha256`, and `k8s_lab_capn_provider_version`. Upstream
   publishes no checksum file for `clusterctl`: compute it once and pin it (the
   bare hex digest; the role adds the `sha256:` prefix):

   ```bash
   curl -sSfL https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.14.4/clusterctl-linux-amd64 \
     | sha256sum
   ```

3. Run `<playbook>`. Role `host` installs the new `clusterctl`; role
   `clusterctl` renders its configuration for the new CAPN release, compares
   every installed provider with its pin and runs `clusterctl upgrade apply`
   with explicit versions for the older ones. The rendered configuration sets
   `CLUSTER_TOPOLOGY`, so the `ClusterTopology` feature gate survives the
   upgrade (the provider manifests default it to off). A provider newer than
   its pin stops the run before anything changes.

   While the controllers are replaced nothing reconciles; the clusters keep
   running.

## Verify

```bash
kubectl --kubeconfig $MGMT get providers.clusterctl.cluster.x-k8s.io -A \
  -o custom-columns=NAME:.metadata.name,VERSION:.version --no-headers
kubectl --kubeconfig $MGMT get deploy -A -l clusterctl.cluster.x-k8s.io \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas --no-headers
kubectl --kubeconfig $MGMT -n capi-system get deploy capi-controller-manager \
  -o jsonpath='{.spec.template.spec.containers[0].args}'
kubectl --kubeconfig $MGMT get clusters -A \
  -o custom-columns=NAME:.metadata.name,AVAILABLE:.status.conditions[?\(@.type==\"Available\"\)].status,TOPOLOGY:.status.conditions[?\(@.type==\"TopologyReconciled\"\)].status --no-headers
```

Every provider at its pin and its controller ready; the core controller's
`--feature-gates` contain `ClusterTopology=true`; every cluster `True True`.
The real proof is the next topology change being reconciled — on the harness
the workload Kubernetes upgrade ([upgrade-kubernetes.md](upgrade-kubernetes.md))
ran right after this one.

## Rollback

`clusterctl` does not downgrade, and the playbook refuses to try. A failed or
interrupted upgrade is completed by running `<playbook>` again: it compares the
versions anew. A bad release is fixed forward with the next patch release; the
last resort is the disaster recovery in [backup-restore.md](backup-restore.md).

## Tested

2026-11-16, harness: installed on Cluster API v1.14.3 and CAPN v0.9.0
(cert-manager v1.21.2), pins raised to v1.14.4 and v0.9.1. The playbook run
took 2.5 minutes with three changes (the binary, its configuration, the
upgrade — 112 s, cert-manager to v1.21.3 included); the Terraform roots were
unchanged. Both clusters stayed `Available`, the gate stayed on, and the
workload upgrade that followed was reconciled.
