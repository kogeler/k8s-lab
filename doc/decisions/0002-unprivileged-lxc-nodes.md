# 0002. Nodes are unprivileged LXC system containers, with no privileged path

Status: Accepted, 2026-11-16

## Context

CAPN, the Cluster API infrastructure provider for Incus and LXD, creates nodes as virtual
machines or as containers, privileged or not. Root in a privileged container is root on the
host; LXD documents such containers as not root-safe. Kubernetes in a container needs
nesting for containerd, `/dev/kmsg`, kernel modules and a kubelet that accepts a user
namespace, and each of these is a reason to reach for privileges when something fails.

## Decision

- Every node and the bootstrap instance is an unprivileged container. No input, profile,
  toggle or documented fallback makes one privileged.
- The LXD project enforces it: `restricted=true` with
  `restricted.containers.privilege=unprivileged`, and host disks only from `/boot`
  ([`vars/main.yml`](../../ansible/roles/lxd/vars/main.yml)); the substrate scenario asserts
  that LXD refuses a privileged instance and a disk from `/etc`. CAPN's client certificate is
  restricted to that project ([`capn_identity`](../../ansible/roles/capn_identity/)).
- The node profiles carry what kubeadm needs, and no role input extends them:
  `security.nesting`, `security.idmap.isolated`, `mknod` and `setxattr` interception,
  `/dev/kmsg`, `/boot` read-only, a list of kernel modules, and an unconfined AppArmor profile
  through `raw.lxc`. The class chart sets `unprivileged: true` and `instanceType: container`,
  replaces CAPN's kubeadm profile with these, and starts every kubelet with
  `KubeletInUserNamespace=true`.
- When the unprivileged path fails a gate, the answer is another component or VM-based nodes
  (outside this repository), never privileges.

## Consequences

- Root in a node maps to an unprivileged ID range of its own on the host, and CAPN's
  credentials cannot reach instances outside the project.
- It is not full confinement: nodes run with nesting, syscall interception and AppArmor
  unconfined, which the project has to allow (`restricted.containers.*`).
- A container cannot load kernel modules: role `host` loads them on the host, now and at boot.
- Whatever needs real host privileges is out: Calico's eBPF dataplane
  ([0013](0013-calico-and-metallb.md)), Pods that load modules or own host devices. Node images
  must work unprivileged; CAPN's prebuilt `capi:kubeadm/<version>` images do.
