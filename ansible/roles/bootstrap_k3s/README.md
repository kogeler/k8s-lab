# bootstrap_k3s

Install k3s inside the already-running LXC bootstrap container and
bring the single-node management cluster up.

## Purpose

Plan §15.2. The role owns "k3s on the bootstrap node" and nothing else:

* pushes the `k3s` binary from `/opt/capi-lab/bin` (delivered by
  [`binary_fetch`](../binary_fetch/README.md)) into the container at
  `/usr/local/bin/k3s`;
* renders a minimal systemd unit and env file inside the container;
* enables + starts the `k3s` service with Stage 1 server flags
  (substrate-required `--disable=traefik` + `--disable=servicelb`,
  configurable TLS SANs);
* polls `k3s kubectl get nodes` until the bootstrap node reports Ready.

It does **not**:

* install `kubectl` / `clusterctl` inside the container — those are
  the lane of [`bootstrap_clusterctl`](../bootstrap_clusterctl/README.md)
  in Phase 4 (plan §15.3);
* publish the kube-apiserver outside the host — passes through an
  opt-in LXD proxy device configured via
  `lxd_bootstrap_instance_devices` (plan §15.5); host firewall stays
  out-of-project-scope (plan §11.4);
* write CAPN identity / CAPI provider resources — `bootstrap_capn_secret`
  (plan §15.4).

## Execution model

* Every write path into the container uses the LXD CLI
  (`lxc file push`, `lxc exec`) as a documented shell fallback
  (plan §2.6.1 allows shell where no native module covers the
  operation — and the `community.general.lxd` connection plugin is
  unusable here: it shells out to `lxc` on the Ansible *controller*,
  whereas in this repo's Molecule harness the controller is not the
  LXD host — the Vagrant VM is).
* Idempotence is earned explicitly:
  * **Binary push**: compare sha256 on the host against the sha256
    computed inside the container before calling `lxc file push`.
  * **systemd unit + env**: render locally into a tmp file on the
    host, read the live in-container content via `lxc exec cat`,
    push only when the two differ.
* The absolute `lxc` path is consumed through the
  `bootstrap_k3s_lxc_cli` variable because snap ships `lxc` in
  `/snap/bin` — not on the default non-interactive SSH `PATH`.

## Requirements

* The host ran `base_system` → `lxd_host` → the LXD substrate chain
  and `lxd_bootstrap_instance` (which is a transitive meta-dep).
* `binary_fetch` laid `k3s` on the host at
  `/opt/capi-lab/bin/k3s` with mode `0755`.
* `community.general` collection is installed on the control node
  (already pinned in `ansible/requirements.yml`) — used indirectly by
  the transitive `lxd_bootstrap_instance` meta-dep.
* `lxc` CLI is available at the path given by `bootstrap_k3s_lxc_cli`
  (default `/snap/bin/lxc` matches the snap install used by
  [`lxd_host`](../lxd_host/README.md)).

## Role variables

Every public variable uses the `bootstrap_k3s_*` prefix. Internal
values use `_bootstrap_k3s_*` and must not be consumed outside the
role.

### General

| Variable | Default | Description |
| --- | --- | --- |
| `bootstrap_k3s_enabled` | `true` | Whole-role toggle. |
| `bootstrap_k3s_project` | `capi-lab` | LXD project the container lives in. |
| `bootstrap_k3s_instance_name` | `capi-bootstrap-0` | LXD instance name. |
| `bootstrap_k3s_lxd_remote` | `local` | LXD remote name used in `lxc` invocations. |
| `bootstrap_k3s_lxc_cli` | `/snap/bin/lxc` | Absolute path to the `lxc` CLI. |

### Binary delivery

| Variable | Default | Description |
| --- | --- | --- |
| `bootstrap_k3s_host_bin_dir` | `/opt/capi-lab/bin` | Host-side source directory (matches `binary_fetch_bin_dir`). |
| `bootstrap_k3s_host_k3s_filename` | `k3s` | Source filename on host. |
| `bootstrap_k3s_container_bin_path` | `/usr/local/bin/k3s` | Destination path inside container. |
| `bootstrap_k3s_bin_mode` | `0755` | Mode applied to the in-container binary. |

### systemd unit

| Variable | Default | Description |
| --- | --- | --- |
| `bootstrap_k3s_service_name` | `k3s` | systemd unit name (no `.service` suffix). |
| `bootstrap_k3s_unit_path` | `/etc/systemd/system/k3s.service` | Path to the rendered unit inside the container. |
| `bootstrap_k3s_env_path` | `/etc/default/k3s` | Environment file referenced by the unit (leading `-` so missing is tolerated). |
| `bootstrap_k3s_unit_mode` | `0644` | Mode for the unit file. |

### k3s server flags

The substrate-required disable list — `traefik` and `servicelb` — is
baked into `vars/main.yml` as `_bootstrap_k3s_required_disable_components`
and cannot be overridden. Plan §2.9 / §5.5 delivers ingress +
LoadBalancer through Terraform Helm releases (MetalLB + an ingress
controller); leaving k3s' bundled versions on would race the add-ons
pass. `bootstrap_k3s_extra_disable_components` appends on top for
non-required extras.

| Variable | Default | Description |
| --- | --- | --- |
| `bootstrap_k3s_extra_disable_components` | `[]` | *Additional* components disabled on top of the required baseline. Each entry renders as `--disable=<x>`. Typical extras: `metrics-server`. |
| `bootstrap_k3s_tls_san` | `[]` | Each entry becomes `--tls-san=<x>`. |
| `bootstrap_k3s_write_kubeconfig_mode` | `0644` | `--write-kubeconfig-mode=<mode>`. |
| `bootstrap_k3s_token` | `""` | `--token=<x>` when non-empty; also set as `K3S_TOKEN` in the env file. |
| `bootstrap_k3s_cluster_cidr` | `""` | Overrides the k3s default pod CIDR when non-empty. |
| `bootstrap_k3s_service_cidr` | `""` | Overrides the k3s default service CIDR when non-empty. |
| `bootstrap_k3s_extra_kubelet_feature_gates` | `[]` | *Additional* kubelet feature gates merged into the same `--kubelet-arg=feature-gates=<csv>` as the required ones. The role always emits `KubeletInUserNamespace=true` — it is hardcoded in the systemd template because plan §2.8 hard-locks unprivileged LXC and kubelet would otherwise crash on `/dev/kmsg`. This variable layers on top of that baseline; it cannot remove it. |
| `bootstrap_k3s_extra_args` | `[]` | Raw arguments appended to `ExecStart`. |

### Readiness

| Variable | Default | Description |
| --- | --- | --- |
| `bootstrap_k3s_wait_retries` | `60` | `kubectl get nodes` retry count. |
| `bootstrap_k3s_wait_delay` | `4` | Seconds between retries. |

### Flow control

| Variable | Default | Description |
| --- | --- | --- |
| `bootstrap_k3s_flow_control_install` | `true` | Skip install (binary push + unit render) when `false`. |
| `bootstrap_k3s_flow_control_service` | `true` | Skip the service enable/start when `false`. |

## Tags

Per-section tags follow the repo convention (plan §2.6.3); both the
underscore and hyphen spellings work:

* `bootstrap_k3s` / `bootstrap-k3s` — everything.
* `bootstrap_k3s_preflight` — input validation only.
* `bootstrap_k3s_install` — binary push + unit render.
* `bootstrap_k3s_service` — enable + start.
* `bootstrap_k3s_healthchecks` — node readiness probe + kubeconfig stat.

## Example

```yaml
- hosts: k8slab_host
  become: true
  roles:
    - role: bootstrap_k3s
      vars:
        bootstrap_k3s_tls_san:
          - "bootstrap.example.test"
        bootstrap_k3s_extra_args:
          - "--kube-apiserver-arg=anonymous-auth=false"
```

## Testing

Molecule scenario at `tests/molecule/bootstrap-k3s/`:

* `converge` drives the role end-to-end against the shared Vagrant VM.
* `idempotence` asserts no-ops on a second run.
* `verify` asserts: k3s unit active inside container, node Ready,
  kubeconfig present, on-disk k3s binary sha256 matches the host copy.

Run locally:

```bash
make -C tests/molecule bootstrap-k3s-delegated-test
```

## Caveats

* The single shell fallback (`lxc file push`) skips when the sha256
  matches, so re-runs are free. If someone rewrites the in-container
  binary out-of-band (e.g. by running upstream `install.sh`), the
  next converge will overwrite it.
* This role does not persist the k3s token. If you re-create the
  bootstrap container between converges, the token changes — set
  `bootstrap_k3s_token` to a stable value when that matters.
* The systemd unit + env are rendered locally into `/tmp` on the
  host, compared against in-container content, and cleaned up at the
  end of `install.yml`. Nothing persistent lives under `/tmp`; a
  failed converge may leave those tmp files behind and is safe to
  re-run.

[plan]: ../../../PLAN-stage1-common.md
