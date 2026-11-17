# tflint configuration for the three modules and the two fixture roots (`make check`).
config {
  # Each module is linted on its own; evaluating a root's module calls would
  # read the runtime handoff file.
  call_module_type = "none"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
