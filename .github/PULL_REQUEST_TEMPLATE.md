<!--
See CONTRIBUTING.md and doc/development.md ("Done").
-->

## What changes and why

<!-- 1-3 sentences on the why; the diff shows the what. -->

## Test evidence

<!-- The recap lines of the runs: make check, the affected scenario with
idempotence, make test-e2e on a fresh VM when roles, playbooks, charts,
modules or the harness changed. -->

```
```

## Checklist

- [ ] `make check` passes.
- [ ] The affected scenario ran with idempotence; `make test-e2e` on a fresh VM if roles, playbooks, charts, modules or the harness changed.
- [ ] Docs of what changed are updated; generated pages regenerated.
- [ ] A change to `k8s_lab_*` variables updates `doc/variable-contract.md` and `tests/playbooks/group_vars/all.yml`.
- [ ] An entry under `## [Unreleased]` at the top of `CHANGELOG.md` (heading created if missing).
- [ ] No raw manifest application introduced.
