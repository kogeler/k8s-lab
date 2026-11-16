# Certificate expiry

## When to use

Planning for certificate lifetimes, or a client reports an expired
certificate. What renews itself and what has to be re-exported:

| Certificate | Lifetime (reference values) | Renewal |
|---|---|---|
| Control-plane certificates kubeadm issues (API server, etcd, front proxy, the node's `admin.conf`) | `controlPlane.certificateValidityPeriodDays` of the class chart: 1095 days, the most Cluster API allows | Automatic: Kubeadm Control Plane replaces each control-plane machine `controlPlane.certificatesExpiryDays` (60) days before its certificates expire; the new machine gets new certificates |
| Cluster CAs (`ca`, `etcd-ca`, `front-proxy-ca`) | 10 years (kubeadm) | None; a cluster older than that is rebuilt |
| kubelet client certificates | 1 year | Automatic: the kubelet rotates them |
| Client certificate in the `<cluster>-kubeconfig` Secret | 1 year (Cluster API) | Automatic in the Secret when less than six months remain — every copy made from it keeps the old one |
| `mgmt.kubeconfig` on the host and the runner | copy of the Secret | Rewritten from the Secret by every run of the management playbook |
| Workload kubeconfig (`terraform output -raw kubeconfig`) | copy of the Secret | Terraform reads the Secret at every plan and apply; a copy written to a file is re-exported ([kubeconfig.md](kubeconfig.md)) |
| CAPN client certificate | `capn_identity_validity_days`: 1825 days | Manual: rotate before it expires ([capn-identity.md](capn-identity.md)); nothing warns |

## Preconditions

`$MGMT` works; for the node check, a shell on the host.

## Steps

Nothing has to be done for the automatic rows. For the others:

1. Run the management playbook at least every six months (it rewrites
   `mgmt.kubeconfig`) and re-export every workload kubeconfig kept outside
   Terraform.
2. Rotate the CAPN identity before `capn_identity_validity_days` run out.

## Verify

```bash
kubectl --kubeconfig $MGMT -n $NS get kcp \
  -o custom-columns=NAME:.metadata.name,EXPIRY-DAYS:.spec.rollout.before.certificatesExpiryDays,VALIDITY:.spec.kubeadmConfigSpec.clusterConfiguration.certificateValidityPeriodDays
kubectl --kubeconfig $MGMT -n $NS get machines -l cluster.x-k8s.io/control-plane \
  -o custom-columns=NAME:.metadata.name,EXPIRES:.status.certificatesExpiryDate
lxc exec --project $PROJECT <control-plane node> -- kubeadm certs check-expiration   # host
kubectl --kubeconfig $MGMT -n $NS get secret <cluster>-kubeconfig -o jsonpath='{.data.value}' \
  | base64 -d | grep client-certificate-data | awk '{print $2}' | base64 -d | openssl x509 -noout -enddate
lxc config trust list --format csv                                                  # host
```

Every Kubeadm Control Plane shows 60 and 1095; each control-plane machine an
expiry date about three years after it was created; the kubeconfig's client
certificate and the CAPN trust entry their end dates.

## Rollback

Not applicable.

## Tested

2026-11-16, harness, read on both clusters: both Kubeadm Control Planes carry
60 / 1095; `kubeadm certs check-expiration` on a `lab-default` control-plane
node showed every certificate expiring 2029-11-15 (1095 days) and the CAs
2036-11-13; the admin kubeconfig's client certificate ended 2027-11-16 (one
year); the CAPN certificate 2031-11-15; a `mgmt-1` control-plane Machine's
`status.certificatesExpiryDate` read 2029-11-15. The rollout before expiry itself was
not exercised: it needs a clock 2.8 years ahead.
