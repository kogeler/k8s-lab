# 0015. Every dependency is pinned at its latest stable release and verified

Status: Accepted, 2026-11-16

## Context

The lab rests on a long chain of upstream releases: Kubernetes and k3s, Cluster API, CAPN,
LXD, Calico, MetalLB, Helm and Terraform providers, Ansible collections, Python tooling, CI
actions. Unpinned inputs make two runs of one commit differ; old pins collect known defects
and fall out of upstream support. A binary fetched at run time is a supply-chain risk unless
it is checked.

## Decision

- A pin is raised to the current upstream stable release whenever it is touched, after
  checking upstream; no upper bound locks out a new major version. The versions in use are in
  [versions.md](../reference/versions.md).
- Role `host` downloads `kubectl`, `clusterctl` and `k3s` into `<k8s_lab_opt_root>/bin`
  (`/opt/capi-lab/bin`), each checked against a sha256 pinned in `group_vars` next to its
  version, not one fetched from the same origin.
- Kubernetes, k3s, Cluster API and CAPN versions are common variables. Calico and MetalLB are
  exact chart dependencies with a committed `Chart.lock`. Images in chart values carry a tag
  and a digest.
- The runner's tooling: one `uv` project (`pyproject.toml` with lower bounds, `uv.lock` with
  exact versions and hashes); Ansible collections from `requirements.yml` (lower bounds),
  installed by `make deps` from `requirements.lock.yml` (exact, transitive ones included);
  binaries at the versions in `.tool-versions`, which CI installs; Terraform providers locked
  in each root's `.terraform.lock.hcl`; GitHub Actions pinned by commit SHA; the Vagrant box
  by version.
- `make deps-upgrade` re-resolves both locks. There is no update bot: every bump is a
  deliberate change, tested on the harness.

## Consequences

- Two runs of one commit install the same pinned versions, and a bump is one visible diff.
- Staying current is manual work. Without a bot, a stale pin shows only when someone looks, or
  when the nightly e2e run breaks on something unpinned.
- Not everything is pinned by content: node images are `capi:kubeadm/<version>` aliases on
  CAPN's image server (a fingerprint is an optional chart value), the bootstrap image is the
  `debian/13/cloud` alias, the LXD snap follows its channel, apt packages follow the
  distribution, and the images of the upstream charts (the tigera-operator and the Calico
  components it deploys, MetalLB's controller and speakers) are the tags their chart
  version names.
- The host binaries are pinned for amd64 only, as the OS gate requires x86_64; Kubernetes
  versions are limited to those CAPN publishes node images for.
