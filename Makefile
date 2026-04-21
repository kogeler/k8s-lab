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
	$(MAKE) -C $(MOLECULE_DIR) e2e_local-vagrant-converge
	$(MAKE) -C $(MOLECULE_DIR) e2e_local-vagrant-verify

.PHONY: clean-local
clean-local: ## Destroy local Vagrant VM, Molecule state, ephemeral artifacts
	-$(MAKE) -C $(MOLECULE_DIR) destroy-all
	-$(MAKE) -C $(VAGRANT_DIR) destroy
	rm -rf $(REPO_ROOT)/.artifacts/*
	touch $(REPO_ROOT)/.artifacts/.gitkeep

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
