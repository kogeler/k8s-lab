# Upgrade Calico or MetalLB

## When to use

A new Calico or MetalLB release is to be adopted, or one of this repository's
add-on charts changed (`cni-calico`, `cni-calico-config`, `metallb`,
`metallb-config`). The upstream charts are dependencies of the wrapper charts
under `charts/`; a cluster gets a new version when its add-on releases are
upgraded — by the management playbook for `mgmt-1`, by each add-on root for a
workload cluster.

## Preconditions

- Release notes read. Calico upgrades from the two previous minor releases;
  the tigera-operator chart carries no CRDs, the operator applies them when its
  new Pod starts (`manageCRDs`). The MetalLB chart upgrades its own CRDs; this
  repository runs it in native L2 mode (`speaker.frr.enabled` and
  `frrk8s.enabled` false).
- The new version supports the clusters' Kubernetes versions.
- The cluster is `Available` and its API answers (an add-on root refreshed
  while it does not loses its releases — [troubleshooting](../troubleshooting.md)).

## Steps

1. In the wrapper chart (`charts/cni-calico/Chart.yaml` or
   `charts/metallb/Chart.yaml`): the dependency's `version`, the matching
   `appVersion`, and the chart's own `version` (a patch or minor bump). For
   Calico also `appVersion` (and `version`) of `charts/cni-calico-config`:
   Gate B waits until the operator reports that version on every node, and
   `make check` refuses a mismatch.
2. Update the dependency and check the result:

   ```bash
   helm dependency update charts/cni-calico
   make check
   ```

   This rewrites `Chart.lock`, which is committed; the archive under
   `charts/cni-calico/charts/` is not committed: `make deps` and every install
   fetch it.
3. `mgmt-1`: run `<playbook>`. The releases are upgraded in place; the run
   ends with every gate.
4. Each workload cluster: apply its add-on root. A changed release re-runs what
   depends on it: after `cni-calico` or `cni-calico-config`, the wait for the
   Calico CRDs and Gate B; after `metallb` or `metallb-config`, the wait for the
   MetalLB webhook and Gate A. The convergence check runs only when the
   Cluster changes.

   ```bash
   terraform -chdir=<root>/addons plan
   terraform -chdir=<root>/addons apply
   ```

## Verify

```bash
helm list -A --kubeconfig <cluster kubeconfig>
kubectl --kubeconfig <cluster kubeconfig> -n tigera-operator get deploy tigera-operator \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl --kubeconfig <cluster kubeconfig> -n calico-system rollout status daemonset calico-node
kubectl --kubeconfig <cluster kubeconfig> -n metallb-system get pods
```

The releases show the new chart versions, the images the new release, the
DaemonSets rolled out, `kubectl --kubeconfig <cluster kubeconfig> get
installation default -o jsonpath='{.status.calicoVersion}'` the new Calico
version; the gate of the upgraded add-on passed in the apply (every gate in the
playbook run).

## Rollback

Set the previous versions in the wrapper chart, update the dependency again
and repeat steps 3–4. Read the release notes first: an upgrade that changed CRDs may not
go back cleanly.

## Tested

2026-11-16, harness: Calico v3.33.0 → v3.33.1 (released that day) with the
steps above — the dependency and appVersion of `cni-calico`, the appVersion of
`cni-calico-config`, `helm dependency update`, `make check`, one playbook run
for both clusters (the converge applies the add-on root too): the operator
became v1.44.1 on both, the releases upgraded in place, and the `Installation`
reported v3.33.1 once the last calico-node was updated, about two minutes after
the operator — the moment Gate B waits for (its wait was run afterwards on both
clusters and passed; by hand it times out for v3.33.0). Not exercised: an
upgrade with that wait already in place (no newer Calico), and a MetalLB
upgrade (0.16.2 is the newest release; its steps are the same).
