name = "lab-default"

# Disjoint from the management cluster's range, so an answer identifies the cluster.
metallb = {
  pool = { rangeV6 = "2001:db8:42:100::300-2001:db8:42:100::3ff" }
}
