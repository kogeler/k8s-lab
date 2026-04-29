# k8s-lab — local developer Makefile.
#
# Scope contract (plan §13):
#   * only local workflows live here;
#   * no `deploy TARGET=...` / `destroy TARGET=...` for real sites —
#     those belong in private consumer repos.
#
# Targets delegate to tests/molecule/Makefile for scenario runs and to
# tests/vagrant/debian13 for the shared local VM lifecycle.

SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
MAKEFLAGS += --no-print-directory

REPO_ROOT     := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ANSIBLE_DIR   := $(REPO_ROOT)/ansible
MOLECULE_DIR  := $(REPO_ROOT)/tests/molecule
VAGRANT_DIR   := $(REPO_ROOT)/tests/vagrant/debian13
TF_FIXTURES   := $(REPO_ROOT)/tests/fixtures/terraform

# Project-local Ansible collection store (gitignored). Every invocation —
# from any subdirectory — resolves collections through this absolute path.
ANSIBLE_COLLECTIONS_DIR := $(ANSIBLE_DIR)/collections
export ANSIBLE_COLLECTIONS_PATH := $(ANSIBLE_COLLECTIONS_DIR)

# Python-side tooling (ansible, ansible-lint, molecule, yamllint) is
# expected to come from a Python virtualenv that the caller has already
# activated (`source <venv>/bin/activate`). We don't hardcode the venv
# location — the caller owns it.
ANSIBLE        ?= ansible
ANSIBLE_PLAY   ?= ansible-playbook
ANSIBLE_GALAXY ?= ansible-galaxy
ANSIBLE_LINT   ?= ansible-lint
YAMLLINT       ?= yamllint
MOLECULE       ?= molecule
# Non-Python tools are expected to be on the system PATH.
TERRAFORM      ?= terraform
TFLINT         ?= tflint
HELM           ?= helm
VAGRANT        ?= vagrant

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_.-]+:.*##/ {printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# --------------------------------------------------------------------------
# Linting
# --------------------------------------------------------------------------

.PHONY: lint
lint: lint-yaml lint-ansible lint-terraform lint-helm ## Run all static checks

.PHONY: lint-yaml
lint-yaml: ## yamllint across repo
	cd $(REPO_ROOT) && $(YAMLLINT) -c .yamllint .

.PHONY: lint-ansible
lint-ansible: ## ansible-lint across roles
	cd $(ANSIBLE_DIR) && $(ANSIBLE_LINT) roles/

.PHONY: lint-terraform
lint-terraform: ## terraform fmt -check + validate on modules and fixtures
	find $(REPO_ROOT)/terraform $(TF_FIXTURES) -type d \( -name '.terraform' -prune \) -o -name '*.tf' -print0 \
		| xargs -0 -I{} dirname {} | sort -u | while read d; do \
			echo "== terraform fmt -check $$d" ; \
			$(TERRAFORM) -chdir=$$d fmt -check -recursive ; \
		done

.PHONY: lint-helm
lint-helm: ## helm lint for all local wrapper charts
	for chart in $(REPO_ROOT)/charts/*/ ; do \
		[ -f "$$chart/Chart.yaml" ] || continue ; \
		$(HELM) lint "$$chart" ; \
	done

# --------------------------------------------------------------------------
# Local harness lifecycle
# --------------------------------------------------------------------------

.PHONY: test-local-harness
test-local-harness: ## Bring up / verify the shared Vagrant VM and mocked networks
	$(MAKE) -C $(VAGRANT_DIR) up
	$(MAKE) -C $(MOLECULE_DIR) harness-smoke

.PHONY: test-local-e2e
test-local-e2e: ## Full local pipeline (plan §13.2); may take significant time
	$(MAKE) -C $(VAGRANT_DIR) up
	$(MAKE) -C $(MOLECULE_DIR) e2e-local-vagrant-converge
	$(MAKE) -C $(MOLECULE_DIR) e2e-local-vagrant-verify

# --------------------------------------------------------------------------
# Phase 5 — workload cluster (PLAN §16.6)
# --------------------------------------------------------------------------
#
# Deploys the workload cluster end-to-end via the single Terraform module
# `terraform/modules/workload_cluster` invoked from the test fixture
# `tests/fixtures/terraform/workload-clusters/lab-default/`. The module
# reads `.artifacts/bootstrap.auto.tfvars.json` (emitted by Phase 4
# export_artifacts) — threaded explicitly via -var-file because Terraform
# auto-loads *.auto.tfvars.json only from cwd, not from the repo-root
# .artifacts/ where Phase 4 deposits the handoff.
#
# Runner deps: terraform, helm, kubectl on PATH (no Python venv needed
# for these targets).

WORKLOAD_TF_DIR  := $(TF_FIXTURES)/workload-clusters/lab-default
BOOTSTRAP_TFVARS := $(REPO_ROOT)/.artifacts/bootstrap.auto.tfvars.json
ARTIFACTS_DIR    := $(REPO_ROOT)/.artifacts

.PHONY: deploy-workload
deploy-workload: ## Phase 5 — terraform apply workload cluster (CAPI + CNI + MetalLB + helm tests)
	@test -f $(BOOTSTRAP_TFVARS) \
	  || { echo "ERROR: $(BOOTSTRAP_TFVARS) missing — run Phase 4 first (make test-local-e2e)"; exit 1; }
	cd $(WORKLOAD_TF_DIR) \
	  && $(TERRAFORM) init -upgrade \
	  && $(TERRAFORM) apply -auto-approve -var-file=$(BOOTSTRAP_TFVARS)

.PHONY: workload-kubeconfig
workload-kubeconfig: ## Materialise rewritten workload kubeconfig to .artifacts/clusters/<cluster>.kubeconfig
	@mkdir -p $(ARTIFACTS_DIR)/clusters
	@cd $(WORKLOAD_TF_DIR) \
	  && cluster_name="$$($(TERRAFORM) output -raw cluster_name)" \
	  && out="$(ARTIFACTS_DIR)/clusters/$${cluster_name}.kubeconfig" \
	  && umask 077 \
	  && $(TERRAFORM) output -raw kubeconfig >"$$out" \
	  && echo "wrote $$out"

# --------------------------------------------------------------------------
# Phase 6 — pivot bootstrap → self-hosted mgmt (PLAN §18)
# --------------------------------------------------------------------------
#
# Two-stage flow stitched into a single Make target:
#
#   1. terraform apply on `tests/fixtures/terraform/management-clusters/mgmt-1/`
#      stands up the target mgmt cluster on the bootstrap k3s — same
#      generic workload_cluster module the workload fixture uses, just
#      with mgmt-cluster topology values (distinct ClusterClass prefix,
#      isolated MetalLB VIP range; topology counts come from §8 globals).
#
#   2. tests/fixtures/ansible/pivot_clusterctl_move/playbook.yml runs
#      `pivot_clusterctl_move` (clusterctl init on target + clusterctl
#      move bootstrap → target) followed by `cleanup_bootstrap` (delete
#      the bootstrap LXC). The role's own healthchecks re-assert the
#      post-pivot end state, so no separate Molecule scenario is needed.
#
# Runner deps: terraform + helm + kubectl on PATH (TF stage), and the
# project venv on PATH (ansible stage — same venv that drives Molecule).
# K8SLAB_HOST_* env vars are populated inline below from
# `vagrant ssh-config host` output (one awk pass) — same wiring
# `scripts/molecule_run.py` does for Molecule scenarios, but the
# adhoc playbook does not need Molecule's VM-identity tracking, so a
# Python wrapper would be unnecessary indirection here.

MGMT_TF_DIR     := $(TF_FIXTURES)/management-clusters/mgmt-1
PIVOT_FIXTURE   := $(REPO_ROOT)/tests/fixtures/ansible/pivot_clusterctl_move
SHARED_INV_DIR  := $(MOLECULE_DIR)/shared/inventory

.PHONY: deploy-pivot
deploy-pivot: ## Phase 6 — terraform apply mgmt-1 + run pivot_clusterctl_move + cleanup_bootstrap
	@test -f $(BOOTSTRAP_TFVARS) \
	  || { echo "ERROR: $(BOOTSTRAP_TFVARS) missing — run Phase 4 first (make test-local-e2e)"; exit 1; }
	@echo "== Phase 6 stage 0/2: ensure Vagrant VM is up"
	$(MAKE) -C $(VAGRANT_DIR) up
	@echo "== Phase 6 stage 1/2: terraform apply mgmt-1"
	cd $(MGMT_TF_DIR) \
	  && $(TERRAFORM) init -upgrade \
	  && $(TERRAFORM) apply -auto-approve -var-file=$(BOOTSTRAP_TFVARS)
	@echo "== Phase 6 stage 2/2: ansible-playbook pivot"
	@# `vagrant ssh-config host` parsed once into K8SLAB_HOST_* — same
	@# 4 keys `scripts/molecule_run.py` exports for Molecule. awk emits
	@# `key=value` lines that `eval` consumes in the current shell.
	cd $(VAGRANT_DIR) \
	  && eval "$$($(VAGRANT) ssh-config host \
	       | awk '/^[[:space:]]*HostName/{print "K8SLAB_HOST_ADDR="$$2} \
	              /^[[:space:]]*User /{print "K8SLAB_HOST_USER="$$2} \
	              /^[[:space:]]*Port /{print "K8SLAB_HOST_PORT="$$2} \
	              /^[[:space:]]*IdentityFile/{print "K8SLAB_HOST_KEY="$$2}')" \
	  && cd $(REPO_ROOT) \
	  && K8SLAB_HOST_ADDR=$$K8SLAB_HOST_ADDR \
	     K8SLAB_HOST_USER=$$K8SLAB_HOST_USER \
	     K8SLAB_HOST_PORT=$$K8SLAB_HOST_PORT \
	     K8SLAB_HOST_KEY=$$K8SLAB_HOST_KEY \
	     ANSIBLE_ROLES_PATH=$(ANSIBLE_DIR)/roles \
	     ANSIBLE_COLLECTIONS_PATH=$(ANSIBLE_COLLECTIONS_DIR) \
	     $(ANSIBLE_PLAY) \
	       -i $(PIVOT_FIXTURE)/hosts.yml \
	       -i $(SHARED_INV_DIR) \
	       $(PIVOT_FIXTURE)/playbook.yml

.PHONY: mgmt-kubeconfig
mgmt-kubeconfig: ## Materialise mgmt kubeconfig to .artifacts/clusters/mgmt-1.kubeconfig (consumer of post-pivot deploy-workload)
	@mkdir -p $(ARTIFACTS_DIR)/clusters
	@cd $(MGMT_TF_DIR) \
	  && cluster_name="$$($(TERRAFORM) output -raw cluster_name)" \
	  && out="$(ARTIFACTS_DIR)/clusters/$${cluster_name}.kubeconfig" \
	  && umask 077 \
	  && $(TERRAFORM) output -raw kubeconfig >"$$out" \
	  && echo "wrote $$out"

# --------------------------------------------------------------------------
# Destroy / clean graph (PLAN §19.2)
# --------------------------------------------------------------------------
#
# Naming convention:
#   destroy-*  operates on running infra (TF state, helm releases, VM,
#              libvirt domains). Each destroy auto-cascades the clean-*
#              targets that the destruction itself makes stale, so the
#              operator never has to remember which files to wipe
#              afterwards. After any destroy-*, the corresponding next-
#              cycle command (deploy-workload, vagrant up, …) just works.
#
#   clean-*    file/directory deletes only. Idempotent against absent
#              state (run safely with no infra at all).
#
#   compound   `clean-local` = "I want to start over fast" (destroys VM,
#              cleans every artefact). `reset-all` = "exercise the full
#              destroy chain end-to-end" (TF destroy on the live workload
#              first, then VM destroy + cleans).

# ---- DESTROY ----------------------------------------------------------------

.PHONY: destroy-workload
destroy-workload: ## Phase 5 reverse — terraform destroy + cascade clean-{tfstate,workload-kubeconfig}
	@# Subshell-wrap cd so it does not leak into the next recipe line under .ONESHELL.
	@if [ -f $(WORKLOAD_TF_DIR)/terraform.tfstate ] && [ -f $(BOOTSTRAP_TFVARS) ]; then \
	  echo "== terraform destroy on workload fixture" ; \
	  ( cd $(WORKLOAD_TF_DIR) && $(TERRAFORM) destroy -auto-approve -var-file=$(BOOTSTRAP_TFVARS) ) ; \
	else \
	  echo "== skip terraform destroy: no tfstate or no bootstrap.auto.tfvars.json" ; \
	fi
	@$(MAKE) clean-tfstate clean-workload-kubeconfig

.PHONY: destroy-pivot
destroy-pivot: ## Phase 6 reverse — terraform destroy on mgmt-1 fixture + cascade clean-{pivot-tfstate,mgmt-kubeconfig}
	@if [ -f $(MGMT_TF_DIR)/terraform.tfstate ] && [ -f $(BOOTSTRAP_TFVARS) ]; then \
	  echo "== terraform destroy on mgmt-1 fixture" ; \
	  ( cd $(MGMT_TF_DIR) && $(TERRAFORM) destroy -auto-approve -var-file=$(BOOTSTRAP_TFVARS) ) ; \
	else \
	  echo "== skip terraform destroy: no tfstate or no bootstrap.auto.tfvars.json" ; \
	fi
	@$(MAKE) clean-pivot-tfstate clean-mgmt-kubeconfig

.PHONY: destroy-vm
destroy-vm: ## Destroy local Vagrant VM + libvirt orphans; cascades clean-{bootstrap-bundle,workload-kubeconfig,mgmt-kubeconfig,tfstate,pivot-tfstate}
	$(MAKE) -C $(VAGRANT_DIR) destroy
	@$(MAKE) clean-bootstrap-bundle clean-workload-kubeconfig clean-mgmt-kubeconfig clean-tfstate clean-pivot-tfstate

# ---- CLEAN (file-only, idempotent) -----------------------------------------

.PHONY: clean-tfstate
clean-tfstate: ## Wipe local Terraform state in workload fixture (.terraform/, tfstate*, lock files)
	@rm -rf $(WORKLOAD_TF_DIR)/.terraform \
	        $(WORKLOAD_TF_DIR)/.terraform.lock.hcl \
	        $(WORKLOAD_TF_DIR)/terraform.tfstate \
	        $(WORKLOAD_TF_DIR)/terraform.tfstate.backup \
	        $(WORKLOAD_TF_DIR)/.terraform.tfstate.lock.info
	@echo "== cleaned: $(WORKLOAD_TF_DIR) terraform state"

.PHONY: clean-pivot-tfstate
clean-pivot-tfstate: ## Wipe local Terraform state in mgmt-1 fixture (.terraform/, tfstate*, lock files)
	@rm -rf $(MGMT_TF_DIR)/.terraform \
	        $(MGMT_TF_DIR)/.terraform.lock.hcl \
	        $(MGMT_TF_DIR)/terraform.tfstate \
	        $(MGMT_TF_DIR)/terraform.tfstate.backup \
	        $(MGMT_TF_DIR)/.terraform.tfstate.lock.info
	@echo "== cleaned: $(MGMT_TF_DIR) terraform state"

.PHONY: clean-bootstrap-bundle
clean-bootstrap-bundle: ## Remove .artifacts/bootstrap.{kubeconfig,auto.tfvars.json} + harness-vm-id
	@rm -f $(ARTIFACTS_DIR)/bootstrap.kubeconfig \
	       $(ARTIFACTS_DIR)/bootstrap.auto.tfvars.json \
	       $(ARTIFACTS_DIR)/harness-vm-id
	@echo "== cleaned: bootstrap handoff bundle"

.PHONY: clean-workload-kubeconfig
clean-workload-kubeconfig: ## Remove .artifacts/clusters/<workload>.kubeconfig (stale workload kubeconfigs)
	@find $(ARTIFACTS_DIR)/clusters -mindepth 1 -name '*.kubeconfig' \
	      ! -name 'mgmt-*.kubeconfig' -delete 2>/dev/null || true
	@echo "== cleaned: workload kubeconfigs in $(ARTIFACTS_DIR)/clusters/"

.PHONY: clean-mgmt-kubeconfig
clean-mgmt-kubeconfig: ## Remove .artifacts/clusters/mgmt-*.kubeconfig (stale mgmt kubeconfigs)
	@find $(ARTIFACTS_DIR)/clusters -mindepth 1 -name 'mgmt-*.kubeconfig' -delete 2>/dev/null || true
	@echo "== cleaned: mgmt kubeconfigs in $(ARTIFACTS_DIR)/clusters/"

.PHONY: clean-molecule
clean-molecule: ## Remove ~/.ansible/tmp/molecule.* scratch directories
	@find $$HOME/.ansible/tmp -maxdepth 1 -type d -name 'molecule.*' -exec rm -rf {} + 2>/dev/null || true
	@echo "== cleaned: ~/.ansible/tmp/molecule.*"

# ---- COMPOUND ---------------------------------------------------------------

.PHONY: clean-local
clean-local: ## "Start over" — destroys VM and cascades every clean-*. Fast; does NOT exercise terraform destroy on the live workload.
	@$(MAKE) destroy-vm
	@$(MAKE) clean-molecule
	@echo "== local harness reset complete"

.PHONY: reset-all
reset-all: ## Full PLAN §19.2 reverse — terraform destroy on live workload + pivot mgmt, THEN destroy-vm + clean-molecule. Slow; exercises every destroy step.
	@$(MAKE) destroy-workload
	@$(MAKE) destroy-pivot
	@$(MAKE) destroy-vm
	@$(MAKE) clean-molecule
	@echo "== full destroy chain complete"

# --------------------------------------------------------------------------
# Convenience
# --------------------------------------------------------------------------

.PHONY: deps
deps: ## Install Ansible collections into ansible/collections (project-local)
	# --force makes the install authoritative for the project tree — without
	# it ansible-galaxy happily "skips" anything already present in venv's
	# bundled site-packages, leaving holes in our local collections path.
	$(ANSIBLE_GALAXY) collection install --force \
		-r $(ANSIBLE_DIR)/requirements.yml \
		-p $(ANSIBLE_COLLECTIONS_DIR)

.PHONY: tree
tree: ## Print top-level repo layout (best effort)
	@command -v tree >/dev/null && tree -L 2 -I '.git|.terraform|.molecule|.vagrant|.artifacts' $(REPO_ROOT) || ls -la $(REPO_ROOT)
