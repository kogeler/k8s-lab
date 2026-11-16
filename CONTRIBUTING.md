# Contributing

k8s-lab ships reusable roles, charts and modules; a deployment's inventory,
secrets, variables and Terraform state live in its own repository. The
[development guide](doc/development.md) has the layout, the conventions, the
harness and the definition of done; the [decision records](doc/decisions/README.md)
say why things are the way they are.

## Before opening a pull request

```bash
uv sync --locked --all-groups && source .venv/bin/activate
make deps
make check                 # the Lint workflow runs the same
make test-substrate        # a role changed: its scenario, with idempotence
make test-bootstrap
make vm-destroy && make test-e2e   # roles, playbooks, charts, modules or the harness changed
```

Quote the recap of the runs in the pull request. The `e2e` workflow runs the
same flow on a GitHub Actions runner (`make test-gha`); it changes the machine
it runs on and refuses to run anywhere else — use `make test-e2e` locally.

A pull request also updates the docs of what it changes, regenerates the
generated pages, and adds an entry under `## [Unreleased]` at the top of
`CHANGELOG.md`, creating the heading when it is missing
([done](doc/development.md#done)).

## Scope

| Welcome | Out of scope |
|---|---|
| Fixes in the roles, charts, modules and harness | Site-specific inventories, secrets, variables |
| Documentation fixes | Privileged containers, in any form |
| Tests for existing behavior | Raw manifest application (`kubectl apply -f`) |
| Items of the [roadmap](ROADMAP.md), after the design is agreed in an issue | Rules in the host's firewall |

A change of architecture comes with a new [decision record](doc/decisions/README.md).

## Reporting issues

Open a GitHub issue with what you ran (commit, role, chart or module, `make`
target), what happened (logs, `terraform plan`, the Molecule failure, the
output of `scripts/collect-diagnostics.sh`) and what you expected. Security
issues: [SECURITY.md](SECURITY.md).
