# 11 — Operations

This chapter is the day-2 manual: what to do once a lab is alive.
Inspecting kubeconfigs, adding workload clusters on top of an existing
mgmt-1, tearing things down cleanly, upgrading versions, rotating the
CAPN identity Secret, backups, and the small set of recurring
operational checks worth knowing by heart.

The runner-side source of truth for every operation in this chapter is
the root `Makefile`. Per the project rule [`feedback_makefile_only`],
direct invocations of `terraform`, `vagrant`, `virsh`, `helm`,
`kubectl`, `lxc` against the running lab go through the Make targets
documented here — not through ad-hoc shell.

For the architecture behind the bootstrap → pivot → workload graph, see
[`02-architecture.md`](02-architecture.md). For consumer-repo
deployment, see [`07-deployment-guide.md`](07-deployment-guide.md).

---

## 1. Kubeconfigs

### 1.1. The single `mgmt.kubeconfig`

The runner keeps **one** management-cluster kubeconfig at
`.artifacts/mgmt.kubeconfig`. It is gitignored, mode `0600`, owned by
the runner user (plan `§11.1`).

The same path lives through the entire canonical sequence:

1. Phase 4 `export_artifacts` writes the **bootstrap k3s** admin
   kubeconfig to that path. Server URL points at the LXD proxy device
   (`https://<vagrant-vm>:16443` in local mode, or the equivalent
   host-side endpoint in production).
2. After pivot (`pivot_clusterctl_move`), a **second include** of
   `export_artifacts` rewrites the same file in place with the
   self-hosted **mgmt-1** admin kubeconfig.
3. After `cleanup_bootstrap`, the bootstrap LXC is gone and the only
   credentials in the file are mgmt-1's.

This is deliberate: every runner-side consumer (`terraform`, the
Molecule e2e-local verify scenarios, manual `kubectl` inspection) keeps
the same path through the entire lifecycle and always points at the
currently-authoritative management cluster. See plan `§11.1`.

### 1.2. Workload kubeconfigs

The Terraform module `workload_cluster` does **not** copy the workload
kubeconfig to disk. It keeps it inside `terraform.tfstate` and exposes
it via `terraform output -raw kubeconfig`.

To materialise the workload kubeconfig as a file:

```bash
make workload-kubeconfig
# → wrote /media/data/git/k8s-lab/.artifacts/clusters/<cluster_name>.kubeconfig
```

The target reads `cluster_name` from the TF state of the active
fixture, runs `terraform output -raw kubeconfig`, and writes the file
under `umask 077` (mode `0600`) to
`.artifacts/clusters/<cluster_name>.kubeconfig`.

Per-workload kubeconfigs in `.artifacts/clusters/` are **debug copies**
— they are gitignored and treated as throwaway. The authoritative copy
lives in TF state (or, in production, in whatever secret store the
consumer repo provides).

### 1.3. Inspecting cluster state

With `mgmt.kubeconfig` in hand, the canonical management-side health
inspection is:

```bash
export KUBECONFIG=$(pwd)/.artifacts/mgmt.kubeconfig

# CAPI universe
kubectl get clusters,machinedeployments,kubeadmcontrolplanes -A

# CAPI controllers themselves
kubectl get pods \
  -n capi-system \
  -n capi-kubeadm-bootstrap-system \
  -n capi-kubeadm-control-plane-system \
  -n capn-system

# Workload Cluster CR detail
kubectl describe cluster -n capi-clusters <cluster_name>
```

For workload-side inspection (CNI, MetalLB, application Pods), use the
materialised workload kubeconfig:

```bash
make workload-kubeconfig
export KUBECONFIG=$(pwd)/.artifacts/clusters/lab-default.kubeconfig
kubectl get nodes -o wide
kubectl get pods -A
```

---

## 2. Adding a workload cluster

In Stage 1 the same mgmt-1 can manage **multiple** workload clusters.
Each lives in its own per-cluster ClusterClass (plan `§16.1`) so that
two workload Cluster CRs do not share `*Template` references and
cannot couple through a chart bump on one of them.

### 2.1. Where the new TF root lives

Workload clusters are NOT added by editing the test fixture
`tests/fixtures/terraform/workload-clusters/lab-default/`. That is the
single fixture exercised by the local harness; it is not meant to be
forked in-tree.

Instead, in the **consumer repo**:

1. Copy `terraform/workload-clusters/<existing>/` to a new directory
   with a different `cluster_name` (e.g. `terraform/workload-clusters/data-pipeline/`).
2. Bump `var.k8s_lab_workload_cluster_name` and any per-cluster sizing.
3. Run:

   ```bash
   cd terraform/workload-clusters/data-pipeline
   terraform init
   terraform apply -var-file=<path-to>/.artifacts/mgmt.auto.tfvars.json
   ```

   The `*.auto.tfvars.json` file is the Phase-5 handoff bundle
   `export_artifacts` wrote on the runner — it carries every §8 global
   the module needs (kubernetes version, CAPN provider version, pod /
   service CIDRs, mgmt cluster name).

### 2.2. Why per-workload ClusterClass

Each workload's `capi-cluster-class` chart install creates a fresh
ClusterClass + `*Template` set named after that workload's chart
version (plan `§16.1` and `§2.9` chart-version-as-CR-name pattern). A
chart bump on workload A creates new Templates without affecting
workload B's existing references.

### 2.3. CIDR collision rules

Each workload cluster has its own `clusterNetwork` block and runs its
own kube-proxy + Calico domain — pod and service CIDRs do **not** have
to be globally unique, since each cluster's pod traffic stays inside
that cluster.

But routing on the host bridges (`capi-int`, `br-ext6`) is shared.
Concretely:

- two workloads can use the same `10.244.0.0/16` Pod CIDR — Calico's
  IPv4 SNAT hides each cluster's pod traffic behind the node IP, so
  the host never sees overlapping pod IPs;
- two workloads **cannot** use the same MetalLB IPv6 VIP range — they
  announce on the same `eth1` / `br-ext6` segment and the second
  speaker would race with the first;
- two workloads **cannot** use the same external IPv6 SLAAC pool on
  `eth1` — the LXD profile that allocates external IPs is shared.

Practical rule: keep `k8s_lab_metallb_vip_range_v6` and
`k8s_lab_external_node_ipv6_range` unique per workload; pod / service
CIDRs can stay at the defaults if you do not export them.

### 2.4. Identity-Secret namespace fanout

The new workload's Cluster CR will live in some namespace
(`capi-clusters` is the default; multi-tenant operators may use one
namespace per workload). CAPN looks up the identity Secret in the
**same namespace** as the LXCCluster CR (plan `§13.11` /
`§16.3`), so that namespace MUST appear in
`k8s_lab_capn_identity_namespaces` BEFORE you `terraform apply` the
new workload.

Update procedure:

```yaml
# host_vars or §8 globals
k8s_lab_capn_identity_namespaces:
  - capi-clusters       # default
  - tenant-data-pipeline
```

Re-run the playbook that includes `bootstrap_capn_secret`. The role
fans the identity Secret out to every namespace in the list (creating
the Namespace if missing). Existing namespaces' Secrets are server-side
applied — re-running is a no-op if nothing changed.

After that the new TF root can `terraform apply` without
`identityRef` lookups failing.

---

## 3. Destroying

The Makefile destroy graph follows two strict naming axes (plan
`§19.2`):

- `destroy-*` operates on running infra (TF state, helm releases, VM,
  libvirt domains). Each `destroy-*` auto-cascades the `clean-*`
  targets it has made stale, so the next forward target works
  zero-touch.
- `clean-*` is file-only and idempotent — safe to run on a repo with
  no infra at all.

```
destroy-workload  ─→  clean-tfstate
                  └→  clean-workload-kubeconfig

destroy-vm        ─→  clean-mgmt-bundle
                  └→  clean-workload-kubeconfig
                  └→  clean-tfstate

clean-local       ─→  destroy-vm  (cascades cleans above)
                  └→  clean-molecule

reset-all         ─→  destroy-workload  (cascades clean-tfstate + clean-workload-kubeconfig)
                  └→  destroy-vm        (cascades clean-mgmt-bundle + clean-workload-kubeconfig + clean-tfstate)
                  └→  clean-molecule
```

### 3.1. `make destroy-workload`

Tears down the workload cluster currently described by
`tests/fixtures/terraform/workload-clusters/lab-default/`. Three
branches, picked automatically by the recipe:

1. **TF state present** (workload was deployed via `make deploy-workload`):
   `terraform destroy -auto-approve -var-file=.artifacts/mgmt.auto.tfvars.json`.
   TF unrolls the `helm_release` chain in reverse: `metallb-config →
   metallb → cni-calico → workload Cluster CR → per-workload
   ClusterClass`. The Cluster CR delete triggers the CAPI cascade —
   CAPN destroys the LXC instances and the workload haproxy LB, which
   can take several minutes (LXC graceful stop + storage cleanup).

2. **No TF state but `.artifacts/mgmt.kubeconfig` and
   `mgmt.auto.tfvars.json` are present** (workload was deployed via
   the Molecule e2e-local converge path — `kubernetes.core.helm`
   direct, no TF state at all): helm uninstall fallback. The recipe
   reads `k8s_lab_workload_cluster_name` from the tfvars JSON and
   runs:

   ```
   helm uninstall <cluster_name>       -n capi-clusters --kubeconfig .artifacts/mgmt.kubeconfig --wait --timeout 15m
   helm uninstall <cluster_name>-class -n capi-clusters --kubeconfig .artifacts/mgmt.kubeconfig --wait --timeout 5m
   ```

   The first uninstall deletes the workload Cluster CR — CAPI cascades
   that into Machine / LXCMachine deletion → CAPN tears down LXC
   instances. `--wait` blocks until finalizers release. The second
   uninstall deletes the per-workload ClusterClass + `*Template`
   release. The CNI / MetalLB releases lived **inside** the workload
   cluster and disappear with the cluster itself — there is no
   separate uninstall for them.

3. **Neither tfstate nor `mgmt.kubeconfig`** — informative log, no-op
   on infra. The clean cascade still runs (idempotent against absent
   files).

In every branch the cascade `clean-tfstate` + `clean-workload-kubeconfig`
runs at the end:

- `clean-tfstate` wipes `.terraform/`, `.terraform.lock.hcl`,
  `terraform.tfstate*`, `.terraform.tfstate.lock.info` from the
  fixture directory.
- `clean-workload-kubeconfig` removes any
  `.artifacts/clusters/*.kubeconfig` debug copies.

After `make destroy-workload`, `make deploy-workload` brings the
cluster back zero-touch.

### 3.2. `make destroy-vm`

Destroys the local Vagrant VM and any libvirt orphans (delegates to
`make -C tests/vagrant/debian13 destroy`). Cascades:

- `clean-mgmt-bundle` — removes `.artifacts/mgmt.kubeconfig`,
  `.artifacts/mgmt.auto.tfvars.json`, `.artifacts/harness-vm-id`.
- `clean-workload-kubeconfig` — debug per-cluster copies.
- `clean-tfstate` — workload TF state is meaningless without the VM.

This is the right target when the VM itself is hosed (boot loop, disk
pressure, libvirt confused) and you want a clean substrate but don't
need to exercise `terraform destroy`.

### 3.3. `make clean-local`

Compound, ~30s. "I want to start over fast." Equivalent to:

```
destroy-vm  +  clean-molecule
```

VM destruction transitively subsumes bootstrap cleanup (the bootstrap
LXC dies with its host VM). Does **not** exercise `terraform destroy`
on the live workload — appropriate when you don't care about
exercising the TF reverse path.

`clean-molecule` removes `~/.ansible/tmp/molecule.*` scratch
directories.

### 3.4. `make reset-all`

Compound, ~3-5 min. Full PLAN `§19.2` reverse chain:

```
destroy-workload  →  destroy-vm  →  clean-molecule
```

Use this when you want to validate the destroy contract end-to-end
(typically before a release, or to reproduce a destroy bug). Order
matters: `destroy-workload` runs **first**, against the live mgmt
cluster, so it actually exercises the helm uninstall + CAPI cascade
delete + CAPN LXC teardown path. Only then does `destroy-vm` wipe the
VM.

### 3.5. Production destroy

For a real consumer repo, the destroy chain looks like:

1. **Workload TF roots** — `terraform destroy` on each
   `terraform/workload-clusters/<name>/` directory in the consumer
   repo. CAPI cascades into LXC teardown. Order between workloads is
   irrelevant; they are independent under the same mgmt-1.

2. **`cleanup_bootstrap` is irrelevant in production** — the bootstrap
   LXC was destroyed at the end of Phase 7 of the original deploy and
   has not existed since. The role still ships and is still tested
   (`tests/molecule/cleanup-bootstrap/`) for substrate correctness,
   but a production destroy never invokes it on a steady-state lab.

3. **mgmt-1 itself** — uninstall its Cluster CR + ClusterClass
   releases against `mgmt.kubeconfig`. Naming convention:

   ```bash
   helm uninstall <mgmt-1-cluster-release> \
     -n capi-clusters \
     --kubeconfig .artifacts/mgmt.kubeconfig --wait --timeout 15m
   helm uninstall <mgmt-1-clusterclass-release> \
     -n capi-clusters \
     --kubeconfig .artifacts/mgmt.kubeconfig --wait --timeout 5m
   ```

   At this point CAPI on mgmt-1 has already deleted itself — it is
   *self-hosting*, so removing its own Cluster CR cascades into its
   own LXC teardown. `kubectl` calls against the now-dead apiserver
   stop responding.

4. **LXD project** — once mgmt-1 instances are gone, the project is
   empty and can be removed:

   ```bash
   lxc project delete capi-lab
   ```

5. **Substrate / host** — bridge, snap, /opt/capi-lab, host
   sysctl tunings — these are owned by the consumer repo's own
   `destroy.yml` playbook (the shared k8s-lab repo only ships
   `cleanup_bootstrap`). Document them there, not here.

---

## 4. Upgrading

Three orthogonal version axes can be bumped independently: Kubernetes,
CAPN provider, individual chart versions. All bumps follow the project
"latest stable" rule: verify upstream BEFORE pinning, and update the
inline §8 comment plus the §8a aggregation row (plan `§2.11`).

### 4.1. Kubernetes version

```yaml
# inventory group_vars / §8 globals
k8s_lab_kubernetes_version: "v1.<NEW>.<NEW>"
```

The new value MUST exist in the CAPN simplestreams image set —
otherwise CAPN cannot find a matching `kubeadm/<ver>` image. Confirm
upstream:

```bash
curl -s https://images.linuxcontainers.org/capn/streams/v1/images.json \
  | jq '[.products | to_entries[] | .key] | map(select(test("kubeadm")))'
```

The chart-version-as-CR-name pattern (plan `§2.9` and `§12.10`) is the
mechanism that lets you actually roll forward without hitting CAPI CR
immutability. Bump the affected chart's `Chart.Version` so:

- a fresh `ClusterClass-<new-slug>` and `*Template-<new-slug>` set is
  rendered;
- the workload Cluster CR's `spec.topology.classRef.name` is rewritten
  to the new slug (the chart receives the slug from the Terraform
  module);
- CAPI rolls the topology forward via its standard rolling update
  algorithm (CP first, then workers).

`helm upgrade` against the affected releases on mgmt-1 (or
`terraform apply` against the workload TF root) drives this.
Old-version objects continue to live until you decide to clean them
up — `helm rollback` to the previous chart version restores the prior
state.

### 4.2. CAPN provider version

```yaml
k8s_lab_capn_provider_version: "v0.<NEW>.<NEW>"
```

Plus the matching pin in `clusterctl/clusterctl.yaml` (URL pin against
the GitHub release artefact).

For initial install on bootstrap, the `bootstrap_clusterctl` role's
idempotence guard skips re-init when controllers are already present.
For an in-place CAPN bump on a steady-state mgmt-1, this means
`bootstrap_clusterctl` will NOT do the upgrade for you — it is
not the role's job. The official path is:

```bash
clusterctl upgrade plan --kubeconfig .artifacts/mgmt.kubeconfig
clusterctl upgrade apply --contract v1beta1 --kubeconfig .artifacts/mgmt.kubeconfig
```

In Stage 1 this is a documented manual step. Wrapping `clusterctl
upgrade` in a role is on the Stage 2 backlog.

After the upgrade, re-verify with:

```bash
kubectl --kubeconfig .artifacts/mgmt.kubeconfig get pods -n capn-system
```

### 4.3. Chart version bumps (Calico, MetalLB, ClusterClass…)

Each wrapper chart in `charts/` carries an upstream pin in its
`Chart.yaml dependencies:` block AND a plan-level pin in §8. Bumping
the chart is a three-line change:

1. Update the dependency pin in `charts/<chart>/Chart.yaml` to the
   new upstream stable.
2. Bump the chart's own `Chart.Version` (keeps the chart-version-as-CR-name
   trail honest if the chart owns CAPI CRs).
3. Bump the matching §8 inline pin and §8a row.

Re-run `helm dep update charts/<chart>` to regenerate the chart lock,
then re-apply the affected TF root. The `hashicorp/helm` provider's
`helm_release.wait = true` (plan `§12.11`) blocks until every resource
in the new release is Ready before TF returns.

### 4.4. The "always re-verify upstream pins" rule

Per memory rule [`feedback_latest_stable`] / plan `§2.11`:

- model defaults / "what was stable last time" do NOT count as a
  valid pin source;
- before any bump, fetch the upstream `releases/latest` (GitHub /
  snapcraft / chart index) and record the verified version date in
  the §8a table;
- never commit lower-bound pins of the form `>=X,<X+1` that lock out
  future major releases.

---

## 5. Rotating the CAPN identity Secret / LXD trust

The CAPN identity Secret carries the LXD client certificate CAPN uses
to reach the host LXD daemon at `<capi-int-gateway-ipv4>:8443`. Plan
`§13.11`. Three artefacts:

- the host LXD trust-store entry (`lxc config trust list` shows it);
- the on-disk client cert + key under
  `/opt/capi-lab/etc/bootstrap_capn_secret/` on the host;
- the Kubernetes Secret `incus-identity` (default name) materialised
  in every namespace listed in `k8s_lab_capn_identity_namespaces`.

### 5.1. There is no automated `force_rotate` flag (today)

`bootstrap_capn_secret` does NOT expose a
`bootstrap_capn_secret_force_rotate` toggle in
`defaults/main.yml` — its `community.crypto` pipeline is
file-state-idempotent, and the LXD trust check is fingerprint-based.
Re-running the role with the existing cert in place is a no-op; the
role will not regenerate.

### 5.2. Manual rotation procedure

To rotate, you have to invalidate the existing artefacts so the role's
idempotence guards take a different branch. The clean sequence is:

```bash
# On the host, remove the on-disk staging that the openssl_*
# modules check for state idempotence.
sudo rm -f /opt/capi-lab/etc/bootstrap_capn_secret/client.{key,csr,crt}

# Drop the existing LXD trust entry so the new cert can be added.
# Identify the entry by name shown in `lxc config trust list`:
sudo lxc config trust list
sudo lxc config trust remove k8slab-capn   # cert CN; cosmetic name in trust store

# Re-run the role on the host. New key + cert are generated, new
# trust entry is added, and the Secret is server-side applied across
# every namespace in k8s_lab_capn_identity_namespaces.
ansible-playbook -i <inventory> -l <host> \
  --tags bootstrap_capn_secret <consumer-repo>/playbooks/site.yml
```

CAPN controllers re-read the Secret at every Cluster reconcile, so
there is no controller restart step. Verify by tailing
`capn-controller-manager` logs for a clean LXCCluster reconcile after
rotation.

### 5.3. LXD trust store as source of truth

`lxc config trust list` is the single source of truth for which client
certs the LXD daemon will accept. If the rotation procedure is
interrupted (new cert generated, but trust store not updated), CAPN
calls fail with TLS errors. Always inspect the trust store after
rotation:

```bash
sudo lxc config trust list
# expect exactly ONE entry whose CN matches
# bootstrap_capn_secret_client_cert_cn (default "k8slab-capn")
# and whose project restriction = "capi-lab"
```

---

## 6. Backups

The shared k8s-lab repo does **not** ship backup automation. Backups
are a consumer-repo concern and depend on what the operator considers
the canonical source of truth for the running lab.

### 6.1. What to back up

| Artefact | Source of truth status | Backup priority |
|----------|------------------------|-----------------|
| `.artifacts/mgmt.kubeconfig` | Reproducible from substrate; cheap to back up. | Medium — saves a re-bootstrap if lost. |
| `.artifacts/mgmt.auto.tfvars.json` | Reproducible from §8 + bootstrap state. | Medium. |
| Consumer-repo `vault.yml` | **Source of truth** (real cert / key material, registry creds, etc.). | Critical — back up off-host. |
| LXD project content | Substrate state. Opaque to k8s. | Low — cheaper to recreate from code. |
| Kubernetes etcd | **Source of truth** for k8s API state. | Critical for any production workload. |

### 6.2. LXD-side substrate snapshots

For substrate disaster recovery (host-level corruption, accidental
`lxc project delete`), LXD ships its own export:

```bash
sudo lxc export <instance> --project capi-lab /backup/<instance>.tar.gz
```

This produces an opaque rootfs+config tarball. It is **not** a
Kubernetes-aware backup — restoring a CP node from an `lxc export`
produces a node with stale etcd state that does not match the rest of
the cluster. Use `lxc export` for substrate disaster recovery only,
not for k8s state recovery.

### 6.3. Kubernetes state backups

For the workload cluster's actual Kubernetes state (Secrets,
PersistentVolumes, application CRs), use standard tooling — Velero,
periodic etcd snapshots via `etcdctl`, or whatever the consumer's
backup contract specifies. CAPI is a control-plane provisioner; it
does not back up workload state.

---

## 7. Common operational checks

### 7.1. mgmt-1 self-hosted health

```bash
export KUBECONFIG=$(pwd)/.artifacts/mgmt.kubeconfig

# Controllers Running across all CAPI namespaces
kubectl get pods \
  -n capi-system \
  -n capi-kubeadm-bootstrap-system \
  -n capi-kubeadm-control-plane-system \
  -n capn-system

# Cluster + topology overview
kubectl get clusters,kubeadmcontrolplanes,machinedeployments -A
```

Expected steady state: every controller Pod `Running 1/1`, every
Cluster CR `Phase: Provisioned`.

### 7.2. Workload cluster health

```bash
export KUBECONFIG=$(pwd)/.artifacts/clusters/lab-default.kubeconfig

# Nodes Ready (both CP and workers)
kubectl get nodes -o wide

# Calico DaemonSet rolled out on every node
kubectl -n tigera-operator get pods
kubectl -n calico-system get ds

# MetalLB speaker DaemonSet rolled out + controller Running
kubectl -n metallb-system get pods,ds
```

### 7.3. External VIP reachability (Gate A)

If MetalLB is configured with an IPv6 VIP pool, reachability from
outside the lab is the canonical proof that the L2 plane works end-to-end:

```bash
# from a host that can reach br-ext6 (or the Vagrant VM in local mode)
curl -6 -v "http://[<vip>]:80/"
```

The Gate A helm test (plan `§17.3`,
`charts/metallb-config/templates/tests/`) does the same probe
in-cluster and as part of the deploy pipeline; this is the
out-of-band verification.

### 7.4. LXD substrate inventory

```bash
sudo lxc list --project capi-lab \
  -f csv -c n,s,t,4,6
```

Output columns:

- `n` — instance name (`mgmt-1-CP-0`, `lab-default-CP-0`, …)
- `s` — running / stopped
- `t` — `container` (unprivileged LXC)
- `4` / `6` — IPv4 / IPv6 addresses

A healthy steady-state lab shows mgmt-1 instances + workload
instances + workload haproxy LB, all `RUNNING`, with both IPv4 and
IPv6 addresses on each node.

### 7.5. Helm release inventory

```bash
# Releases on mgmt-1 that own CAPI CRs for workloads
helm list --kubeconfig .artifacts/mgmt.kubeconfig -n capi-clusters

# Releases inside each workload (CNI, MetalLB, MetalLB config)
helm list --kubeconfig .artifacts/clusters/<name>.kubeconfig -A
```

Releases on mgmt-1 follow the chart-version-as-CR-name pattern —
expect `<cluster-name>-class` (ClusterClass + Templates) and
`<cluster-name>` (Cluster CR) per workload.

---

## 8. When `helm upgrade` fails on `admission webhook denied: field is immutable`

This is the canonical CAPI immutability symptom (plan `§12.10`).
Meaning: a chart change touched a CAPI CR field — typically a
ClusterClass `spec.controlPlane.machineInfrastructure.ref` or an
`*Template.spec` — that the admission webhook flags immutable once
referenced by a Cluster CR.

The fix is **never** to `--force` past the webhook, edit the CR, or
delete-and-recreate manually. The correct path:

1. **Bump `Chart.Version`** in the affected wrapper chart's
   `Chart.yaml`. The chart-version-as-CR-name pattern (plan `§2.9` /
   `§12.10`) renders fresh ClusterClass + `*Template` objects with
   names suffixed by the new version slug. The Cluster CR's
   `spec.topology.classRef.name` is rewritten to point at the new
   ClusterClass (the chart receives the slug from the Terraform
   module).
2. **Re-apply** the affected TF root — `terraform apply` updates the
   `helm_release` against the new chart version.
3. CAPI rolls the topology forward (rolling update of CP first, then
   workers).
4. Old ClusterClass + `*Template` objects from the previous chart
   version continue to exist — they have no Cluster CR referencing
   them. Clean them up at your leisure with `helm uninstall
   <prefix>-<old-slug>`, or leave them in place for `helm rollback`
   support.

The §8 inline pins + §8a aggregation row capture every chart version
this contract depends on; bumping a chart without updating those is a
plan deviation that re-review will catch (plan `§2.11`).

---

## 9. Operational links

| Topic | Where |
|-------|-------|
| Why pivot is mandatory | [`02-architecture.md`](02-architecture.md) §3.3, plan `§12.6`. |
| Acceptance gates A / B | [`02-architecture.md`](02-architecture.md) §8, plan `§17`. |
| Variable reference | [`08-configuration-reference.md`](08-configuration-reference.md). |
| Role-by-role behaviour | [`09-roles-reference.md`](09-roles-reference.md). |
| Module + chart reference | [`10-modules-and-charts.md`](10-modules-and-charts.md). |
| Troubleshooting catalogue | [`13-troubleshooting.md`](13-troubleshooting.md). |
| Phase 8 destroy plan | `plans/PLAN-stage1-6.md` §19. |
| Artefact contract | `plans/PLAN-stage1-common.md` §11. |
| Risk catalogue (helm storage / immutability / …) | `plans/PLAN-stage1-common.md` §12. |
