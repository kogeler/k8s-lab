This file owns §23: Stage 2 — Step 18 — hosted CI path. The §N
numbering is continuous across all plan files; cross-references of
the form `§<number>` are valid without naming the file — see the
`PLAN-stage1-common.md` header for the full file lineup.

Stage 2 file lineup:

```
PLAN-stage2-common.md ............ backlog (no §N — items get a §N on implementation)
PLAN-stage2-1.md ................. §23      (Step 18 — hosted CI path)  <-- this file
```

---

# 23. Step 18 — Hosted CI path on GitHub Actions

**Status:** **completed** (2026-05-13). Closes the *"Hosted CI path
without local runner"* item from `PLAN-stage2-common.md` (now removed
from the backlog).

The §N entry is written in past tense and describes what was actually
built, not what was originally proposed — the backlog text and the
implementation diverged on the substrate approach (see §23.2).

## 23.1. Goal

Run the full canonical bootstrap → pivot → workload flow (§3) on a
hosted CI runner so that every PR is validated end-to-end without
requiring an operator to have a physical Vagrant + libvirt host.

The pre-commit local-Vagrant gate (`make test-local-e2e`, per §2.11a
and user-memory `feedback_test_before_commit`) **remains in force**
— the hosted CI is an additive second line of defence, not a
replacement.

## 23.2. Substrate approach — bare LXD on the runner

`PLAN-stage2-common.md` listed two candidate approaches:

1. nested virtualization: `setup-kvm` on the runner → Vagrant
   libvirt provider → the same VM the local flow uses;
2. bare LXD on the runner, dismissed in the backlog text with
   *"requires privileged host access which GitHub Actions runners
   do not provide"*.

The actual implementation took approach **(2)**. The backlog's
dismissal turned out to be a misjudgment: GitHub Actions
`ubuntu-latest` runners DO grant the runner user passwordless `sudo`,
which is sufficient for `snap install lxd` and for `lxc` operations
against an unprivileged LXC tree. **No privileged-LXC host access is
required** — every container the canonical flow spawns is
unprivileged, identically to the local Vagrant flow (substrate
invariant §2.8 preserved). Approach (1) was therefore not implemented
— it would have added a 5–10 min nested-KVM warm-up per job and an
extra layer of debug surface (libvirt → KVM → guest, vs. just runner
→ snap LXD → LXC).

## 23.3. What was built

### 23.3.1. New Molecule scenario `tests/molecule/gha`

A composite scenario that shares the canonical flow with `e2e-local`
through `import_playbook`:

* `converge.yml` → `- import_playbook: ../e2e-local/converge.yml`
* `verify.yml`   → `- import_playbook: ../e2e-local/verify.yml`

Single source of truth: every future change to the bootstrap →
pivot → workload sequence is made once in `e2e-local`, both
scenarios pick it up.

The substrate divergence is contained in `gha/`-local files:

| File | Purpose |
|---|---|
| `molecule.yml` | `driver: default managed: false`, platform `k8slab-host`; `[diff] always=true` for the entire scenario so CI logs carry full per-task diff. |
| `host_vars/k8slab-host.yml` | `ansible_connection: local` (the target IS the runner); blanks out the SSH coordinates inherited from `shared/inventory/group_vars/k8slab_host.yml`; loopback btrfs device path override; mode relaxation for kubeconfigs read by `kubernetes.core` action plugins on the controller; cert-manager wait extension; tfvars-handoff disabled (the URL contains 127.0.0.1 which the `export_artifacts` healthcheck rejects on purpose); wider per-step timeouts. |
| `tasks/runner-cleanup.yml` | Stops Docker (`docker.service`/`docker.socket`/`containerd.service`); inserts a single explicit `iptables -I FORWARD -j ACCEPT` (Docker pins `FORWARD DROP` at daemon start and the graceful shutdown does NOT revert it — observed in CI runs 25787813025/25790660361); disables swap + comments swap entries in `/etc/fstab`; apt-purges ~5 GiB of preinstalled bloat (`google-cloud-cli`, `azure-cli`, `mysql-*`, `php*`, `ruby`, …); `rm -rf` ~10 GiB of unpacked toolchains under `/usr/share`, `/opt`, `/usr/local/lib/android`. The rm task carries `diff: false` as a per-task override because the Android SDK alone is ~30k files and the global diff would blow the CI log past 200k lines. |
| `tasks/loopback-pool.yml` | Allocates a 20 GiB sparse file at `/mnt/k8slab/lxd-pool.img` (the runner's `/mnt` carries ~70 GiB scratch space vs. ~14 GiB on `/`), attaches it via `losetup -f --show`, publishes a stable udev-style symlink at `/dev/disk/by-id/k8slab-lxdpool-loop`. `k8s_lab_lxd_pool_device` host_var is pinned to that symlink so every consumer (`lxd_storage_pools_pools[].config.source`, `shared/tasks/prepare-btrfs-pool.yml`) reads the same path irrespective of which `/dev/loopN` the kernel happens to pick. |
| `prepare.yml` | Top-level prepare playbook. First task asserts `$GITHUB_ACTIONS == "true"` (defence-in-depth guard against local invocation). Then runner-cleanup → loopback-pool → shared substrate prepare (apt deps + `ext6-ra-source.yml` veth + radvd) → shared clean-disk (wipefs of the loop device — no-op on a fresh sparse file but kept symmetric with `e2e-local`). |
| `ENABLE_CI` | Sentinel file matched verbatim by the workflow's matrix builder. Empty by design — the assertion is its existence, not its contents. |

### 23.3.2. Universal role-preflight extension to Ubuntu

Every Stage 1 role's `tasks/preflight.yml` previously gated on
`distribution == 'Debian' AND distribution_major_version >= 13`.
The CI runner is `ubuntu-latest` (currently 24.04). The OS check was
relaxed across all 14 roles to:

```yaml
- ansible_facts['os_family'] == 'Debian'
- >-
  (ansible_facts['distribution'] == 'Debian'
   and (ansible_facts['distribution_major_version'] | int) >= 13)
  or
  (ansible_facts['distribution'] == 'Ubuntu'
   and (ansible_facts['distribution_major_version'] | int) >= 22)
```

The change is purely additive — the Debian 13+ path is unchanged
and verified by re-running `base-system-delegated-test` and a full
clean-VM `make test-local-e2e` cycle (both green, see §23.6).
Production target stays Debian 13 (§2.1 unchanged); Ubuntu is the CI
substrate only. The `Debian-family Linux` wording in `doc/`,
`README.md`, `AGENTS.md`, `CITATION.cff`, `mkdocs.yml`, `llms.txt`,
`CITATION.cff`, and the README badge was updated to `Debian or
Ubuntu Linux` for accuracy.

### 23.3.3. New `bootstrap_clusterctl` role variable

Added `bootstrap_clusterctl_cert_manager_timeout` (default `""` =
inherit clusterctl's 10-min internal wait). When non-empty, the role
template `templates/clusterctl.yaml.j2` emits a `cert-manager:`
block with the override:

```yaml
cert-manager:
  timeout: "{{ bootstrap_clusterctl_cert_manager_timeout }}"
```

`gha/host_vars/k8slab-host.yml` sets it to `"25m"`. The 10-min
default trips with `context deadline exceeded` on Azure-hosted GHA
runners because cold-cache pulls of cert-manager cainjector + webhook
+ controller from `quay.io` routinely take 12–15 min. The role's
preflight validates the value (`""` or `<N>[smh]`).

### 23.3.4. Workflow `.github/workflows/molecule.yml`

* **Triggers**: `pull_request` + `push` against `main`, path-filtered
  to `ansible/**`, `charts/**`, `terraform/**`, `tests/molecule/**`,
  `scripts/**`, `.github/workflows/molecule.yml`. Doc-only PRs
  skip the workflow. `workflow_dispatch` is allowed for manual reruns.
* **Concurrency**: `cancel-in-progress: true` so a force-push during
  a 30–60 min e2e does not double-bill runner minutes.
* **Setup**: Python 3.13 + pinned tooling from `requirements-gha.txt`
  (see §23.3.5), Ansible collections from
  `ansible/requirements.yml`, `azure/setup-helm@v4` (v4.1.4),
  `azure/setup-kubectl@v4` (matching `k8s_lab_kubectl_version`).
* **Invocation**: `make -C tests/molecule gha-local-test` (routed
  through the project Makefile per user-memory
  `feedback_makefile_only`).
* **Failure diagnostics**: a single `Collect diagnostics on failure`
  step produces a five-section dump (host / LXD substrate /
  bootstrap k3s / self-hosted mgmt / artifacts dir) designed to make
  most failures diagnosable from the run log alone, without
  re-running the 30–60 min e2e. The `Upload .artifacts on failure`
  step uploads `.artifacts/` + `/tmp/molecule.*.log` as a
  `k8s-lab-artifacts` zip with 7-day retention. See
  `doc/12-testing.md` §11.5.

### 23.3.5. Pinned Python dependencies — `requirements-gha.txt`

A fully-pinned `pip` lockfile at repo root. The header lists the four
primary entries (`ansible-core`, `molecule`, `kubernetes`,
`jsonpatch`) plus the regeneration recipe (a throwaway
`.venv-gha-temp` venv on Python 3.13 — same interpreter the runner
uses — running `pip install ...` without bounds and then `pip
freeze`). All transitives below are derived; the regeneration recipe
re-resolves them against the latest stable primaries rather than
bumping anything by hand (per user-memory `feedback_latest_stable`).
`.gitignore` excludes `.venv-gha-temp/`. `actions/setup-python@v5` is
keyed on `cache-dependency-path: requirements-gha.txt` so the pip
cache invalidates automatically when the file changes.

### 23.3.6. `tests/molecule/Makefile` extension

Added a `GHA_SCENARIOS := gha` list (separate from the
Vagrant-driven `SCENARIOS`) and a `_molecule_local` recipe macro
that invokes `molecule` directly — bypasses
`scripts/molecule_run.py` entirely (no `vagrant up`, no SSH
coordinate discovery). The macro's first line is a hard guard:

```make
@if [ "$${GITHUB_ACTIONS:-}" != "true" ]; then \
    echo "ERROR: gha scenario is CI-only — refusing to run locally."; \
    ...; exit 1; \
fi
```

Eight `gha-local-<action>` targets are wired explicitly
(`create`/`prepare`/`converge`/`idempotence`/`verify`/`test`/`destroy`/`lint`).
The `help` target documents both families.

### 23.3.7. Three-layer guard against accidental local execution

The scenario mutates host networking (radvd + veth pair under
systemd-networkd), the snap-installed LXD daemon, iptables (one
explicit FORWARD ACCEPT rule), swap state, `/etc/fstab`, and 20 GiB
of `/mnt`. On an ephemeral runner this is fine — the VM is discarded
at job end. On a developer workstation it would persist and corrupt
the local Vagrant harness.

Three independent layers refuse a local invocation; none may be
weakened without an explicit Step that justifies it:

1. `tests/molecule/Makefile` — `_molecule_local` macro's
   `$GITHUB_ACTIONS != "true"` gate (§23.3.6).
2. `tests/molecule/gha/prepare.yml` — first task is an
   `ansible.builtin.assert` on the same env var.
3. `.github/workflows/molecule.yml` is the only legitimate caller.

User-memory `feedback_gha_scenario_ci_only` records the contract.

## 23.4. Stage 1 invariants explicitly preserved

This Step is **additive only** — none of the substrate invariants
fixed in `PLAN-stage1-common.md` was weakened. The verification list:

* **Unprivileged-LXC only (§2.8)** — `gha` uses the same
  `lxd_profiles` / `lxd_bootstrap_instance` paths; no
  `security.privileged` flip.
* **Helm-first delivery (§2.9)** — `gha/converge.yml` is a verbatim
  `import_playbook` of `e2e-local/converge.yml`, which is helm-only.
* **CAPI bootstrap-and-pivot flow (§3)** — same playbook, same Phase
  A → D sequence, `cleanup_bootstrap` retires the bootstrap LXC
  post-pivot.
* **Dual-stack networking (§5)** — `shared/tasks/ext6-ra-source.yml`
  runs identically on the runner (radvd + veth pair, the same
  `2001:db8:42:100::/64` documentation prefix), Calico ships with
  the same dual-stack Pod CIDR pair.
* **Mandatory pivot** — the gha CI run is **failed** if pivot is
  skipped or aborts; no escape hatch.
* **CAPI/CAPN version pins (§8)** — inherited from `shared/inventory/
  group_vars/k8slab_host.yml`; no override in `gha/host_vars`.

The substrate divergences in `gha/host_vars` (mode relaxation,
cert-manager timeout, tfvars-handoff disable, wider timeouts) are
*operational accommodations for the runner environment*, not
invariant changes. They are documented in `doc/12-testing.md` §11.3
with explicit *why*-rationale.

## 23.5. Documentation updates done in this Step

* `doc/12-testing.md` — §1 intro extended (two e2e drivers: Vagrant +
  GHA), §2 scenario table grew a 15th row for `gha` (marked
  CI-only), §5.3 new sub-section on the `gha-local-*` Makefile
  family + three-layer guard, §11 fully rewritten from "There is no
  CI" to a six-subsection description of the GHA workflow (trigger
  policy, runner-specific substrate, scenario-local overrides,
  Python deps, failure diagnostics, local equivalence).
* `doc/03-stack.md` — *OS target* updated to mention Ubuntu CI
  substrate alongside the production Debian 13 reference.
* `doc/05-prerequisites.md` — *Operating system* and *Kernel and
  namespaces* sections re-worded to acknowledge Ubuntu defaults.
* `doc/08-configuration-reference.md` — `k8s_lab_host_distro`
  description widened to Debian 13+ / Ubuntu 22.04+.
* `doc/09-roles-reference.md`, `doc/01-overview.md`,
  `doc/02-architecture.md`, `doc/07-deployment-guide.md`,
  `doc/14-glossary.md`, `doc/README.md`, `README.md`, `AGENTS.md`,
  `CITATION.cff`, `mkdocs.yml`, `llms.txt`, `tests/molecule/shared/
  verify.yml` — *Debian-family Linux* → *Debian or Ubuntu Linux*
  prose update.
* `CONTRIBUTING.md` — added a bullet pointing at the GHA Molecule
  workflow as the post-push second-line check, plus the explicit
  *do not run gha locally* warning.
* `AGENTS.md` — Repository Map + Tests And Harness sections updated
  to mention `gha` and the workflow file.
* `llms-full.txt` — regenerated via `make docs-llm` after every
  `doc/` change.
* User-memory `feedback_gha_scenario_ci_only` added to `MEMORY.md`.

## 23.6. Acceptance evidence

1. **GHA workflow run [25793173461](https://github.com/kogeler/k8s-lab/actions/runs/25793173461)** —
   green on `tests/molecule/gha (e2e on runner)`: full bootstrap →
   mgmt-1 + Gate A/B helm tests on mgmt-1 → `clusterctl init` +
   `clusterctl move` → cleanup_bootstrap → workload + Gate A/B helm
   tests on workload + external Gate A curl via `ext6-ra-peer`. The
   workflow ran on a fresh `ubuntu-latest` image from a clean
   checkout.
2. **Local Vagrant `make test-local-e2e` on a freshly destroyed VM**
   (2026-05-13) — three PLAY RECAPs, all `failed=0 unreachable=0`:
   Prepare `ok=19 changed=10`, Converge `ok=407 changed=72`, Verify
   `ok=12 changed=3`. Confirms the universal-preflight relaxation
   (§23.3.2) and the new `bootstrap_clusterctl_cert_manager_timeout`
   variable (§23.3.3) do not regress the Debian 13 + Vagrant flow.

## 23.7. Out of scope (left for further Steps if desired)

* **Caching the LXD image cache between runs** — currently every CI
  run re-pulls the LXD image template. `actions/cache@v4` keyed on
  `${{ runner.os }}-lxd-images-${{ hashFiles('ansible/roles/lxd_*/**')
  }}` would shave ~3–5 min off the cold runtime.
* **Caching the bootstrap k3s image bundle** — `binary_fetch`
  downloads the airgap-images tarball every run.
* **A matrix run on `ubuntu-22.04`** alongside the default
  `ubuntu-latest` — currently we only test the major-version that
  GitHub aliases as `latest`. The role preflight allows `>= 22.04`
  so this would be a one-line workflow change.
* **A consumer-repo CI template** — the path through `make
  deploy-workload` (Terraform + workload kubeconfig handoff) is not
  exercised on GHA. The `gha` scenario stops at the Ansible/Helm
  layer; a downstream consumer wanting hosted CI for *their*
  Terraform invocation needs a separate workflow that consumes the
  artefacts this one would produce (and relaxes the
  `export_artifacts` 127.0.0.1 healthcheck guard for the loopback
  topology).
