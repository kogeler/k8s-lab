# PLAN §16.4 — single Terraform module. One `terraform apply` brings up
# the workload cluster end-to-end: ClusterClass + Cluster CR + CNI +
# MetalLB + acceptance helm tests. Fail of any helm test → null_resource
# returns non-zero → TF apply fails → state tainted → next apply retries.
#
# Step 17 (2026-04-28): readiness gating moved out of TF into chart-side
# Helm post-install hook (charts/capi-workload-cluster ≥0.8.0). Hook now
# blocks helm install until LB instance Running + kubeconfig Secret
# present + apiserver /livez=200/401/403; therefore TF no longer needs
# its own wait null_resources or shell scripts. Helm test invocations
# stay inline as heredoc local-exec provisioners.

# ---- (1) Per-workload ClusterClass --------------------------------------
resource "helm_release" "capi_cluster_class" {
  provider = helm.mgmt

  name             = "${var.cluster_name}-class"
  chart            = "${path.module}/../../../charts/capi-cluster-class"
  version          = var.cluster_class_chart_version
  namespace        = local.cluster_class_namespace
  create_namespace = false

  wait          = true
  wait_for_jobs = true
  atomic        = true
  force_update  = false

  values = [yamlencode(local.cluster_class_values)]
}

# ---- (2) Workload Cluster CR + chart-side readiness gates --------------
# The chart's post-install hook (api-proxy-attach Job) runs four gates
# in sequence: LB instance materialised in LXD, kubeconfig Secret
# emitted by KCP, LB Running + proxy device attached, apiserver /livez
# OK. helm install --wait + wait_for_jobs blocks on hook completion,
# so this resource reports `Creation complete` only after the workload
# cluster is fully ready end-to-end.
resource "helm_release" "capi_workload_cluster" {
  provider = helm.mgmt

  name             = var.cluster_name
  chart            = "${path.module}/../../../charts/capi-workload-cluster"
  version          = var.cluster_workload_chart_version
  namespace        = var.cluster_namespace
  create_namespace = false

  wait          = true
  wait_for_jobs = true
  atomic        = true
  force_update  = false
  timeout       = 1500 # 25 min — covers cold-cache CAPN provisioning

  values = [yamlencode(local.workload_cluster_values)]

  depends_on = [helm_release.capi_cluster_class]
}

# ---- (3) Read Cluster CR + kubeconfig Secret (both guaranteed by hook) -
data "kubernetes_resource" "workload_cluster_cr" {
  provider = kubernetes.mgmt

  api_version = "cluster.x-k8s.io/v1beta2"
  kind        = "Cluster"
  metadata {
    name      = var.cluster_name
    namespace = var.cluster_namespace
  }

  depends_on = [helm_release.capi_workload_cluster]
}

data "kubernetes_resource" "workload_kubeconfig_secret" {
  provider = kubernetes.mgmt

  api_version = "v1"
  kind        = "Secret"
  metadata {
    name      = "${var.cluster_name}-kubeconfig"
    namespace = var.cluster_namespace
  }

  depends_on = [helm_release.capi_workload_cluster]
}

# ---- (4) CNI: Calico via local wrapper chart ---------------------------
resource "helm_release" "cni_calico" {
  provider = helm.workload

  name             = "cni-calico"
  chart            = "${path.module}/../../../charts/cni-calico"
  version          = var.cni_calico_chart_version
  namespace        = "tigera-operator"
  create_namespace = true

  wait          = true
  wait_for_jobs = true
  atomic        = true
  force_update  = false
  timeout       = 900

  values = [yamlencode(local.cni_calico_values)]

  depends_on = [data.kubernetes_resource.workload_kubeconfig_secret]
}

# ---- (5) Gate B — Calico in-cluster acceptance --------------------------
resource "null_resource" "helm_test_cni_calico" {
  triggers = {
    chart_version    = var.cni_calico_chart_version
    release_id       = helm_release.cni_calico.id
    workload_kc_hash = sha256(local.workload_kubeconfig_rewritten)
  }

  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]

    # Inline `helm test` driver: write the rewritten workload kubeconfig
    # to a process-private mktemp file, exec helm test, clean up on any
    # exit. Workload kubeconfig material lives only in TF state — never
    # in .artifacts/, never in $HOME — per PLAN §16.4 architectural fence.
    command = <<-EOT
      set -euo pipefail
      kc=$(mktemp -t k8slab-workload-kc.XXXXXXXXXX)
      chmod 0600 "$kc"
      trap 'rm -f "$kc"' EXIT
      printf '%s' "$KUBECONFIG_CONTENT" >"$kc"
      echo "helm_test: $RELEASE_NAMESPACE/$RELEASE (timeout=$HELM_TEST_TIMEOUT)" >&2
      exec helm test "$RELEASE" \
        --kubeconfig "$kc" \
        --namespace  "$RELEASE_NAMESPACE" \
        --timeout    "$HELM_TEST_TIMEOUT" \
        --logs
    EOT

    environment = {
      RELEASE            = helm_release.cni_calico.name
      RELEASE_NAMESPACE  = helm_release.cni_calico.namespace
      KUBECONFIG_CONTENT = local.workload_kubeconfig_rewritten
      HELM_TEST_TIMEOUT  = var.helm_test_timeout
    }
  }
}

# ---- (6) MetalLB upstream subchart wrapper -----------------------------
resource "helm_release" "metallb" {
  provider = helm.workload

  name             = "metallb"
  chart            = "${path.module}/../../../charts/metallb"
  version          = var.metallb_chart_version
  namespace        = "metallb-system"
  create_namespace = true

  wait          = true
  wait_for_jobs = true
  atomic        = true
  force_update  = false
  timeout       = 600

  # MetalLB controller + speaker DS need pod networking up to form
  # memberlist gossip; CNI must be green before the wrapper can start.
  depends_on = [null_resource.helm_test_cni_calico]
}

# ---- (7) MetalLB CRs (IPAddressPool + L2Advertisement + Gate A driver) -
resource "helm_release" "metallb_config" {
  provider = helm.workload

  name             = "metallb-config"
  chart            = "${path.module}/../../../charts/metallb-config"
  version          = var.metallb_config_chart_version
  namespace        = "metallb-system"
  create_namespace = false

  wait          = true
  wait_for_jobs = true
  atomic        = true
  force_update  = false
  timeout       = 600

  values = [yamlencode(local.metallb_config_values)]

  # CRDs ship with charts/metallb (templates/crds/) — must be applied
  # before metallb-config's CRs; cannot be a single release because
  # Helm 3 validates the manifest list before apply (PLAN §17.3 split).
  depends_on = [helm_release.metallb]
}

# ---- (8) Gate A — MetalLB external L2 acceptance -----------------------
resource "null_resource" "helm_test_metallb_config" {
  triggers = {
    chart_version    = var.metallb_config_chart_version
    release_id       = helm_release.metallb_config.id
    workload_kc_hash = sha256(local.workload_kubeconfig_rewritten)
  }

  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]

    command = <<-EOT
      set -euo pipefail
      kc=$(mktemp -t k8slab-workload-kc.XXXXXXXXXX)
      chmod 0600 "$kc"
      trap 'rm -f "$kc"' EXIT
      printf '%s' "$KUBECONFIG_CONTENT" >"$kc"
      echo "helm_test: $RELEASE_NAMESPACE/$RELEASE (timeout=$HELM_TEST_TIMEOUT)" >&2
      exec helm test "$RELEASE" \
        --kubeconfig "$kc" \
        --namespace  "$RELEASE_NAMESPACE" \
        --timeout    "$HELM_TEST_TIMEOUT" \
        --logs
    EOT

    environment = {
      RELEASE            = helm_release.metallb_config.name
      RELEASE_NAMESPACE  = helm_release.metallb_config.namespace
      KUBECONFIG_CONTENT = local.workload_kubeconfig_rewritten
      HELM_TEST_TIMEOUT  = var.helm_test_timeout
    }
  }
}
