<!--
Thanks for the PR. Please confirm the items below before requesting review.
See CONTRIBUTING.md for the project scope and policy.
-->

## What changes and why

<!-- 1-3 sentences focused on the why. The diff already shows the what. -->

## Affected layer

- [ ] Ansible role(s):
- [ ] Helm chart(s):
- [ ] Terraform module:
- [ ] Molecule / Vagrant harness:
- [ ] Documentation under `doc/`:
- [ ] Plan section(s) `§N` updated:

## Test evidence

<!--
Per project policy: no untested commits. Paste evidence below — Molecule
converge output, terraform plan, helm test result, or harness e2e log.
-->

```
```

## Checklist

- [ ] `make lint` passes locally.
- [ ] Matching Molecule scenario converges + verifies on the local Vagrant VM.
- [ ] If this changes a variable contract, `doc/08-configuration-reference.md` is updated in the same PR.
- [ ] If this changes architectural behaviour, the relevant `plans/PLAN-stage*.md §N` is updated in the same PR.
- [ ] No raw manifests / `kubectl apply -f` paths introduced.
