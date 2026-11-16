name                = "lab-default"
kubernetes_version  = "v1.37.0"
control_plane_count = 3
worker_count        = 2
pod_cidrs           = ["10.244.0.0/16", "fd42:77:2::/56"]
service_cidrs       = ["10.96.0.0/16", "fd42:77:3::/112"]
