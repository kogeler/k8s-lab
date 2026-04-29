# pivot_clusterctl_move

Pivot the bootstrap k3s management cluster onto a self-hosted target
management cluster (plan §18.1).

## Purpose

Drives the canonical CAPI bootstrap-and-pivot flow:

1. Materialise a runner-reachable kubeconfig for the target mgmt
   cluster — read the `<cluster>-kubeconfig` Secret from bootstrap,
   rewrite `clusters[].cluster.server` to
   `https://<lxd-host>:<api-proxy-port>` (port comes from the
   `k8s-lab.io/api-proxy-port` annotation on the Cluster CR, written by
   `charts/capi-workload-cluster`), pin
   `tls-server-name: kubernetes.default.svc`.
2. `clusterctl init --infrastructure incus:<ver>` against the target
   kubeconfig — same provider set the bootstrap cluster already runs.
3. `clusterctl move --to-kubeconfig` to relocate every CAPI CR
   (Cluster, ClusterClass, *Templates, KubeadmControlPlane,
   MachineDeployment, owned Machines + Secrets) from bootstrap to
   target.

The role is hard-gated on the global `k8s_lab_pivot_enabled` mode flag
(§3.1 — default `false`, MVP path). With the flag at its default, the
role is a documented no-op below preflight; flipping it to `true`
opts the entire repo into the Stage-2 pivot path.

## Out of scope

* **Target mgmt cluster CREATION** (Cluster CR + ClusterClass +
  Templates + LB instance + CNI). Brought up by the orchestrator —
  Helm install of `charts/capi-cluster-class` +
  `charts/capi-workload-cluster` with mgmt-topology values, plus
  `charts/cni-calico` against the result. The role assumes this is
  already done.
* **Bootstrap deletion** (the second half of §18.2 acceptance) is
  owned by `cleanup_bootstrap` (plan §19.1), invoked separately by the
  Phase 6 wrapper after this role completes.
* **Workload-cluster post-pivot creation** (Phase 7 — §18.3) is just
  another `make deploy-workload` against the new mgmt kubeconfig; this
  role does not orchestrate it.

## Requirements

* Pivot mode must be enabled — `k8s_lab_pivot_enabled: true` (global,
  see plan §8). Default `false` makes this role a no-op.
* `k8s_lab_lxd_host_address` (or the per-role default override
  `pivot_clusterctl_move_target_api_address`) must be set to a
  runner-reachable address of the LXD host — the rewritten kubeconfig
  points its `server:` URL at it.
* The target mgmt Cluster CR must already exist in
  `capi-clusters/<cluster_name>` on the bootstrap cluster, with the
  `k8s-lab.io/api-proxy-port` annotation populated and CNI installed
  (CAPI controllers and cert-manager need pod networking before
  `clusterctl init` can land).
* `clusterctl` binary present on the host (delivered by
  `binary_fetch`, transitively pulled in via the meta-chain
  `pivot_clusterctl_move → bootstrap_clusterctl → bootstrap_k3s →
  binary_fetch`).
* Bootstrap kubeconfig at
  `pivot_clusterctl_move_bootstrap_kubeconfig_path` (default
  `/opt/capi-lab/etc/bootstrap_clusterctl/bootstrap.kubeconfig`) —
  produced by `bootstrap_clusterctl`.

## Role variables

All public variables use the `pivot_clusterctl_move_*` prefix
(plan §2.6.2). Substrate-required values (CAPN provider name, TLS
server name, api-proxy-port annotation key, required Deployment list)
live in `vars/main.yml` as `_pivot_clusterctl_move_required_*` and are
NOT consumer-tunable — see role docstring for rationale.

| Variable | Default | Description |
| --- | --- | --- |
| `pivot_clusterctl_move_enabled` | `true` | Role-level toggle (still respects `k8s_lab_pivot_enabled`). |
| `pivot_clusterctl_move_bootstrap_kubeconfig_path` | `{{ k8s_lab_opt_root }}/etc/bootstrap_clusterctl/bootstrap.kubeconfig` | Source kubeconfig for `clusterctl move`. |
| `pivot_clusterctl_move_target_cluster_name` | `{{ k8s_lab_management_cluster_name | default('mgmt-1') }}` | Cluster CR name on bootstrap → target. |
| `pivot_clusterctl_move_target_cluster_namespace` | `capi-clusters` | Namespace of the target Cluster CR + kubeconfig Secret. |
| `pivot_clusterctl_move_target_api_address` | `{{ k8s_lab_lxd_host_address \| default('') }}` | Runner-reachable LXD host address (rewritten into target kubeconfig). |
| `pivot_clusterctl_move_clusterctl_path` | `/opt/capi-lab/bin/clusterctl` | Host-side clusterctl binary. |
| `pivot_clusterctl_move_capn_version` | `{{ k8s_lab_capn_provider_version }}` | CAPN release initialised on target. |
| `pivot_clusterctl_move_capn_provider_url` | upstream `infrastructure-components.yaml` URL | Override for airgap mirror. |
| `pivot_clusterctl_move_cluster_topology_enabled` | `true` | `CLUSTER_TOPOLOGY=true` env on init. |
| `pivot_clusterctl_move_extra_providers` | `[]` | Optional extras for `clusterctl.yaml` (each: `{name,url,type}`). |
| `pivot_clusterctl_move_extra_init_flags` | `[]` | Optional extra `clusterctl init` flags (each: `--<kind>=<provider>:<version>`). |
| `pivot_clusterctl_move_extra_wait_deployments` | `[]` | Optional extra Deployments waited on after init/move. |
| `pivot_clusterctl_move_init_timeout` | `600` | Wall-clock budget for `clusterctl init` (s). |
| `pivot_clusterctl_move_move_timeout` | `1200` | Wall-clock budget for `clusterctl move` (s). |
| `pivot_clusterctl_move_wait_target_kubeconfig_retries` | `90` | Poll attempts for the bootstrap-side `<cluster>-kubeconfig` Secret. |
| `pivot_clusterctl_move_wait_target_kubeconfig_delay` | `10` | Seconds between Secret polls. |
| `pivot_clusterctl_move_wait_retries` | `90` | Poll attempts for post-init Deployment Available + Cluster CR + livez. |
| `pivot_clusterctl_move_wait_delay` | `5` | Seconds between healthcheck polls. |
| `pivot_clusterctl_move_flow_control_*` | `true` | Coarse-grained per-section toggles (plan §2.6.3). |

## Tags

Both `_` and `-` spellings are accepted (plan §2.6.3):

* `pivot_clusterctl_move` / `pivot-clusterctl-move` — whole role.
* `pivot_clusterctl_move_preflight` — input validation only.
* `pivot_clusterctl_move_target_kubeconfig` — Secret read + rewrite.
* `pivot_clusterctl_move_config` — `clusterctl.yaml` render.
* `pivot_clusterctl_move_init` — `clusterctl init` on target.
* `pivot_clusterctl_move_move` — `clusterctl move`.
* `pivot_clusterctl_move_healthchecks` — post-pivot assertions.

## Idempotence

The role is a no-op across every combination of (init done?, move
done?). Two probes drive the gating:

* `init`: probe target for `apps/v1 Deployment capn-system/
  capn-controller-manager`. Present → init is already complete (it is
  all-or-nothing for clusterctl), task skips.
* `move`: probe bootstrap for `cluster.x-k8s.io/v1beta2 Cluster
  capi-clusters/<cluster_name>`. Absent → move already happened (move
  deletes from source after creating on target), task skips. Also
  drives the kubeconfig-acquisition fallback: when the CR is gone we
  reuse the on-disk kubeconfig from the previous converge instead of
  trying to read a Secret that no longer exists.

Re-running the role after a successful pivot is therefore reliably
`changed=false` end-to-end.

## Example

```yaml
- hosts: k8slab_host
  become: true
  vars:
    k8s_lab_pivot_enabled: true
  roles:
    - role: pivot_clusterctl_move
      vars:
        pivot_clusterctl_move_target_cluster_name: "mgmt-1"
        pivot_clusterctl_move_target_api_address: "203.0.113.10"
```

## Caveats

* **`clusterctl move` is bootstrap-wide within a namespace.** It moves
  every Cluster CR (and owned objects) in the namespace passed via
  `--namespace=`. With the default `pivot_clusterctl_move_target_cluster_namespace
  = capi-clusters`, every Cluster CR in `capi-clusters/` on bootstrap
  goes to target. The MVP scenario keeps only `mgmt-1` on bootstrap,
  so this is a feature, not a problem — but a deployment that already
  has multiple Cluster CRs co-located on bootstrap will pivot all of
  them in one shot.
* **CNI must be on target before init.** clusterctl init applies
  cert-manager + provider Deployments; without pod networking the
  Deployments crash-loop and `--wait-providers` times out. The role
  does NOT install CNI — that is the orchestrator's job before
  invoking pivot. A `helm install cni-calico --kubeconfig <target>`
  step belongs in the caller (TF module §16.4 or Molecule prepare).
* **Post-pivot bootstrap kubeconfig is a stale endpoint.** It still
  authenticates against the bootstrap cluster, which holds no CAPI
  CRs after the move; consumers should reach for the target mgmt
  kubeconfig (`pivot_clusterctl_move_target_kubeconfig_path`)
  thereafter. The Phase 6 wrapper deletes the bootstrap container via
  `cleanup_bootstrap` once the move is verified — this role does not
  do that itself.
* **Idempotence skips fail-fast on a stale on-disk kubeconfig.** If a
  consumer manually wipes the staging dir between a successful move
  and a re-converge, the role surfaces a concrete error instead of
  silently re-fetching from a Secret that no longer exists. Re-run
  the orchestrator step that creates the target mgmt cluster (so the
  Cluster CR is back on bootstrap) before re-converging.
