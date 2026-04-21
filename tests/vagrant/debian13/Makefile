# Local Vagrant harness for k8s-lab.
#
# Lifecycle contract:
#   make up        — define/start libvirt networks, then `vagrant up` the host VM
#   make destroy   — `vagrant destroy -f`, leave libvirt networks in place
#   make wipe      — destroy + remove libvirt networks (heavy; forces re-define)
#   make ssh       — ssh into the host VM
#   make status    — vagrant status
#
# The libvirt networks are defined imperatively because vagrant-libvirt's
# auto-creation of custom networks is flaky for IPv6-only segments; managing
# them via `virsh net-define` gives reproducible XML-sourced topology.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

HERE          := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
NET_DIR       := $(HERE)/libvirt-networks
VAGRANT       ?= vagrant
# virsh talks to the system libvirtd via the libvirt group socket; the
# runner is expected to be a member of `libvirt`. No sudo — if the call
# fails with permission errors, add the user to that group and re-login.
VIRSH         ?= virsh -c qemu:///system

NETS := k8slab-mgmt-nat k8slab-ext6-mock
ifeq ($(K8SLAB_PROBE),1)
NETS += k8slab-probe-ext6
endif

# Libvirt-side artifacts this Vagrantfile produces. Kept as a single
# variable so `destroy` / `wipe` stay symmetric with `up`.
LIBVIRT_DOMAINS := k8slab_host k8slab_probe
LIBVIRT_VOLUMES := k8slab_host.img k8slab_host-vdb.qcow2 \
                   k8slab_probe.img k8slab_probe-vdb.qcow2
LIBVIRT_POOL    ?= default

.PHONY: up
up: networks
	cd $(HERE) && $(VAGRANT) up --provider=libvirt host
	@if [ "$${K8SLAB_PROBE:-0}" = "1" ]; then \
		cd $(HERE) && $(VAGRANT) up --provider=libvirt probe ; \
	fi

# Molecule scenario state is invalidated automatically on the next molecule
# run by `scripts/molecule_run.py`: it compares the live VM identity at
# `.vagrant/machines/host/libvirt/id` against the tracker written under
# `.artifacts/harness-vm-id` and wipes stale state on mismatch. Keeping
# the destroy target minimal avoids a second, duplicate mechanism — single
# source of truth beats belt-and-braces for this.
.PHONY: destroy
destroy:
	-cd $(HERE) && $(VAGRANT) destroy -f
	@# Safety net for the case where vagrant was killed mid-flight (SIGKILL
	@# on `vagrant up`, OOM, session drop). `vagrant destroy` can no longer
	@# clean up orphan libvirt domains + volumes if its own state tracker
	@# is gone, and the next `vagrant up` then fails instantly with
	@# "Volume for domain is already created". Belt-and-braces: force-remove
	@# any domain and volume this Vagrantfile is known to allocate.
	@for d in $(LIBVIRT_DOMAINS); do \
		if $(VIRSH) dominfo $$d >/dev/null 2>&1 ; then \
			echo "== cleanup: virsh destroy $$d" ; \
			$(VIRSH) destroy  $$d >/dev/null 2>&1 || true ; \
			$(VIRSH) undefine --nvram $$d >/dev/null 2>&1 || \
				$(VIRSH) undefine        $$d >/dev/null 2>&1 || true ; \
		fi ; \
	done
	@for v in $(LIBVIRT_VOLUMES); do \
		if $(VIRSH) vol-info --pool $(LIBVIRT_POOL) $$v >/dev/null 2>&1 ; then \
			echo "== cleanup: virsh vol-delete $$v" ; \
			$(VIRSH) vol-delete --pool $(LIBVIRT_POOL) $$v >/dev/null 2>&1 || true ; \
		fi ; \
	done
	@# Drop the local vagrant state directory when it has drifted from
	@# libvirt reality — a leftover .vagrant/machines/*/libvirt/id pointing
	@# at a no-longer-existing UUID causes `vagrant status` to report
	@# "inaccessible" and `vagrant destroy` to no-op.
	@for m in $(HERE)/.vagrant/machines/*/libvirt ; do \
		[ -d "$$m" ] || continue ; \
		if [ -f "$$m/id" ]; then \
			uuid=$$(cat "$$m/id") ; \
			if ! $(VIRSH) dominfo $$uuid >/dev/null 2>&1 ; then \
				echo "== cleanup: removing stale vagrant state at $$m" ; \
				rm -rf "$$m" ; \
			fi ; \
		fi ; \
	done

.PHONY: wipe
wipe: destroy
	@for n in $(NETS); do \
		echo "== removing libvirt net $$n" ; \
		$(VIRSH) net-destroy   $$n >/dev/null 2>&1 || true ; \
		$(VIRSH) net-undefine  $$n >/dev/null 2>&1 || true ; \
	done

# `virsh net-list --name` prints only active networks, one per line.
# We stash the list once and test membership with bash string match to
# avoid SIGPIPE / pipefail issues that arise from piping into `grep -q`
# under `set -eu -o pipefail`.
.PHONY: networks
networks:
	@active_list=$$'\n'"$$($(VIRSH) net-list --name)"$$'\n' ; \
	for n in $(NETS); do \
		xml="$(NET_DIR)/$${n#k8slab-}.xml" ; \
		if ! $(VIRSH) net-info $$n >/dev/null 2>&1 ; then \
			echo "== defining libvirt net $$n from $$xml" ; \
			$(VIRSH) net-define $$xml ; \
			$(VIRSH) net-autostart $$n ; \
		fi ; \
		if [[ "$$active_list" != *$$'\n'"$$n"$$'\n'* ]] ; then \
			echo "== starting libvirt net $$n" ; \
			$(VIRSH) net-start $$n ; \
		fi ; \
	done

.PHONY: ssh
ssh:
	cd $(HERE) && $(VAGRANT) ssh host

.PHONY: status
status:
	cd $(HERE) && $(VAGRANT) status

.PHONY: inventory
inventory:
	@$(HERE)/inventory.py
