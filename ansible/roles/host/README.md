# host

## Purpose

Prepares the host for LXD and the Kubernetes nodes inside it: the APT packages the
other roles need, kernel modules and sysctls, the opt root, and pinned `kubectl`,
`clusterctl` and `k3s`. It does not install LXD (role `lxd`) and never touches
the firewall.

## Requirements

- An x86_64 Debian 13+ or Ubuntu 22.04+ host with swap off, reachable over SSH with
  `become`; facts gathered.
- Collections `ansible.posix` and `community.general`.
- No role dependencies.

## Inputs

Declared in `meta/argument_specs.yml`. The common variables `k8s_lab_opt_root`,
`k8s_lab_{kubectl,clusterctl,k3s}_version` and `k8s_lab_{kubectl,clusterctl,k3s}_sha256`
are required ([variable contract](../../../doc/variable-contract.md)); every
`host_*` input defaults to one of them. `host_enabled` and one
`host_flow_control_<area>` per area (`preflight`, `packages`, `kernel`, `dirs`,
`binaries`) switch the role or an area off.

## What it changes

- APT: `snapd`, `ca-certificates`, `python3-cryptography`.
- Kernel: loads `overlay`, `br_netfilter`, `nf_conntrack`, and `nft_compat`,
  `xt_connmark`, `xt_mark` (the nodes' reply marks on `eth1`) and lists them in
  `/etc/modules-load.d/`; writes `/etc/sysctl.d/60-k8s-lab.conf` (IPv4 and IPv6
  forwarding, inotify limits) and applies it.
- Files: `<opt_root>/`, `<opt_root>/etc/`, `<opt_root>/bin/{kubectl,clusterctl,k3s}`
  (root, 0755).

## Re-running

Safe on a live host: packages are only added, nothing is restarted. A binary is
downloaded only when its digest differs from the pin, so a re-run with unchanged
pins needs no download host; a new version and digest in the common variables
replace the file in place. Forwarding on the host's interfaces makes the kernel
ignore router advertisements on them unless `accept_ra=2`: a host that takes its own
IPv6 default route from RA needs that setting on its uplink.

## Removing

Nothing removes this. To undo by hand: delete `<opt_root>`,
`/etc/sysctl.d/60-k8s-lab.conf` and the module entries in `/etc/modules-load.d/`.

## Tested by

`tests/molecule/substrate` (`verify/host.yml`), and every scenario built on it.
