# 0012. API servers are published through LXD proxy devices; the host firewall is out of scope

Status: Accepted, 2026-11-16

## Context

The API servers of the bootstrap cluster, `mgmt-1` and every workload cluster listen inside
containers on the internal network, which the runner cannot reach. Rules in the host's
firewall would write into a ruleset the operator owns and outlive the cluster they served. A
per-cluster task in Ansible would make every workload cluster need an Ansible run
([0005](0005-one-owner-per-cluster.md)).

## Decision

- Each API server is published by an LXD proxy device with `bind: host`: the LXD daemon listens
  on the host and connects into the instance. LXD owns the device; it goes with the instance.
  The bootstrap instance gets `k3s-api` (host port `bootstrap_api_port`, 16443) when it is
  created.
- `mgmt-1` and every workload cluster: device `api-proxy` on CAPN's load-balancer instance,
  to its local port 6443, added by the Cluster chart's post-install and post-upgrade hook Job
  ([`attach.py`](../../charts/capi-workload-cluster/files/attach.py): Python standard library,
  image pinned by digest). The Job finds the load balancer by the properties CAPN sets on it,
  verifies TLS on every connection (LXD's pinned certificate, the service-account CA, the
  cluster CA), and returns when the API server answers `/livez` through the load balancer.
  The port is `apiProxy.port`, or `20000 + adler32(name) mod 10000`, recorded in the Cluster's
  `k8s-lab.io/api-proxy-port` annotation for Ansible and Terraform. Nothing runs on uninstall.
- The listen address is `k8s_lab_api_listen_address` for the bootstrap cluster and `mgmt-1`,
  the module's `api_proxy.listenAddress` for a workload cluster, `0.0.0.0` in the reference.
  Kubeconfigs pin `tls-server-name: kubernetes.default.svc`, so any address that reaches the
  port works.
- No role writes to the host's firewall. Who may connect is decided by the deployment's own
  firewall or a narrower listen address.

## Consequences

- Publication works alike for every cluster, needs no host-side step, leaves nothing behind.
- With `0.0.0.0` on a host with a public address, every API server is on the internet with
  only Kubernetes authentication in front of it; [deploy.md](../deploy.md) shows how to
  restrict it.
- The hook Pod on the management API mounts the CAPN identity Secret, so it can call LXD with
  CAPN's credentials, and may read the cluster's kubeconfig Secret.
- Two cluster names can hash to the same port; one of them then needs `apiProxy.port`. A
  daemon reload of LXD keeps the devices working ([lxd.md](../runbooks/lxd.md)).
