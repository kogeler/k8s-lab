# 0001. One host, reusable building blocks; deployments live in a consumer repository

Status: Accepted, 2026-11-16

## Context

The lab runs every Kubernetes cluster on one bare-metal server: no second machine, no cloud
API. The code that builds it is useful to more than one site, while each site has its own
inventory, addresses, credentials and state. Keeping both in one repository puts real secrets
next to reusable code and turns every change into a deployment.

## Decision

- The target is one x86_64 host with Debian 13 or newer, or Ubuntu 22.04 or newer; role `host`
  holds the only OS gate ([`preflight.yml`](../../ansible/roles/host/tasks/preflight.yml)).
  The local harness runs Debian 13, CI runs Ubuntu 26.04.
- This repository ships building blocks only: six Ansible roles
  ([`ansible/roles/`](../../ansible/roles/)), six Helm charts ([`charts/`](../../charts/)), two
  Terraform modules ([`terraform/modules/`](../../terraform/modules/)), the reference playbooks
  ([`tests/playbooks/`](../../tests/playbooks/)) and the test harness.
- A deployment lives in a consumer repository: its inventory, `group_vars`, secrets, its
  playbooks derived from the reference ones, its Terraform roots with their
  `terraform.tfvars` and state backends. It takes this repository at one release tag twice:
  a checkout for the roles (a git submodule) and a git module source for Terraform. Each
  is the whole repository, and the role `management_cluster` and the modules install the
  charts from the copy they come with, not from a chart repository.
- The only Terraform roots here are the test consumer under
  [`tests/fixtures/terraform/`](../../tests/fixtures/terraform/). Runtime output
  (kubeconfigs, `handoff.json`) goes to `.artifacts/`, which is not committed.

## Consequences

- All clusters share one failure domain: a host reboot takes every node down at once
  ([host-reboot.md](../runbooks/host-reboot.md)), and the host's memory and CPU bound how many
  clusters fit. High availability across hosts is not a goal.
- What only a real site has stays the consumer's to set up and test: the uplink and its
  router, the host firewall, backups kept off the host, Terraform state backends
  ([deploy.md](../deploy.md)).
- A consumer pins a commit or tag and upgrades by moving it. Nothing is published as an
  Ansible collection, a chart repository or a registry module.
