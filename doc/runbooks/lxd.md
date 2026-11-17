# LXD: refresh, daemon reload, channel change

LXD comes from the `lxd` snap on the channel `lxd_snap_channel` (`6/stable`).
Role `lxd` holds the snap's automatic refreshes (`snap refresh --hold lxd`,
the `lxd` snap only): an update happens when an operator runs it.

## When to use

- **Refresh within the channel**: a new LXD release on the same channel
  (security or bug fixes).
- **Daemon reload**: LXD's daemon has to restart (after a configuration change
  of the snap, or to pick up a refresh) while the nodes keep running.
- **Channel change**: moving to another LXD track.

## Preconditions

- The clusters are `Available`. While the daemon restarts, its API is gone for
  a few seconds: CAPN's reconciles fail and retry; the running nodes and the
  published API ports are not affected.
- **Never** `snap stop lxd`, and never `snap restart lxd` without `--reload`:
  both stop every instance — every node of every cluster at once.
- A channel change is one way: LXD upgrades its database on start and cannot
  go back to an older track.

## Steps — refresh within the channel

1. On the host:

   ```bash
   snap info lxd | grep -E '^(tracking|refresh-date|installed|hold)'
   snap refresh --list
   sudo snap refresh lxd
   sudo /snap/bin/lxd waitready --timeout=300
   ```

   On a refresh snapd stops only the daemon; the instances keep running.

## Steps — daemon reload

1. On the host:

   ```bash
   sudo snap restart --reload lxd
   sudo /snap/bin/lxd waitready --timeout=300
   ```

## Steps — channel change

1. Read the release notes of the new track and check CAPN's support for it.
2. Take the backup of [backup-restore.md](backup-restore.md); LXD leaves a
   copy of its database under `/var/snap/lxd/common/lxd/database` when it
   upgrades the schema.
3. Set `lxd_snap_channel` in `group_vars/all.yml` and run `<playbook>`: role
   `lxd` switches the snap to the new channel, which refreshes it; the hold
   stays.

## Verify

```bash
snap list lxd                                                    # host: version, revision, "held"
ssh <host> sudo lxc list --project $PROJECT --format json \
  | jq -r '.[] | [.name, .status, (.state.pid|tostring)] | @tsv'
kubectl --kubeconfig $MGMT -n capn-system logs deploy/capn-controller-manager --since=5m | grep -ci error
kubectl --kubeconfig $MGMT get lxcmachines -A
```

Every instance still `Running` with the same init PID as before (a restarted
instance gets a new one), the published API servers answering, no CAPN error,
every LXCMachine ready.

## Rollback

A refresh within the channel: `sudo snap revert lxd` returns to the previous
revision while the track is the same (not exercised). A channel change: none —
restore the host from its backup.

## Tested

2026-11-16, harness, both clusters running (10 instances): `snap refresh lxd`
— no update available on `6/stable` (6.10.1, revision 41228 is current);
`snap restart --reload lxd` — the daemon restarted (new PID, "LXD is
reloading"), ready in 5 s; every instance kept its init PID and addresses, both
published API servers answered throughout, CAPN logged no error afterwards.
The channel change was not exercised: there is no newer stable track to move
to, and the move cannot be undone.
