This file owns §19: Phase 8 — destroy contract. The §N numbering is continuous
across all plan files; cross-references in the form `§<number>` are valid without
naming the file — see the `PLAN-stage1-common.md` header for the full
file lineup. The atomic scope of this shard is the reverse of all create-paths
into a clean state, so that a coding agent can work on the cleanup role
and the destroy contract independently of forward-paths.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (workload_cluster TF module)
PLAN-stage1-4.md ................. §17      (Helm test contracts — Gate A + Gate B chart-side specs)
PLAN-stage1-5.md ................. §18      (pivot mgmt-1 → self-hosted)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)                             <-- this file
PLAN-stage1-7.md ................. §20..§22 (Stage 1 closure + self-review + recommendation)
```

---

# 19. Phase 8 — Destroy contract

This section describes the destroy role (§19.1) and phase (§19.2), which
must be able to roll back the Stage-1 create-paths to a clean local
state.

## 19.1. Role: `cleanup_bootstrap`

**Status: done in Step 9 (2026-04-24).**

Removes:

* the bootstrap LXC — `capi-bootstrap-0` in the `capi-lab` project via
  `community.general.lxd_container state=absent` with
  `force_stop: true`. The instance-level proxy device `k3s-api`,
  through which `lxd_bootstrap_instance_devices` publishes the bootstrap API on
  `<vagrant>:16443`, goes away together with the instance — there is no
  separate step for publication.
* the runner-side artifacts root — optional, the path is taken from
  `cleanup_bootstrap_artifacts_root` (default empty = skip). Deletion
  goes through `ansible.builtin.file state=absent` with `delegate_to: localhost`
  and `become: false`, because `export_artifacts` wrote to the same
  path on the runner, not in the VM. Preflight blocks `/` and `//` so that
  a config error does not tear down the runner FS.

### Implementation notes (Step 9)

* **No meta-deps by design** (`meta/main.yml dependencies: []`).
  Cleanup is reverse-motion: if the substrate is already partially torn down, the role
  must remain a no-op, and not re-install LXD/project/pool
  just to remove a single instance. The Phase 8 orchestrator (§19.2)
  itself sequences the cleanup roles in the right order.
* **Probe-then-delete for full idempotence.**
  The first step is `ansible.builtin.uri GET /1.0/instances/<name>?project=<project>`
  with `status_code: [200, 404]` + `failed_when: false` + `changed_when: false`.
  The guard covers all three substrate states (daemon absent /
  project absent / instance absent) with a single check; a second consecutive
  run yields `changed=0` (plan §2.6.1 requirement).
* **Healthcheck guard `when: status in [200, 404]`** — if the substrate
  is completely torn down, even the healthcheck assert is skipped (nothing
  to validate). If the substrate is reachable, the assertion is 404 after delete.
* **Scenario-local artifacts path** in Molecule
  (`tests/molecule/cleanup-bootstrap/host_vars/k8slab-host.yml`):
  `{{ repo }}/.artifacts-cleanup-bootstrap-test` — so that the
  cleanup test does not clobber the real `.artifacts/` from the
  `export_artifacts` scenario / full e2e path.
* **Prepare strategy.** Since there are no meta-deps, the pre-converge
  instance is created in `prepare.yml` via
  `ansible.builtin.include_role name: lxd_bootstrap_instance` — it
  pulls the whole substrate chain transitively. In prepare, the runner-side
  section `delegate_to: localhost` creates a sentinel file in the
  scenario-local artifacts root, so that verify can prove
  real deletion (exists=false after cleanup), rather than the situation
  "the path never existed".

### Verify

The Molecule scenario `tests/molecule/cleanup-bootstrap/` end-to-end
run (`make -C tests/molecule cleanup-bootstrap-delegated-test`,
2026-04-24):

* converge: `ok=17 changed=2 failed=0` (instance delete + artifacts
  delete);
* **idempotence: `ok=16 changed=0 failed=0`** — probe returns
  404 → delete skipped, artifacts already absent, healthcheck 404 →
  assert pass;
* verify (6 asserts): `ok=6 changed=0 failed=0` — instance 404,
  instance is absent in the project-level `/1.0/instances?project=...`
  list (belt-and-braces protection against a false 404 when the
  project is absent), scenario-local artifacts root `exists=false` on the runner.

## 19.2. Phase 8 — Destroy

**Status: done in Step 18 (2026-04-28) — the Makefile destroy/clean
graph was groomed into two explicit axes (`destroy-*` for running infra,
`clean-*` for file-only deletes), each destroy auto-cascades the
`clean-*` targets it invalidates, two compound supertargets cover
typical operator workflows. The operator does not track manual cleanup
after any of the destroy steps — the next forward target works
without intervention.**

Reverse-ordered chain (canonical flow §3 in the reverse direction):

1. **`make destroy-workload`** — three branches in a single target:
   * **(a) TF state present** (workload was deployed through the TF
     route — `make deploy-workload`): `terraform destroy` on the §16.5
     fixture (`tests/fixtures/terraform/workload-clusters/lab-default/`).
     TF unrolls the helm_release chain of the §16.4 module in
     reverse order: metallb-config → metallb → cni-calico →
     workload Cluster CR (CAPI/CAPN delete LXC instances +
     workload kubeconfig Secret) → per-workload ClusterClass.
   * **(b) no TF state but `.artifacts/mgmt.kubeconfig` +
     `mgmt.auto.tfvars.json` exist** (workload was deployed through
     Molecule e2e-local converge — `kubernetes.core.helm` direct,
     no TF state at all): helm-uninstall fallback. `helm uninstall
     <cluster-name> -n capi-clusters --wait` (workload Cluster CR
     → CAPI cascade-deletes Machines → CAPN destroys LXC instances
     + LB; `--wait` waits until finalizers release the CR) + `helm
     uninstall <cluster-name>-class` (per-cluster ClusterClass +
     Templates). cni-calico / metallb / metallb-config lived
     **inside** the workload cluster — they go away together with
     the destroyed LXC instances, a separate uninstall is not needed.
   * **(c) neither tfstate nor mgmt.kubeconfig** — skip with informative
     log; the clean cascade still runs (no infra → no
     stale files).
   **Cascade on all branches: `clean-tfstate` +
   `clean-workload-kubeconfig`** — TF state in the fixture + any
   materialized workload kubeconfig copy in
   `.artifacts/clusters/` make no sense after destroy.
2. **Vagrant/libvirt cleanup** — `make destroy-vm` returns the
   harness to a clean state. **Cascade: `clean-mgmt-bundle`
   + `clean-workload-kubeconfig` + `clean-tfstate`** — after the
   VM wipe, ALL runner-side artifacts (handoff bundle + per-cluster
   debug kubeconfigs + workload TF state) point to ghosts.
   `cleanup_bootstrap` is not separately invoked in this branch — the VM
   teardown subsumes bootstrap cleanup transitively (the role remains
   testable via the Molecule scenario `tests/molecule/cleanup-bootstrap/`
   for production paths where the substrate is persistent).

### Naming convention (Step 18)

* **`destroy-*`** — operate on running infra (TF state, helm
  releases, VM, libvirt domains). Each cascades the `clean-*`
  targets it has made stale. After any `destroy-*`, the next forward
  target (`deploy-workload`, `vagrant up`, …) works without manual
  intermediate cleanup.
* **`clean-*`** — file/directory deletes only. Idempotent against
  missing state (safe to run on a repo without infra).
* **compound** — operator-facing supertargets:
  * **`make clean-local`** (≈30s) — "start over" fast reset:
    `destroy-vm + clean-molecule`. VM destruction subsumes
    bootstrap cleanup transitively; does not exercise
    `terraform destroy` on a live workload.
  * **`make reset-all`** (≈3-5min) — the full PLAN §19.2
    reverse chain: `destroy-workload → destroy-vm + clean-molecule`.
    Exercises every destroy-step on live infra (helm uninstall
    + Cluster CR cascade delete + LXC teardown via CAPN, then
    VM wipe). Used when the operator wants to validate the
    destroy contract end-to-end before the next test cycle.

### Cascade graph

```
destroy-workload  ─→  clean-tfstate
                  └→  clean-workload-kubeconfig

destroy-vm        ─→  clean-mgmt-bundle
                  └→  clean-workload-kubeconfig
                  └→  clean-tfstate

clean-local       ─→  destroy-vm  (← which cascades the cleans above)
                  └→  clean-molecule

reset-all         ─→  destroy-workload  (← cascades clean-tfstate + clean-workload-kubeconfig)
                  └→  destroy-vm        (← cascades clean-mgmt-bundle + clean-workload-kubeconfig + clean-tfstate)
                  └→  clean-molecule
```

### Contract

* we do not touch the shared external bridge if it was not created by the harness
  (production-mirror — the bridge usually lives outside the repo);
* the operator invokes steps ONLY through root-level Makefile targets
  (memory `feedback_makefile_only`); direct `terraform destroy`
  or `vagrant destroy` are not invoked;
* `tests/vagrant/debian13/Makefile destroy` after Step 18 operates
  ONLY on the VM + libvirt orphans — `.artifacts/*` cleanup is owned
  by the root Makefile through the cascade. A stand-alone
  `make -C tests/vagrant/debian13 destroy` leaves `.artifacts/`
  untouched (it is the operator's call to use `destroy-vm` if
  the cascade is needed).

### Acceptance

All three criteria are green (Step 18 verification, 2026-04-28):

* `make destroy-workload` on a Ready cluster → TF destroy tears down
  all resources from the §16.4 chain (5 helm releases + 2 helm test
  null_resources), the cascade cleans up `.terraform/`, `terraform.tfstate*`,
  `.artifacts/clusters/<cluster>.kubeconfig`. Immediately afterwards
  `make deploy-workload` brings up a fresh cluster zero-touch
  (without manual cleanup between destroy and deploy);
* `terraform destroy` is idempotent — a repeated destroy on
  an empty state (after the first destroy + before the cascade wipe) is a no-op
  with `Resources: 0 destroyed`;
* the `cleanup_bootstrap` Molecule scenario is green (§19.1 shipped in
  Step 9; confirmation that the role-level reverse path works on an
  isolated test substrate).

[1]: https://capn.linuxcontainers.org/?utm_source=chatgpt.com "Introduction - The cluster-api-provider-incus book"
[2]: https://documentation.ubuntu.com/lxd/latest/reference/network_bridge/?utm_source=chatgpt.com "Bridge network - LXD documentation"
[3]: https://documentation.ubuntu.com/lxd/latest/installing/?utm_source=chatgpt.com "How to install LXD - LXD documentation"
[4]: https://documentation.ubuntu.com/lxd/latest/reference/projects/?utm_source=chatgpt.com "Project configuration - LXD documentation"
[5]: https://documentation.ubuntu.com/microcloud/latest/lxd/howto/projects_confine/?utm_source=chatgpt.com "How to confine users to specific projects - LXD documentation"
[6]: https://docs.k3s.io/?utm_source=chatgpt.com "K3s - Lightweight Kubernetes | K3s"
[7]: https://main.cluster-api.sigs.k8s.io/clusterctl/commands/init.html?utm_source=chatgpt.com "init - The Cluster API Book"
[8]: https://cluster-api.sigs.k8s.io/clusterctl/commands/move?utm_source=chatgpt.com "move - The Cluster API Book"
[9]: https://documentation.ubuntu.com/lxd/latest/reference/devices_nic/?utm_source=chatgpt.com "Type: nic - LXD documentation"
[10]: https://kubernetes.io/docs/concepts/services-networking/dual-stack/?utm_source=chatgpt.com "IPv4/IPv6 dual-stack | Kubernetes"
[11]: https://metallb.io/configuration/_advanced_l2_configuration?utm_source=chatgpt.com "Advanced L2 configuration :: MetalLB, bare metal load-balancer for Kubernetes"
[12]: https://documentation.ubuntu.com/lxd/stable-5.0/reference/network_bridge/?utm_source=chatgpt.com "Bridge network - LXD documentation"
[13]: https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/?utm_source=chatgpt.com "kube-proxy | Kubernetes"
[14]: https://ansible.readthedocs.io/projects/molecule/configuration/?utm_source=chatgpt.com "Configuration - Ansible Molecule"
[15]: https://snapcraft.io/docs/how-to-guides/manage-snaps/manage-updates/?utm_source=chatgpt.com "Manage updates - Snap documentation"
[16]: https://capn.linuxcontainers.org/reference/default-simplestreams-server.html?utm_source=chatgpt.com "Default simplestreams server - The cluster-api-provider-incus book"
[17]: https://capn.linuxcontainers.org/reference/profile/kubeadm.html?utm_source=chatgpt.com "Kubeadm profile - The cluster-api-provider-incus book"
[18]: https://docs.k3s.io/cli/server?utm_source=chatgpt.com "server | K3s"
[19]: https://capn.linuxcontainers.org/reference/identity-secret.html?utm_source=chatgpt.com "Identity secret - The cluster-api-provider-incus book"
[20]: https://capn.linuxcontainers.org/reference/templates/default.html?utm_source=chatgpt.com "Default - The cluster-api-provider-incus book"
[21]: https://capn.linuxcontainers.org/reference/api/v1alpha2/api.html?utm_source=chatgpt.com "v1alpha2 API - The cluster-api-provider-incus book"
[22]: https://vagrant-libvirt.github.io/vagrant-libvirt/about/?utm_source=chatgpt.com "About - Vagrant Libvirt Documentation"
[23]: https://libvirt.org/formatnetwork.html?utm_source=chatgpt.com "libvirt: Network XML format"
[24]: https://capn.linuxcontainers.org/explanation/unprivileged-containers.html?utm_source=chatgpt.com "Unprivileged Containers - The cluster-api-provider-incus book"
[25]: https://registry.terraform.io/providers/hashicorp/helm/latest?utm_source=chatgpt.com "hashicorp/helm | Terraform Registry"
[26]: https://docs.tigera.io/calico/latest/getting-started/kubernetes/helm?utm_source=chatgpt.com "Installing with Helm | Calico Documentation"
[27]: https://metallb.io/installation/index.html?utm_source=chatgpt.com "Installation :: MetalLB, bare metal load-balancer for Kubernetes"
[28]: https://main.cluster-api.sigs.k8s.io/tasks/bootstrap/kubeadm-bootstrap/kubelet-config.html?utm_source=chatgpt.com "Kubelet configuration - The Cluster API Book"
[29]: https://main.cluster-api.sigs.k8s.io/tasks/bootstrap/kubeadm-bootstrap/index.html?utm_source=chatgpt.com "Kubeadm based bootstrap - The Cluster API Book"
[30]: https://github.com/kogeler/mini-pig-ansible-collection/tree/main/roles/init "mini-pig-ansible-collection init role"
[31]: https://github.com/kogeler/mini-pig-ansible-collection/tree/main/roles/naive_proxy "mini-pig-ansible-collection naive_proxy role"
[32]: https://github.com/kogeler/mini-pig-ansible-collection/tree/main/roles/naive_proxy/molecule "mini-pig-ansible-collection naive_proxy molecule harness"
[33]: https://github.com/kogeler/mini-pig-ansible-collection/blob/main/roles/naive_proxy/README.md "mini-pig-ansible-collection naive_proxy README"
[34]: https://documentation.ubuntu.com/lxd/default/howto/security_harden/ "How to harden security for LXD"
[35]: https://kubernetes.io/docs/concepts/workloads/pods/user-namespaces/ "User Namespaces | Kubernetes"
[36]: https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/ "Feature Gates | Kubernetes"
[37]: https://kubernetes.io/docs/tasks/administer-cluster/kubelet-in-userns/ "Running Kubernetes Node Components as a Non-root User | Kubernetes"
[38]: https://github.com/flannel-io/flannel "flannel GitHub repository"
[39]: https://flannel-io.github.io/flannel/index.yaml "flannel Helm repository index"
