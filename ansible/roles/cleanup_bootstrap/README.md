# cleanup_bootstrap

Delete the k8s-lab bootstrap LXC container inside the `capi-lab` LXD
project (plan §19.1).

## Purpose

Reverses the create-path owned by `lxd_bootstrap_instance`: ensures the
bootstrap container (`capi-bootstrap-0` by default) is absent. The
instance-level proxy device that publishes the bootstrap k3s API
(`k3s-api`, defined in shared host_vars) is an instance property — LXD
removes it with the container, so "bootstrap API publication" in plan
§19.1 is covered by the same step.

When a runner-side artifacts root is provided the role also deletes
`.artifacts/` (kubeconfig, CAPN secret, trust material) — those files
point at the now-dead endpoint and would leak into the next redeploy.

## Out of scope

* workload / management cluster teardown (Phase 8 orchestrator, §19.2);
* Helm add-on removal;
* LXD project / storage pool / managed network / profile destruction;
* host-side `br-ext6` bridge removal.

## Requirements

None at role level. The role probes LXD availability first and
gracefully skips when the daemon / project / instance is already
absent — it is safe to run on a partially-torn-down host.

## Role variables

All public variables use the `cleanup_bootstrap_*` prefix
(plan §2.6.2).

| Variable | Default | Description |
| --- | --- | --- |
| `cleanup_bootstrap_enabled` | `true` | Whole-role toggle. |
| `cleanup_bootstrap_lxd_socket_uri` | `unix:/var/snap/lxd/common/lxd/unix.socket` | LXD daemon URI for `community.general.lxd_container`. |
| `cleanup_bootstrap_lxd_socket_path` | `/var/snap/lxd/common/lxd/unix.socket` | Bare socket path for `ansible.builtin.uri` probe. |
| `cleanup_bootstrap_project` | `capi-lab` | LXD project containing the instance. |
| `cleanup_bootstrap_instance_name` | `capi-bootstrap-0` | Instance to delete. |
| `cleanup_bootstrap_force_stop` | `true` | Force-stop the instance if running before deleting. |
| `cleanup_bootstrap_delete_timeout` | `60` | Seconds the delete operation may take. |
| `cleanup_bootstrap_remove_artifacts` | `true` | Whether to wipe the runner-side artifacts root. |
| `cleanup_bootstrap_artifacts_root` | `""` | Absolute path to wipe (`delegate_to: localhost`). Empty = skip. |
| `cleanup_bootstrap_flow_control_instance` | `true` | Skip the delete step (keeps preflight + healthchecks). |
| `cleanup_bootstrap_flow_control_artifacts` | `true` | Skip the artifacts-root removal step. |

## Tags

Both `_` and `-` spellings are accepted (plan §2.6.3):

* `cleanup_bootstrap` / `cleanup-bootstrap` — whole role.
* `cleanup_bootstrap_preflight` — input validation only.
* `cleanup_bootstrap_instance` — the delete step.
* `cleanup_bootstrap_artifacts` — runner-side artifacts-root removal.
* `cleanup_bootstrap_healthchecks` — post-delete assertions.

## Idempotence

The role is a no-op across every combination of
(daemon reachable?, project present?, instance present?). A single
REST GET against the exact instance URL decides whether to call the
delete module. Re-runs after a successful cleanup, or first-time runs
against a never-bootstrapped host, both report `changed=false`.

## Example

```yaml
- hosts: k8slab_host
  become: true
  roles:
    - role: cleanup_bootstrap
      vars:
        cleanup_bootstrap_project: "capi-lab"
        cleanup_bootstrap_instance_name: "capi-bootstrap-0"
```

## Caveats

* **This is not a full Phase 8 teardown.** Plan §19.2 lists a broader
  destroy contract (workload + management clusters, Helm add-ons,
  substrate, host harness). That orchestrator sequences this role
  alongside other cleanup roles — do not rely on this role alone for a
  clean local redeploy.
* **Force-stop is the default.** A leftover bootstrap container is
  worse than a hard stop during cleanup, so the role does not offer a
  "graceful only" mode. If a consumer needs graceful shutdown they can
  set `cleanup_bootstrap_force_stop: false` and stop the container via
  the LXD API first.
* **Artifacts removal runs on the runner.** The `artifacts` step uses
  `delegate_to: localhost` + `become: false` because export_artifacts
  wrote these files on the runner, not the target VM. `.artifacts/`
  is typically owned by the invoking user so no sudo is needed — if
  your environment relies on root-owned artifacts, pre-chown them
  before running cleanup.
