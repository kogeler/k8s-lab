# CAPN identity: rotation and a new namespace

CAPN reaches LXD with a client certificate that role `capn_identity` creates on
the host, trusts in LXD restricted to the project, and copies with its key into
a Secret in every namespace listed in `capn_identity_namespaces`. Outside the
cluster (its etcd, its snapshots and backups) the key lives only in
`capn_identity_dir` on the host.

## When to use

- **Rotation**: before the certificate expires (`capn_identity_validity_days`,
  default 1825), after the key may have leaked, or as routine.
- **New namespace**: workload clusters are to live in a namespace other than
  `k8s_lab_cluster_namespace`.

## Preconditions

- The management playbook can run against the host.
- Rotation: every namespace that holds a cluster is in
  `capn_identity_namespaces`. The run removes the old trust entry, so a
  cluster in a namespace that is not listed keeps the old certificate and
  loses access to LXD.

## Steps — rotation

1. Run `<playbook>` once with rotation on, as an extra variable — not in
   `group_vars`, or every later run rotates again:

   ```bash
   ansible-playbook -i <inventory> <playbook> -e capn_identity_rotate=true
   ```

   In that run the role makes a new key and certificate, trusts it in LXD next
   to the old one, writes it into every listed namespace's Secret, checks that
   LXD accepts it, and only then removes the earlier trust entries. CAPN reads
   the Secret at every reconcile; nothing restarts. If the run is interrupted,
   the next run completes the rotation.

## Steps — a new namespace

1. Add it to `capn_identity_namespaces` in `group_vars/all.yml`:

   ```yaml
   capn_identity_namespaces: ["capi-clusters", "k8s-lab-two"]
   ```

2. Run `<playbook>`: the namespace is created, the Secret is written there
   (labelled for `clusterctl move`).
3. Put a cluster there: the `namespace` of both of its roots
   ([workload-clusters.md](workload-clusters.md)).

To retire a namespace: destroy its clusters, take it out of the list, then
delete it — the role adds Secrets, it does not remove them:

```bash
kubectl --kubeconfig $MGMT delete namespace k8s-lab-two
```

## Verify

```bash
lxc config trust list --format csv            # host
kubectl --kubeconfig $MGMT -n $NS get secret <k8s_lab_infrastructure_secret_name> -o jsonpath='{.data.client-crt}' \
  | base64 -d | openssl x509 -noout -fingerprint -sha256 -enddate
kubectl --kubeconfig $MGMT -n capn-system logs deploy/capn-controller-manager --since=5m | grep -i error
kubectl --kubeconfig $MGMT get lxcclusters,lxcmachines -A
```

One client entry, `k8slab-capn-<first 12 hex digits of the fingerprint>`, the
same fingerprint in every listed namespace's Secret, no authentication errors,
every LXC object ready. The proof is the next machine CAPN creates.

## Rollback

A rotation cannot be undone: the old key is deleted and its trust entry
removed. Rotate again if the new certificate is in doubt.

## Tested

2026-11-16, harness. Rotation in one run (5 changes): `k8slab-capn-fc78fabd0821`
replaced by `k8slab-capn-e2324b241a09` (valid to 2031-11-15), the Secret
carried the new certificate, CAPN logged no error, and the second workload
cluster created afterwards ([workload-clusters.md](workload-clusters.md)) got
its machines with it. An interrupted rotation completed by the next run was
drilled the same day. Namespace `k8s-lab-two` added, used by that cluster,
retired after it was destroyed.
