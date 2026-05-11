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
# reads `.artifacts/mgmt.auto.tfvars.json` (emitted by Phase 4
# export_artifacts) — threaded explicitly via -var-file because Terraform
# auto-loads *.auto.tfvars.json only from cwd, not from the repo-root
# .artifacts/ where Phase 4 deposits the handoff.
#
# Runner deps: terraform, helm, kubectl on PATH (no Python venv needed
# for these targets).

WORKLOAD_TF_DIR := $(TF_FIXTURES)/workload-clusters/lab-default
MGMT_TFVARS     := $(REPO_ROOT)/.artifacts/mgmt.auto.tfvars.json
ARTIFACTS_DIR   := $(REPO_ROOT)/.artifacts

.PHONY: deploy-workload
deploy-workload: ## Terraform apply workload cluster on existing mgmt (CAPI + CNI + MetalLB + helm tests)
	@test -f $(MGMT_TFVARS) \
	  || { echo "ERROR: $(MGMT_TFVARS) missing — run Phase 4 first (make test-local-e2e)"; exit 1; }
	cd $(WORKLOAD_TF_DIR) \
	  && $(TERRAFORM) init -upgrade \
	  && $(TERRAFORM) apply -auto-approve -var-file=$(MGMT_TFVARS)

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
destroy-workload: ## Destroy workload — TF destroy if tfstate exists, helm uninstall fallback against .artifacts/mgmt.kubeconfig otherwise + cascade clean-{tfstate,workload-kubeconfig}
	@# Three branches:
	@#   (1) TF state present  → reverse the same TF route used to deploy;
	@#   (2) no TF state but mgmt.kubeconfig + tfvars present → workload was
	@#       installed via Molecule e2e-local converge (kubernetes.core.helm
	@#       direct, no TF state). helm uninstall the two top-level releases
	@#       in reverse-order (workload Cluster CR first → CAPI cascade-deletes
	@#       Machines + LXC instances; then per-cluster ClusterClass);
	@#       cni-calico / metallb / metallb-config live INSIDE the workload
	@#       cluster and disappear with it — no separate uninstall needed;
	@#   (3) neither: no infra to destroy, just clean stale files.
	@if [ -f $(WORKLOAD_TF_DIR)/terraform.tfstate ] && [ -f $(MGMT_TFVARS) ]; then \
	  echo "== terraform destroy on workload fixture" ; \
	  ( cd $(WORKLOAD_TF_DIR) && $(TERRAFORM) destroy -auto-approve -var-file=$(MGMT_TFVARS) ) ; \
	elif [ -f $(ARTIFACTS_DIR)/mgmt.kubeconfig ] && [ -f $(MGMT_TFVARS) ]; then \
	  cluster_name=$$(jq -r '.k8s_lab_workload_cluster_name // "lab-default"' $(MGMT_TFVARS)) ; \
	  echo "== no TF state — helm-uninstall fallback for workload '$$cluster_name' on .artifacts/mgmt.kubeconfig" ; \
	  $(HELM) uninstall "$$cluster_name" -n capi-clusters --kubeconfig $(ARTIFACTS_DIR)/mgmt.kubeconfig --wait --timeout 15m 2>&1 || true ; \
	  $(HELM) uninstall "$$cluster_name-class" -n capi-clusters --kubeconfig $(ARTIFACTS_DIR)/mgmt.kubeconfig --wait --timeout 5m 2>&1 || true ; \
	else \
	  echo "== skip destroy: neither TF tfstate nor .artifacts/mgmt.kubeconfig present" ; \
	fi
	@$(MAKE) clean-tfstate clean-workload-kubeconfig

.PHONY: destroy-vm
destroy-vm: ## Destroy local Vagrant VM + libvirt orphans; cascades clean-{mgmt-bundle,workload-kubeconfig,tfstate}
	$(MAKE) -C $(VAGRANT_DIR) destroy
	@$(MAKE) clean-mgmt-bundle clean-workload-kubeconfig clean-tfstate

# ---- CLEAN (file-only, idempotent) -----------------------------------------

.PHONY: clean-tfstate
clean-tfstate: ## Wipe local Terraform state in workload fixture (.terraform/, tfstate*, lock files)
	@rm -rf $(WORKLOAD_TF_DIR)/.terraform \
	        $(WORKLOAD_TF_DIR)/.terraform.lock.hcl \
	        $(WORKLOAD_TF_DIR)/terraform.tfstate \
	        $(WORKLOAD_TF_DIR)/terraform.tfstate.backup \
	        $(WORKLOAD_TF_DIR)/.terraform.tfstate.lock.info
	@echo "== cleaned: $(WORKLOAD_TF_DIR) terraform state"

.PHONY: clean-mgmt-bundle
clean-mgmt-bundle: ## Remove .artifacts/mgmt.{kubeconfig,auto.tfvars.json} + harness-vm-id
	@rm -f $(ARTIFACTS_DIR)/mgmt.kubeconfig \
	       $(ARTIFACTS_DIR)/mgmt.auto.tfvars.json \
	       $(ARTIFACTS_DIR)/harness-vm-id
	@echo "== cleaned: mgmt handoff bundle"

.PHONY: clean-workload-kubeconfig
clean-workload-kubeconfig: ## Remove .artifacts/clusters/*.kubeconfig (stale per-workload debug copies from Molecule e2e-local)
	@find $(ARTIFACTS_DIR)/clusters -mindepth 1 -name '*.kubeconfig' -delete 2>/dev/null || true
	@echo "== cleaned: per-cluster debug kubeconfigs in $(ARTIFACTS_DIR)/clusters/"

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
reset-all: ## Full PLAN §19.2 reverse — terraform destroy on live workload, THEN destroy-vm + clean-molecule. Slow; exercises every destroy step.
	@$(MAKE) destroy-workload
	@$(MAKE) destroy-vm
	@$(MAKE) clean-molecule
	@echo "== full destroy chain complete"

# --------------------------------------------------------------------------
# Convenience
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------
# Documentation bundle for LLM crawlers
# --------------------------------------------------------------------------
#
# `make docs-llm` regenerates llms-full.txt by concatenating every chapter
# under doc/ in reading order (README first, then 01..14). The bundle is
# committed so it is fetchable as a single file at the canonical GitHub raw
# URL — the llms.txt convention assumes a flat, single-URL "everything"
# pointer for LLM ingestion.

.PHONY: docs-llm
docs-llm: ## Regenerate llms-full.txt from doc/*.md in reading order
	@( \
	  echo "# k8s-lab — full documentation snapshot" ; \
	  echo "" ; \
	  echo "> Concatenated bundle of every chapter under doc/, in reading order." ; \
	  echo "> Regenerate with 'make docs-llm'. Canonical source: https://github.com/kogeler/k8s-lab" ; \
	  echo "" ; \
	  for f in $(REPO_ROOT)/doc/README.md $$(ls $(REPO_ROOT)/doc/[0-9][0-9]-*.md | sort) ; do \
	    rel=$${f#$(REPO_ROOT)/} ; \
	    echo "" ; \
	    echo "---" ; \
	    echo "" ; \
	    echo "<!-- source: $$rel -->" ; \
	    echo "" ; \
	    cat "$$f" ; \
	    echo "" ; \
	  done \
	) > $(REPO_ROOT)/llms-full.txt
	@lines=$$(wc -l < $(REPO_ROOT)/llms-full.txt) ; \
	 bytes=$$(wc -c < $(REPO_ROOT)/llms-full.txt) ; \
	 echo "== wrote llms-full.txt ($$lines lines, $$bytes bytes)"

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
