# Host reboot

## When to use

The host restarts — planned (kernel update) or not (power loss).

## What happens, with nothing to do

- On shutdown the LXD snap stops every instance cleanly (30 s, then it kills
  what is left). On boot LXD starts every instance that was running before
  (no `boot.autostart` needed).
- etcd, the API servers and the kubelets start with their instances; `mgmt-1`
  (one control-plane machine) restarts from its own disk. Until `mgmt-1` is
  back nothing reconciles any cluster; Cluster API itself does nothing on a
  restart and replaces no machine (no MachineHealthCheck is shipped; on one
  host every node is NotReady at the same time after a reboot, so one would
  have to tolerate all of them).
- Addresses survive: `eth0` leases on the internal network last 168 hours
  (`lxd_network_dhcp_expiry`), `eth1` addresses are derived from each
  instance's MAC address and the advertised prefix, the published API ports
  are proxy devices of the load-balancer instances.
- Every node reloads its `eth1` reply marks at boot (a unit before the
  kubelet).

## Preconditions

None. Before a planned reboot, a backup ([backup-restore.md](backup-restore.md))
is cheap insurance.

## Steps

1. Reboot the host (`systemctl reboot`; on the harness `make vm-reboot`).
2. Wait until the clusters are back (`Verify`).
3. Optionally run `<playbook>`: it must change nothing.

## Verify

```bash
lxc list --project $PROJECT                       # host: every instance RUNNING
kubectl --kubeconfig $MGMT get nodes
kubectl --kubeconfig $MGMT get clusters -A        # AVAILABLE True
kubectl --kubeconfig <cluster kubeconfig> get pods -A
curl -sk -o /dev/null -w '%{http_code}\n' https://<host>:<published port>/livez
```

Every instance running with the addresses it had, every node `Ready`, every
Pod running, the published API servers answering, a LoadBalancer Service
reachable from outside the external link and a NodePort on a node's `eth1`.

## Rollback

Not applicable.

## Tested

2026-11-16, harness (`make vm-reboot`, 10 instances: `mgmt-1` 1 + 2,
`lab-default` 3 + 2): 26 s after the VM answered 7 of 10 instances were
running, at 43 s all, with every node `Ready` and both Clusters `Available`;
every Pod of both clusters running 75 s after the VM answered. Every
instance's `eth0` and `eth1` addresses unchanged, both published API ports
answering; on both clusters a VIP answered from the host and from a client
behind the external router, a NodePort on `eth1` (and not on `eth0`). The
playbook run afterwards changed nothing.
