locals {
  # ClusterClass namespace defaults to cluster_namespace so each
  # workload's class is self-contained (multi-workload isolation —
  # bumping KCPT in one workload does not rotate names in another).
  cluster_class_namespace = var.cluster_class_namespace != "" ? var.cluster_class_namespace : var.cluster_namespace

  # Reproduces the chart-side slug formula
  # (capi-cluster-class.classFullName helper): dots in chart version
  # → "-", lowercased, DNS-1123 subdomain safe. The workload-cluster
  # chart computes the same slug from its Chart.yaml annotation and
  # references it as spec.topology.classRef.name; this local is only
  # used for the Terraform output so consumers can introspect.
  cluster_class_version_slug = lower(replace(var.cluster_class_chart_version, ".", "-"))
  cluster_class_full_name    = substr("${var.class_prefix}-${local.cluster_class_version_slug}", 0, 63)

  # ---- ClusterClass chart values ------------------------------------------
  cluster_class_values = {
    clusterClass = {
      name = var.class_prefix
    }
    kubernetes = {
      version = var.kubernetes_version
    }
    capn = {
      infrastructureSecretName = var.infrastructure_secret_name
    }
    images = {
      controlplane = {
        ref         = var.image_controlplane_ref
        fingerprint = var.image_controlplane_fingerprint
      }
      worker = {
        ref         = var.image_worker_ref
        fingerprint = var.image_worker_fingerprint
      }
    }
    loadBalancer = var.load_balancer
    profilesExtra = {
      controlplane = var.controlplane_profiles_extra
      worker       = var.worker_profiles_extra
    }
    devicesExtra = {
      controlplane = var.controlplane_devices_extra
      worker       = var.worker_devices_extra
    }
    controlPlane = {
      featureGates               = var.control_plane_tuning.feature_gates
      apiServerExtraArgs         = var.control_plane_tuning.api_server_extra_args
      controllerManagerExtraArgs = var.control_plane_tuning.controller_manager_extra_args
      schedulerExtraArgs         = var.control_plane_tuning.scheduler_extra_args
      kubeletExtraArgs           = var.control_plane_tuning.kubelet_extra_args
      preKubeadmCommands         = var.control_plane_tuning.pre_kubeadm_commands
      postKubeadmCommands        = var.control_plane_tuning.post_kubeadm_commands
    }
    worker = {
      featureGates        = var.worker_tuning.feature_gates
      kubeletExtraArgs    = var.worker_tuning.kubelet_extra_args
      preKubeadmCommands  = var.worker_tuning.pre_kubeadm_commands
      postKubeadmCommands = var.worker_tuning.post_kubeadm_commands
    }
    kubeProxy = {
      nodePortAddresses = var.kube_proxy_node_port_addresses
    }
  }

  # ---- Workload Cluster chart values --------------------------------------
  workload_cluster_values = {
    cluster = {
      name = var.cluster_name
    }
    clusterClass = {
      name      = var.class_prefix
      namespace = local.cluster_class_namespace == var.cluster_namespace ? "" : local.cluster_class_namespace
    }
    kubernetes = {
      version = var.kubernetes_version
    }
    topology = {
      controlPlane = {
        replicas = var.controlplane_count
      }
      workers = {
        replicas = var.worker_count
      }
    }
    clusterNetwork = {
      pods = {
        cidrBlocks = var.pod_cidrs
      }
      services = {
        cidrBlocks = var.service_cidrs
      }
    }
    apiProxy = {
      infrastructureSecretName = var.infrastructure_secret_name
    }
  }

  # ---- Per-Cluster API proxy port -----------------------------------------
  # The chart writes the computed Adler-32 port into the Cluster CR
  # annotation k8s-lab.io/api-proxy-port; we read it back as the
  # single-source-of-truth for the kubeconfig server URL rewrite. The
  # data source is null-safe before helm install completes; after the
  # workload-cluster release is applied, the annotation is always set.
  api_proxy_port = tonumber(
    try(data.kubernetes_resource.workload_cluster_cr.object.metadata.annotations["k8s-lab.io/api-proxy-port"], "0")
  )

  # ---- Workload kubeconfig parsing ----------------------------------------
  # The CAPI-emitted Secret stores the admin kubeconfig as a single
  # base64-blob under data.value (kubeconfig-Type Secret). Decode it,
  # then yamldecode to access cluster/user fields directly — no
  # `kubectl --kubeconfig` shell-out needed for the helm provider config.
  workload_kubeconfig_raw = try(
    base64decode(data.kubernetes_resource.workload_kubeconfig_secret.object.data.value),
    ""
  )
  workload_kc_obj = local.workload_kubeconfig_raw != "" ? yamldecode(local.workload_kubeconfig_raw) : null

  workload_kc_cluster = local.workload_kc_obj != null ? local.workload_kc_obj.clusters[0].cluster : null
  workload_kc_user    = local.workload_kc_obj != null ? local.workload_kc_obj.users[0].user : null

  # Rewritten server URL: replace the internal capi-int IPv6 endpoint
  # with the runner-reachable LXD-host:proxy-port. The substrate-locked
  # tls-server-name (kubernetes.default.svc) is already a SAN on the
  # CAPI-issued apiserver cert, so any TCP-reachable URL works.
  workload_server_url_rewritten = "https://${var.lxd_host_address}:${local.api_proxy_port}"

  # Inline kubeconfig content piped to the workload helm provider.
  # Built from the parsed pieces rather than string-substituted on the
  # raw YAML so we never accidentally rewrite a server URL nested in
  # exec auth-info args, etc.
  workload_kubeconfig_rewritten = local.workload_kc_obj != null ? yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [
      {
        name = local.workload_kc_obj.clusters[0].name
        cluster = merge(
          local.workload_kc_cluster,
          {
            server          = local.workload_server_url_rewritten
            tls-server-name = "kubernetes.default.svc"
          }
        )
      }
    ]
    users = [
      {
        name = local.workload_kc_obj.users[0].name
        user = local.workload_kc_user
      }
    ]
    contexts        = local.workload_kc_obj.contexts
    current-context = local.workload_kc_obj.current-context
    preferences     = try(local.workload_kc_obj.preferences, {})
  }) : ""

  # ---- Helm provider material for the workload cluster --------------------
  # The helm provider's `kubernetes` block accepts host + CA + client
  # cert/key as separate fields. Parsing them here (rather than passing
  # an inline kubeconfig string) avoids requiring kubectl on the runner
  # for the helm provider itself — kubectl is only needed for the
  # one-shot wait-for-Secret loop in the null_resource.
  workload_helm_kubernetes = local.workload_kc_obj != null ? {
    host                   = local.workload_server_url_rewritten
    cluster_ca_certificate = base64decode(local.workload_kc_cluster["certificate-authority-data"])
    client_certificate     = base64decode(local.workload_kc_user["client-certificate-data"])
    client_key             = base64decode(local.workload_kc_user["client-key-data"])
    tls_server_name        = "kubernetes.default.svc"
  } : null

  # ---- cni-calico chart values --------------------------------------------
  cni_calico_values = {
    calico = {
      pods = {
        cidrBlocks = var.pod_cidrs
      }
    }
  }

  # ---- metallb-config chart values ----------------------------------------
  metallb_config_values = {
    pool = {
      rangeV6 = var.metallb_vip_range_v6
    }
    l2 = {
      interface          = var.metallb_interface
      extraNodeSelectors = var.metallb_extra_node_selectors
    }
  }
}
