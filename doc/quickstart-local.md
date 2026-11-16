# Quickstart: the local lab

The whole flow on a local Debian 13 VM: host, LXD, bootstrap cluster, `mgmt-1`,
pivot, and a workload cluster through Terraform. The VM plays the host; your
machine is the runner. About 15 minutes on a warm cache.

## Prerequisites

On the runner (Linux, x86_64):

- KVM (`/dev/kvm` readable and writable by you) and libvirt's system daemon
  (`qemu:///system`, you in the `libvirt` group).
- Vagrant with the `vagrant-libvirt` plugin.
- 16 GiB of free memory and 60 GiB of disk: the VM gets 12 GiB and 8 vCPUs,
  plus a 40 GiB pool disk (`K8SLAB_MEM_MB`, `K8SLAB_VCPUS`,
  `K8SLAB_LXD_POOL_GB` change that).
- [uv](https://docs.astral.sh/uv/), and the binaries in
  [`.tool-versions`](../.tool-versions) on `PATH` (Terraform, Helm, kubectl;
  tflint, terraform-docs, kubeconform, shellcheck and actionlint for
  `make check`), plus `curl`, `jq`, `git`, GNU `make`.

On Debian or Ubuntu:

```bash
sudo apt install -y libvirt-daemon-system libvirt-clients qemu-kvm vagrant curl jq git make
sudo usermod -aG libvirt,kvm "$USER"    # log in again
sudo apt install -y vagrant-libvirt     # where the distribution packages the plugin, else:
# sudo apt install -y libvirt-dev ruby-dev gcc make && vagrant plugin install vagrant-libvirt
```

## Set up the checkout

```bash
uv sync --locked --all-groups           # .venv with Ansible, Molecule, linters, MkDocs
source .venv/bin/activate               # or run each target as `uv run make <target>`
make deps                               # the locked Ansible collections and chart dependencies
make check                              # every static and render check
```

## Run the flow

```bash
make test-e2e
```

It starts the VM (`make vm-up`), prepares it (a router that advertises the
external IPv6 prefix, a client behind it), runs
[`tests/playbooks/management.yml`](../tests/playbooks/management.yml) and the
Terraform roots of the fixture cluster `lab-default`, runs everything a second
time (nothing may change), and verifies: nodes, addresses and routes, the
pivot, external reachability of a VIP and a NodePort, a scale up and down, and
the destroy of `lab-default`. Follow a long run in a log:

```bash
make test-e2e > .cache/e2e.log 2>&1 &
tail -f .cache/e2e.log
```

## Look around

`mgmt-1` stays up after the run; `lab-default` was destroyed by the verify.

```bash
export KUBECONFIG=$PWD/.artifacts/mgmt.kubeconfig
kubectl get clusters,machines -A
make deploy-workload                    # lab-default again: its cluster root, then its add-on root
(umask 077; mkdir -p .artifacts/clusters; terraform -chdir=tests/fixtures/terraform/workload-clusters/lab-default/addons \
  output -raw kubeconfig > .artifacts/clusters/lab-default.kubeconfig)
kubectl --kubeconfig .artifacts/clusters/lab-default.kubeconfig get nodes
make -C tests/vagrant/debian13 ssh      # a shell on the VM: sudo lxc list --project capi-lab
```

`.artifacts/` holds the kubeconfigs and `handoff.json`, all mode 0600. The
fixture roots in `tests/fixtures/terraform/workload-clusters/lab-default/` are
what a deployment copies for each cluster
([workload-clusters.md](runbooks/workload-clusters.md)).

## Smaller runs

| Command | What it runs |
|---|---|
| `make test-substrate` | `tests/playbooks/substrate.yml` (roles `host`, `lxd`), a second run, checks |
| `make test-bootstrap` | the substrate plus the bootstrap cluster, providers and CAPN identity |
| `make test-substrate VARS=alt-vars.yml` | the same with a second value for every name, address, port and path (on a fresh VM) |
| `make -C tests/molecule e2e-local-converge` | one action of a scenario: `prepare`, `converge`, `idempotence`, `verify`, `destroy` |

## Tear down

```bash
make destroy-workload                   # the workload cluster (add-on root, then cluster root)
make vm-destroy                         # the VM, then everything `make clean` removes
make clean                              # only the runner side: .artifacts/, Terraform state, Molecule state
```

`make vm-reboot` reboots the VM and waits until it answers again. `make help`
lists every target.

## When it does not work

- `make vm-up` names the missing piece: Vagrant, the plugin, `/dev/kvm`, or
  libvirt.
- A run that hangs: watch the machines (`kubectl get machines -A` with the
  kubeconfig of the cluster that manages them) and the controllers' logs.
- More in [troubleshooting](troubleshooting.md); the harness itself is
  described in [development](development.md#test-harness).
