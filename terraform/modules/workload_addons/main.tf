# The workload side of a workload cluster: Calico and MetalLB, each an upstream
# release followed by its configuration release, through the root's `helm`
# provider (the workload cluster; modules/access builds its connection). Each
# configuration release has a `helm test` gate. Between the two, the Cluster
# chart's own test waits on the management cluster until Cluster API has
# converged. Gates re-run when their releases change (revision) and when the
# Cluster or its ClusterClass changes (generation).

locals {
  charts        = "${path.module}/../../../charts"
  chart_version = { for c in ["cni-calico", "cni-calico-config", "metallb", "metallb-config"] : c => yamldecode(file("${local.charts}/${c}/Chart.yaml")).version }

  # Puts the workload kubeconfig into a private temporary file for the command.
  with_kubeconfig = <<-EOT
    set -euo pipefail
    KUBECONFIG=$(mktemp -t k8s-lab-kubeconfig.XXXXXX)
    export KUBECONFIG
    trap 'rm -f "$KUBECONFIG"' EXIT
    printf '%s' "$WORKLOAD_KUBECONFIG" >"$KUBECONFIG"
  EOT
  gate            = "${local.with_kubeconfig}helm test \"$RELEASE\" --namespace \"$NAMESPACE\" --timeout \"$TIMEOUT\" --logs"
  # Terraform hides a command's output when its configuration holds a sensitive
  # value; the environment is neither printed nor stored.
  environment = { WORKLOAD_KUBECONFIG = nonsensitive(var.kubeconfig), TIMEOUT = var.helm_test_timeout }
}

resource "helm_release" "cni_calico" {
  name              = "cni-calico"
  chart             = "${local.charts}/cni-calico"
  version           = local.chart_version["cni-calico"]
  namespace         = "tigera-operator"
  create_namespace  = true
  dependency_update = true
  atomic            = true
  timeout           = 900
}

# The operator has no readiness probe: it is Available before it has created
# the CRDs the configuration release needs.
resource "terraform_data" "calico_crds" {
  triggers_replace = helm_release.cni_calico.metadata.revision

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = local.environment
    # `wait --for=create` waits only when given a single object.
    command = <<-EOT
      ${local.with_kubeconfig}
      for crd in installations.operator.tigera.io apiservers.operator.tigera.io; do
        kubectl wait --for=create --timeout=300s "crd/$crd"
        kubectl wait --for=condition=Established --timeout=120s "crd/$crd"
      done
    EOT
  }
}

resource "helm_release" "cni_calico_config" {
  name      = "cni-calico-config"
  chart     = "${local.charts}/cni-calico-config"
  version   = local.chart_version["cni-calico-config"]
  namespace = helm_release.cni_calico.namespace
  atomic    = true
  timeout   = 900
  values    = [yamlencode({ calico = { pods = { cidrBlocks = var.cluster.pod_cidrs } } })]

  depends_on = [terraform_data.calico_crds]
}

# Cluster API has converged on the Cluster's last change: no gate may run while
# machines roll or scale. Needs the CNI: nodes are not Ready before.
resource "terraform_data" "cluster_converged" {
  triggers_replace = var.cluster.generation

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      RELEASE         = var.cluster.name
      NAMESPACE       = var.cluster.namespace
      MGMT_KUBECONFIG = var.mgmt_kubeconfig_path
      TIMEOUT         = var.helm_test_timeout
    }
    command = "helm test \"$RELEASE\" --namespace \"$NAMESPACE\" --kubeconfig \"$MGMT_KUBECONFIG\" --timeout \"$TIMEOUT\" --logs"
  }

  depends_on = [helm_release.cni_calico_config]
}

# Gate B.
resource "terraform_data" "gate_cni" {
  triggers_replace = [helm_release.cni_calico.metadata.revision, helm_release.cni_calico_config.metadata.revision, var.cluster.generation]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = merge(local.environment, { RELEASE = helm_release.cni_calico_config.name, NAMESPACE = helm_release.cni_calico_config.namespace })
    command     = local.gate
  }

  depends_on = [terraform_data.cluster_converged]
}

# The controller and the speakers need pod networking.
resource "helm_release" "metallb" {
  name              = "metallb"
  chart             = "${local.charts}/metallb"
  version           = local.chart_version["metallb"]
  namespace         = "metallb-system"
  create_namespace  = true
  dependency_update = true
  atomic            = true
  timeout           = 600

  depends_on = [terraform_data.gate_cni]
}

# The controller is Ready, and its CA is in the webhook configuration, before
# the webhook serves: the serving certificate reaches the Pod through a mounted
# Secret the kubelet refreshes later. Only an admission call proves it serves:
# a server-side dry run calls the webhook and stores nothing. Any answer from
# the webhook, a rejection included, is enough.
resource "terraform_data" "metallb_webhook" {
  triggers_replace = helm_release.metallb.metadata.revision

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = local.environment
    command     = <<-EOT
      ${local.with_kubeconfig}
      probe='{"apiVersion":"metallb.io/v1beta1","kind":"IPAddressPool","metadata":{"name":"k8s-lab-webhook-probe","namespace":"${helm_release.metallb.namespace}"},"spec":{"addresses":["2001:db8:ffff:ffff::/128"],"autoAssign":false}}'
      for _ in $(seq 60); do
        if out=$(printf '%s' "$probe" | kubectl create --dry-run=server -f - 2>&1) || [[ $out == *"denied the request"* ]]; then
          exit 0
        fi
        sleep 5
      done
      echo "the MetalLB webhook did not answer within 300 s: $out" >&2
      exit 1
    EOT
  }
}

# Its CRs need the CRDs of the metallb release, and Helm validates a release's
# objects before it applies any: two releases.
resource "helm_release" "metallb_config" {
  name      = "metallb-config"
  chart     = "${local.charts}/metallb-config"
  version   = local.chart_version["metallb-config"]
  namespace = helm_release.metallb.namespace
  atomic    = true
  timeout   = 600
  values    = [yamlencode(var.metallb)]

  depends_on = [terraform_data.metallb_webhook]
}

# Gate A.
resource "terraform_data" "gate_metallb" {
  triggers_replace = [helm_release.metallb.metadata.revision, helm_release.metallb_config.metadata.revision, var.cluster.generation]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = merge(local.environment, { RELEASE = helm_release.metallb_config.name, NAMESPACE = helm_release.metallb_config.namespace })
    command     = local.gate
  }
}
