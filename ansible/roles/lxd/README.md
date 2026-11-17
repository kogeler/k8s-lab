# lxd

## Purpose

LXD from its snap and everything the Cluster API nodes run on: the external host
bridge, CAPN's image registry, the restricted project, the btrfs pool, the internal
network, the LXD API listener for CAPN and the node profiles. It creates no
instance and never restarts one.

## Requirements

- Role `host` (a dependency: snapd, kernel modules, forwarding).
- A spare block device for the pool, and an uplink interface for the external
  network that is not the interface of the default route.
- Collection `community.general`.

## Inputs

Declared in `meta/argument_specs.yml`. Required: `lxd_uplink_interface`,
`lxd_storage_source`, and the common variable `k8s_lab_project_name`
([variable contract](../../../doc/variable-contract.md)).
`lxd_enabled` and one `lxd_flow_control_<area>` per area (`snap`, `bridge`,
`registry`, `project`, `storage`, `network`, `listener`, `profiles`) switch the role
or an area off.

## What it changes

- Snaps `snapd` and `lxd` (on `lxd_snap_channel`), with automatic refreshes of
  `lxd` held.
- `/etc/systemd/network/30-<bridge>.netdev`, `30-<bridge>.network`,
  `31-<bridge>-uplink.network`: an address-free bridge with the uplink as its port.
- LXD: image registry `capn`; project `<lxd_project_name>` (restricted:
  unprivileged containers only, disks from the pool or `/boot`, the registries
  `builtin,capn`); pool `<lxd_storage_pool_name>` (btrfs on the source device);
  network `<lxd_network_name>` (NAT, DHCPv4, router advertisements);
  `core.https_address` = the network's IPv4 gateway and `lxd_listener_port`;
  profiles `capi-base`, `capi-bootstrap`, `capi-controlplane`, `capi-worker`.

## Re-running

Safe on a live host; with unchanged inputs nothing is written. An object is
created when missing and updated only in the keys the role sets:

- Profiles are replaced as a whole when they differ (keys added by hand are
  removed). LXD applies device changes and live-updatable settings to the running
  instances that use the profile at once; settings that take effect at start do so
  at the next start. The role restarts nothing: node changes otherwise reach a
  cluster when Cluster API replaces its nodes.
- A changed address of the internal network is refused while instances are on it;
  a changed `lxd_storage_source` is refused for an existing pool.
- A changed `lxd_snap_channel` refreshes LXD in place (instances keep running; the
  database is upgraded one way). Point releases within the channel arrive only by
  `snap refresh lxd` by hand.
- Bridge files that change are applied by a `systemd-networkd` reload; the MTU is in the
  `.network` file as well, since a reload does not update an existing netdev.

## Removing

Nothing removes this. LXD objects can be deleted with `lxc` once no instance uses
them; `snap remove lxd` removes LXD with every instance.

## Tested by

`tests/molecule/substrate` (`verify/lxd.yml`), and every scenario built on it.
