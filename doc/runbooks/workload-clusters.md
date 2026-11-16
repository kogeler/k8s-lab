# Add or remove a workload cluster

Each workload cluster is a pair of Terraform roots — the cluster
(`terraform/modules/workload_cluster`), then its add-ons
(`terraform/modules/workload_addons`). Adding one is a new pair; nothing runs
on the Ansible side unless it lives in a namespace of its own.

## When to use

Another workload cluster on the same `mgmt-1`, or one that is no longer
needed.

## Preconditions

- Room on the host for its nodes (on the 12 GiB harness: `mgmt-1` and two
  workload clusters of one control-plane machine and two workers each).
- A name of its own: it names the Helm releases, the ClusterClass, the LXD
  instances, and the published API port (`20000 + adler32(name) mod 10000`;
  if two names land on the same port, give one an explicit port through the
  module input `api_proxy = { port = … }`).
- A VIP range on the external network that no other cluster uses.
- Pod and Service CIDRs: they may repeat across clusters (nothing routes
  between their Pod networks — on the harness all three clusters use the
  same), but must not overlap the internal node network or the external
  prefix.
- Its namespace holds the CAPN identity Secret: `k8s_lab_cluster_namespace`,
  or one added through [capn-identity.md](capn-identity.md).

## Steps — add

1. Copy a pair of roots without their `.terraform/` and state (the fixture
   pair `lab-default` is the template):

   ```bash
   mkdir -p lab-two/cluster lab-two/addons
   cp lab-default/cluster/{main.tf,variables.tf,versions.tf,terraform.tfvars,.terraform.lock.hcl} lab-two/cluster/
   cp lab-default/addons/{main.tf,outputs.tf,variables.tf,versions.tf,terraform.tfvars,.terraform.lock.hcl} lab-two/addons/
   ```

   On the harness the copy goes next to `lab-default`: the fixture's module
   `source` and default `handoff_path` are relative to that directory. A
   deployment points them at a release of this repository and at its
   `handoff.json` (and at its `mgmt.kubeconfig` through `mgmt_kubeconfig_path`
   when Terraform runs on another machine than Ansible), and gives each root
   its own state backend ([deploy.md](../deploy.md#a-workload-cluster)).
2. Set its values. `lab-two/cluster/terraform.tfvars`:

   ```hcl
   name                = "lab-two"
   kubernetes_version  = "v1.37.0"
   control_plane_count = 1
   worker_count        = 2
   pod_cidrs           = ["10.244.0.0/16", "fd42:77:2::/56"]
   service_cidrs       = ["10.96.0.0/16", "fd42:77:3::/112"]
   ```

   `lab-two/addons/terraform.tfvars`:

   ```hcl
   name = "lab-two"
   metallb = {
     pool = { rangeV6 = "2001:db8:42:100::400-2001:db8:42:100::4ff" }
   }
   ```

   In another namespace, add it to both files: `namespace = "k8s-lab-two"`
   (unset, the roots take the handoff's `cluster_namespace`).
3. Apply the cluster root, then the add-on root:

   ```bash
   terraform -chdir=lab-two/cluster init
   terraform -chdir=lab-two/cluster apply
   terraform -chdir=lab-two/addons init
   terraform -chdir=lab-two/addons apply
   ```

4. Its kubeconfig ([kubeconfig.md](kubeconfig.md)):

   ```bash
   (umask 077; terraform -chdir=lab-two/addons output -raw kubeconfig > lab-two.kubeconfig)
   ```

## Steps — remove

1. Destroy the add-on root, then the cluster root:

   ```bash
   terraform -chdir=lab-two/addons destroy
   terraform -chdir=lab-two/cluster destroy
   ```

   If the cluster's API no longer answers, skip the add-on root: its objects
   live inside the cluster and go with it ([teardown.md](teardown.md)).
2. Delete the pair of roots and their state; retire its namespace if it had
   one ([capn-identity.md](capn-identity.md)).

## Verify

```bash
kubectl --kubeconfig $MGMT get clusters -A
kubectl --kubeconfig lab-two.kubeconfig get nodes
lxc list --project $PROJECT                     # host
```

Added: the Cluster `Available`, its nodes `Ready`, both gates passed in the
add-on apply. Removed: no Cluster, no instance named after it, no Helm release
of it on `mgmt-1` (`helm list -A --kubeconfig $MGMT`).

## Rollback

Adding: destroy it as above. Removing cannot be undone; the cluster is
created anew from its roots.

## Tested

2026-11-16, harness, next to `mgmt-1` and `lab-default` (one control-plane
machine and two workers each). `lab-two` in namespace `k8s-lab-two`, created
with the CAPN identity rotated just before: cluster root 31 s, add-on root
about 1.5 minutes, both gates passed; 12 instances, 4.2 GB of 12 GB free.
Removed in the order above, the namespace retired.
