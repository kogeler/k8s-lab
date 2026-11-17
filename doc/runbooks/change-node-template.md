# Change the node template

## When to use

A machine setting changes: kubelet arguments, kubeadm commands, LXD profiles,
devices, flavors or images of the control plane or the workers — the values of
`charts/capi-cluster-class`. Cluster API never edits a running machine: a
changed template is a new template object, and every machine made from the old
one is replaced.

The load balancer's values (`loadBalancer.*`) are different: CAPN creates the
load-balancer instance once and never replaces it, so a change reaches only a
cluster created afterwards.

## Preconditions

- The change is in the class chart's values. The chart reserves what the
  substrate needs — the kubelet's `feature-gates`, `node-ip` and `provider-id`,
  and the API server and controller-manager flags its `values.yaml` lists —
  and these are not inputs.
- The cluster is `Available`, and a rolling replacement of the affected
  machines is acceptable now (a control-plane change replaces every
  control-plane machine, one at a time).
- One change per apply.

## Steps — workload cluster

1. Set the values in `cluster_class_values` of `<root>/cluster/terraform.tfvars`,
   e.g. a kubelet argument on the workers:

   ```hcl
   cluster_class_values = {
     worker = {
       kubeletExtraArgs = [{ name = "max-pods", value = "120" }]
     }
   }
   ```

2. Plan and apply the cluster root, then the add-on root. The plan updates the
   class release and the Cluster release (the class revision it records); the
   template whose spec changed gets a new name, the ClusterClass points at it,
   the old template is removed, and Cluster API replaces the machines made from
   it. The add-on root's convergence check waits for the replacement, then both
   gates run.

   ```bash
   terraform -chdir=<root>/cluster plan
   terraform -chdir=<root>/cluster apply
   terraform -chdir=<root>/addons apply
   ```

## Steps — `mgmt-1`

The role passes no class values: `mgmt-1`'s templates change with a new
version of this repository's chart or with the role inputs that reach them
(`management_cluster_external_ipv6_prefix` —
[change-external-prefix.md](change-external-prefix.md)). Run `<playbook>`; its
gates wait for the replacement.

## Verify

```bash
kubectl --kubeconfig $MGMT -n $NS get kubeadmcontrolplanetemplates,kubeadmconfigtemplates,lxcmachinetemplates,lxcclustertemplates \
  -l app.kubernetes.io/instance=<cluster>-class
kubectl --kubeconfig $MGMT get machines -A
kubectl --kubeconfig <cluster kubeconfig> get nodes \
  -o custom-columns=NAME:.metadata.name,PODS:.status.capacity.pods
terraform -chdir=<root>/cluster plan -detailed-exitcode
terraform -chdir=<root>/addons plan -detailed-exitcode
```

The class release's templates carry the new name for the changed kind only;
the affected machines are new, the others unchanged; the setting shows on the
nodes; both plans exit 0.

## Rollback

Set the previous values and apply both roots again: the template gets its
previous name back (the name is a hash of its spec) and the machines are
replaced once more.

In an emergency, before the roots can be applied, Helm can roll the class
release back on its own — the one step outside Terraform on a release it owns:

```bash
helm rollback <cluster>-class -n $NS --kubeconfig $MGMT
```

Revert `cluster_class_values` in `<root>/cluster/terraform.tfvars` before the
next apply of that root: the apply re-applies whatever the root says, the bad
values included.

## Tested

2026-11-16, harness, `lab-default`: workers `max-pods=120` — worker template
`lab-default-md-0-boot-19b89306` → `…-83edcc44`, only the two workers replaced
(the convergence check waited 2 min), the nodes reported 120 pods; reverted —
the name `…-19b89306` back, the workers replaced again (2 min 18 s), 110 pods,
both plans clean. `helm rollback` of the class release was drilled on
2026-11-16: the previous template returned and the
control plane rolled back.
