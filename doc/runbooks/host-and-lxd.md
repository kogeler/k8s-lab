# Host or LXD configuration change

## When to use

An input of role `host` (the versions and checksums of the binaries under
`k8s_lab_opt_root/bin`) or of role `lxd` (settings of the bridge, the internal
network, the storage pool, the project, the profiles, the listener) changes on
a host that runs clusters. For the LXD snap itself see [lxd.md](lxd.md).

## Preconditions

- The change is an input in `defaults/main.yml` of the role (or a common
  `k8s_lab_*` variable). Role `lxd` updates objects in place through the LXD
  API; it never re-creates a network, pool or profile that instances use, and
  it never restarts the daemon.
- Names are fixed for the life of a deployment: the project, the network, the
  pool, the bridge, `k8s_lab_management_cluster_name`,
  `k8s_lab_cluster_namespace`, `k8s_lab_infrastructure_secret_name` and
  `k8s_lab_opt_root`. A new name creates a second object next to the one in
  use: a new project moves CAPN's identity away from every running node, and a
  new management cluster name makes the next run bootstrap a second `mgmt-1`.
- Two changes are refused before anything happens: another
  `lxd_storage_source` for an existing pool (LXD cannot move a pool), and new
  `lxd_network_ipv4_address`/`lxd_network_ipv6_address` while instances are
  attached (it would strand them). Both mean new nodes; plan them as a
  rebuild.

## Steps

1. Set the input in `group_vars/all.yml`, e.g. the internal network's lease
   time:

   ```yaml
   lxd_network_dhcp_expiry: "336h"
   ```

2. Run `<playbook>`. Every role checks the live state and changes only what
   differs; the clusters keep running.

## Verify

```bash
lxc network get capi-int ipv4.dhcp.expiry                                  # host: the new value
ssh <host> sudo lxc list --project $PROJECT --format json \
  | jq -r '.[] | [.name, .status, (.state.pid|tostring)] | @tsv'          # same PIDs as before
```

The playbook reports the change once (a second run changes nothing), the
setting holds the new value, every instance runs with the init PID and
addresses it had, the published API servers answer.

## Rollback

Set the previous value and run `<playbook>` again.

## Tested

2026-11-16, harness, both clusters running: `lxd_network_dhcp_expiry`
168h → 336h — one change (`update capi-int`), the network showed 336h, all ten
instances kept their PIDs and addresses, both API servers answered; reverted to
168h the same way. Every playbook run of the session also ran both roles over
live clusters without a change. Not exercised: limiting a run with `--tags`.
