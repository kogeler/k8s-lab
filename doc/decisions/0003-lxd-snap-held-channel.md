# 0003. LXD comes from the snap on a pinned channel, with its automatic refreshes held

Status: Accepted, 2026-11-16

## Context

LXD is distributed as a snap, the supported way to install it on Debian and Ubuntu. A snap
refreshes itself: a refresh restarts the LXD daemon at a time nobody chose (the instances
keep running), and a new track upgrades LXD's database, after which the older version cannot
start. A system-wide hold (`refresh.hold=forever`) would freeze `snapd` and every other snap
on the host as well.

## Decision

- Role `lxd` installs the `lxd` snap from `lxd_snap_channel`, default `6/stable`
  ([`snap.yml`](../../ansible/roles/lxd/tasks/snap.yml)). Debian's `snapd` is older than that
  snap requires, so the role installs the `snapd` snap first; the daemon re-executes into it.
- Automatic refreshes are held for the `lxd` snap only (`snap refresh --hold lxd`, no
  expiry); `snapd` and other snaps refresh as usual.
- A refresh within the channel and a daemon reload (`snap restart --reload lxd`) are operator
  steps ([lxd.md](../runbooks/lxd.md)). Changing `lxd_snap_channel` and running the playbook
  is the upgrade, and it is one way.
- The roles use the snap's socket and LXD's own API, including its image registries: the
  restricted project allows the built-in registries and one named `capn` for CAPN's image
  server. LXD listens on the internal network's gateway address only
  (`core.https_address`, port `lxd_listener_port`).

## Consequences

- LXD's fixes reach the host only when an operator refreshes; nothing reminds anyone.
- `snap stop lxd`, and `snap restart lxd` without `--reload`, stop every instance: every node
  of every cluster at once. The runbook warns about it.
- A channel change cannot be undone except by restoring the host
  ([backup-restore.md](../runbooks/backup-restore.md)), and it was not exercised: no newer
  stable track exists yet.
- Incus and distribution packages of LXD are not supported: the roles depend on the snap's
  paths and on LXD-only features. Only the `6` track is supported; the roles wait for its
  asynchronous operations and declare its image registries.
