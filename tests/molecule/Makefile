# Molecule scenarios: `make <scenario>-<action>`, e.g. `substrate-test`,
# `e2e-local-converge`. Each target is a plain `molecule <action> -s
# <scenario>` run from tests/, which is all a scenario needs once the test
# host is up (`make vm-up` at the repository root).
#
#   VARS=alt-vars.yml   apply tests/playbooks/alt-vars.yml on top of the
#                       reference values (every playbook of the scenario)

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

HERE      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TESTS_DIR := $(abspath $(HERE)/..)
REPO_ROOT := $(abspath $(TESTS_DIR)/..)
# Molecule's state per scenario, inside this checkout (Molecule's default is
# keyed on the directory name `tests` and shared with any project that has one).
STATE_DIR := $(REPO_ROOT)/.cache/molecule
MOLECULE  ?= molecule
VARS      ?=

SCENARIOS := substrate bootstrap e2e-local gha
ACTIONS   := prepare converge idempotence verify test destroy
EXTRA     := $(if $(VARS),-- -e @$(TESTS_DIR)/playbooks/$(VARS))

# A target is <scenario>-<action>; scenario names contain dashes, actions do not.
action    = $(lastword $(subst -, ,$1))
scenario  = $(1:%-$(call action,$1)=%)

TARGETS := $(foreach s,$(SCENARIOS),$(addprefix $(s)-,$(ACTIONS)))
.PHONY: help reset $(TARGETS)

help:
	@echo "make <scenario>-<action> [VARS=alt-vars.yml]"
	@echo "  scenarios: $(SCENARIOS)"
	@echo "  actions:   $(ACTIONS)"
	@echo "make reset   forget the Molecule state of this checkout's scenarios"

# The gha scenario changes the machine it runs on (Docker, swap, iptables,
# disks): only inside a GitHub Actions job. Its playbooks assert the same.
# A full `test` starts a new record of the first converge (the e2e verify
# compares the second run with it).
$(TARGETS):
	@if [ "$(call scenario,$@)" = gha ] && [ "$${GITHUB_ACTIONS:-}" != "true" ]; then \
		echo "ERROR: the gha scenario runs only in GitHub Actions; use e2e-local on the local VM." >&2; \
		exit 1; \
	fi
	$(if $(filter test,$(call action,$@)),rm -f $(REPO_ROOT)/.artifacts/e2e-first-run.json)
	cd $(TESTS_DIR) && MOLECULE_EPHEMERAL_DIRECTORY=$(STATE_DIR)/$(call scenario,$@) \
		$(MOLECULE) $(call action,$@) -s $(call scenario,$@) $(EXTRA)

reset:
	rm -rf $(STATE_DIR)
