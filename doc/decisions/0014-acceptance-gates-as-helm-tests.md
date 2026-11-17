# 0014. Acceptance gates and the convergence check are Helm tests

Status: Accepted, 2026-11-16

## Context

A cluster can be installed while its network does not work (nodes NotReady, one address
family broken, no VIP assigned) or while machines still roll after a change; a run must stop
there. A gate must not break the rules it guards: no `kubectl apply`, nothing downloaded at
run time, no standing permissions, nothing left behind.

## Decision

- Each check is the `helm test` of the release whose component it proves, run by that
  cluster's owner: role `management_cluster` on every run for `mgmt-1`; for a workload
  cluster, `terraform_data` resources of `workload_addons`, replaced when their releases'
  revisions or the Cluster's generation or class revision change. A failure stops the run.
- Gate B (`cni-calico-config`): the `Installation` reports the chart's Calico version (the
  operator rolls `calico-node` after its own release is ready) and every node is Ready; then
  two `agnhost` servers on two different workers behind a dual-stack headless Service, and a
  client that reaches each over IPv4 and IPv6.
- Gate A (`metallb-config`): an `agnhost` server behind an IPv6 `LoadBalancer` Service that
  takes an address from the release's pool as any Service would; a client Pod reads the
  assigned address from the Service (a Role on that one Service) and fetches it, accepting
  only its own server's answer. Helm waits for test Pods and Jobs only: the clients retry
  until their deadline.
- The convergence check (`capi-workload-cluster`) runs on the management API: one
  `kubectl wait` after another, each counting a condition only for the object's current
  generation: topology reconciled, control plane and MachineDeployments neither rolling out
  nor scaling, their machines Ready, the Cluster Available. It is a Job (`backoffLimit: 0`,
  Pod disruptions ignored), so a drain of its node during `mgmt-1`'s own rollout restarts it
  instead of failing it. Terraform runs it after Calico and before Gate B.
- Test objects are hook resources deleted on success, on images by tag and digest, with
  nothing downloaded at run time. Gate B's read-only ClusterRole (nodes, the `Installation`) is
  the only object left. `tests.probePort` makes a gate fail on purpose.

## Consequences

- A green run means the cluster converged and both data paths answered, after every change.
- Gate A proves that a VIP is assigned and answers inside the cluster, not that it is reachable
  from outside: the e2e verify checks that from the host and from a client in another prefix,
  and a deployment checks it on its real uplink.
- `helm test --logs` prints only bare Pods; the convergence check's output is in
  `kubectl logs job/<cluster>-test-cluster-ready --all-containers`.
- Every change pays seconds to minutes for the checks; Gate B needs two workers.
