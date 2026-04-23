# Molecule wrapper Makefile for k8s-lab.
#
# Contract (plan §9.4):
#   * targets follow the scheme `<scenario>-<driver>-<action>`;
#   * even when a scenario has only one driver, the driver name stays in the
#     target so the invocation scheme is stable across the repo;
#   * driver-specific quirks (ANSIBLE_LIBRARY for vagrant-libvirt, GIT_DIR
#     shim for role layout detection, …) are plumbed explicitly here and
#     not left as folklore.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

HERE          := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT     := $(abspath $(HERE)/../..)

# Python tooling (ansible, molecule, …) is expected to come from an
# already-activated virtualenv on $PATH. Callers should `source
# <venv>/bin/activate` before invoking `make`.
MOLECULE      ?= molecule
ANSIBLE       ?= ansible
ANSIBLE_PLAY  ?= ansible-playbook

# Molecule discovers scenarios via ANSIBLE_COLLECTIONS_PATH / role layout; this
# repo is a plain roles directory, not a collection, so some Molecule versions
# mis-classify it. The shim below forces "role" mode for scenarios that run
# against a single role and avoids git-metadata probing.
export ANSIBLE_ROLES_PATH       := $(REPO_ROOT)/ansible/roles
export ANSIBLE_COLLECTIONS_PATH := $(REPO_ROOT)/ansible/collections
export MOLECULE_NO_LOG          ?= false
# Molecule's default scenario glob is `molecule/*/molecule.yml`, resolved
# relative to CWD. Our scenarios live directly under `tests/molecule/`,
# so we redirect the glob to skip the extra `molecule/` prefix.
export MOLECULE_GLOB            := $(HERE)/*/molecule.yml

# vagrant-libvirt ships its Ansible modules via a Python package; make them
# visible without requiring a global `collection install`. Falls back
# silently if molecule_plugins.vagrant is not importable.
_VAGRANT_PLUGIN_DIR := $(shell python -c 'import os, molecule_plugins.vagrant; print(os.path.dirname(molecule_plugins.vagrant.__file__))' 2>/dev/null)
ifneq ($(_VAGRANT_PLUGIN_DIR),)
export ANSIBLE_LIBRARY := $(_VAGRANT_PLUGIN_DIR)$(if $(ANSIBLE_LIBRARY),:$(ANSIBLE_LIBRARY))
endif

# Scenarios that exist under tests/molecule/. Names are kebab-case so
# that `make <scenario>-<driver>-<action>` reads consistently on the
# command line; the snake_case Ansible role they exercise (e.g.
# `ansible/roles/base_system`) is referenced by each scenario's
# `molecule.yml` via `_shared_target_role`, not by this directory name.
# Keep the list curated — it drives `harness-smoke` and `destroy-all`.
SCENARIOS := \
	base-system \
	binary-fetch \
	lxd-host \
	lxd-project \
	lxd-storage-pools \
	lxd-network-int-managed \
	lxd-profiles \
	lxd-bootstrap-instance \
	bootstrap-k3s \
	bootstrap-clusterctl \
	bootstrap-capn-secret \
	export-artifacts \
	gate-ext-l2 \
	gate-cni \
	bootstrap-cluster \
	cluster-addons-helm \
	pivot \
	e2e-local

# Drivers currently wired in this repo. `delegated` uses the Vagrant VM
# directly; keeping `vagrant` as an alias lets the scheme tolerate future
# drivers without renaming targets.
DRIVERS := delegated vagrant

.PHONY: help
help:
	@echo "Targets follow the scheme <scenario>-<driver>-<action>."
	@echo ""
	@echo "Scenarios: $(SCENARIOS)"
	@echo "Drivers:   $(DRIVERS)"
	@echo "Actions:   create prepare converge idempotence verify test destroy"
	@echo ""
	@echo "Convenience:"
	@echo "  harness-smoke    — quick local smoke (no scenario run)"
	@echo "  destroy-all      — destroy every known scenario"

.PHONY: harness-smoke
harness-smoke:
	@echo "== checking molecule installation"
	@$(MOLECULE) --version
	@echo "== listing scenarios"
	@for s in $(SCENARIOS); do \
		[ -f "$(HERE)/$$s/molecule.yml" ] && echo "  ready: $$s" \
			|| echo "  (missing): $$s" ; \
	done

.PHONY: destroy-all
destroy-all:
	@for s in $(SCENARIOS); do \
		if [ -f "$(HERE)/$$s/molecule.yml" ]; then \
			echo "== molecule destroy $$s" ; \
			$(MAKE) -C $(HERE) $$s-delegated-destroy || true ; \
		fi ; \
	done

# ---- Pattern rule: <scenario>-<driver>-<action> --------------------------
#
# Matches e.g. `base-system-delegated-converge`, `gate-cni-vagrant-verify`.
# `%` captures the scenario name (kebab-case, matches the directory under
# tests/molecule/); the literal `-<driver>-<action>` suffix is what
# disambiguates the target. The driver segment is informational — the
# scenario's molecule.yml is the single source of truth for the driver.
%-delegated-create      %-vagrant-create:        ; $(call _molecule,$*,create)
%-delegated-prepare     %-vagrant-prepare:       ; $(call _molecule,$*,prepare)
%-delegated-converge    %-vagrant-converge:      ; $(call _molecule,$*,converge)
%-delegated-idempotence %-vagrant-idempotence:   ; $(call _molecule,$*,idempotence)
%-delegated-verify      %-vagrant-verify:        ; $(call _molecule,$*,verify)
%-delegated-test        %-vagrant-test:          ; $(call _molecule,$*,test)
%-delegated-destroy     %-vagrant-destroy:       ; $(call _molecule,$*,destroy)
%-delegated-lint        %-vagrant-lint:          ; $(call _molecule,$*,lint)

# Route a molecule action through the Python wrapper that brings the
# Vagrant VM up and exports K8SLAB_HOST_* env vars before exec'ing molecule.
define _molecule
	@$(REPO_ROOT)/scripts/molecule_run.py $1 $2
endef
