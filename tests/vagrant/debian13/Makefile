# The local test host (see Vagrantfile). The root Makefile's vm-up and
# vm-destroy call these targets.
#
#   make up       check the prerequisites, start the VM, write .vagrant/ssh-config
#   make destroy  remove the VM, including a domain and volumes vagrant lost track of
#   make reboot   reboot the guest and wait until it is back (the host-reboot drill)
#   make ssh      open a shell on the VM
#   make status   show the VM state

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

HERE       := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SSH_CONFIG := $(HERE)/.vagrant/ssh-config
VAGRANT    ?= vagrant
# vagrant-libvirt's default URI: the system libvirtd through the libvirt group
# socket, no sudo.
VIRSH      ?= virsh -c qemu:///system
# What the Vagrantfile allocates in libvirt's default pool: the domain
# <default_prefix><machine>, its system volume and the pool disk (vdb).
DOMAIN     := k8slab_host
VOLUMES    := $(DOMAIN).img $(DOMAIN)-vdb.qcow2
POOL       := default
# The pool disk as the guest sees it (the Vagrantfile's disk serial).
POOL_DISK  := /dev/disk/by-id/virtio-k8slab-lxdpool

.PHONY: up preflight libvirt destroy reboot ssh status

# What vagrant would otherwise report far from the cause.
preflight: libvirt
	@command -v $(VAGRANT) >/dev/null \
	  || { echo "ERROR: $(VAGRANT) not found" >&2; exit 1; }
	@$(VAGRANT) plugin list 2>/dev/null | grep '^vagrant-libvirt ' >/dev/null \
	  || { echo "ERROR: the vagrant-libvirt plugin is missing (doc/quickstart-local.md)" >&2; exit 1; }
	@[ -r /dev/kvm ] && [ -w /dev/kvm ] \
	  || { echo "ERROR: /dev/kvm is missing or not accessible (KVM enabled? user in the kvm group?)" >&2; exit 1; }

# Without libvirt, destroy would take every domain for absent and forget it.
libvirt:
	@$(VIRSH) uri >/dev/null 2>&1 \
	  || { echo "ERROR: libvirt does not answer on qemu:///system (libvirtd running? user in the libvirt group?)" >&2; exit 1; }

# Idempotent: `vagrant up` leaves a running VM alone, and the SSH config is
# replaced only when it changed. tests/inventory/hosts.yml reaches the VM as
# `host` through that file.
up: preflight
	cd $(HERE) && $(VAGRANT) up --provider=libvirt host
	cd $(HERE) && $(VAGRANT) ssh-config host > $(SSH_CONFIG).tmp
	if cmp -s $(SSH_CONFIG).tmp $(SSH_CONFIG); then rm $(SSH_CONFIG).tmp; else mv $(SSH_CONFIG).tmp $(SSH_CONFIG); fi
	ssh -F $(SSH_CONFIG) host test -b $(POOL_DISK) \
	  || { echo "ERROR: the VM has no $(POOL_DISK), the pool disk of the Vagrantfile" >&2; exit 1; }

# After an interrupted `vagrant up` vagrant may no longer know the domain and
# its volumes, and the next `up` fails with "Volume for domain is already
# created"; remove them directly, then drop vagrant state that points at a
# domain libvirt no longer has. Idempotent.
destroy: libvirt
	-cd $(HERE) && $(VAGRANT) destroy -f
	@if $(VIRSH) dominfo $(DOMAIN) >/dev/null 2>&1; then \
		echo "== removing domain $(DOMAIN)"; \
		$(VIRSH) destroy $(DOMAIN) >/dev/null 2>&1 || true; \
		$(VIRSH) undefine --nvram $(DOMAIN) >/dev/null 2>&1 || $(VIRSH) undefine $(DOMAIN) >/dev/null; \
	fi
	@for v in $(VOLUMES); do \
		if $(VIRSH) vol-info --pool $(POOL) $$v >/dev/null 2>&1; then \
			echo "== removing volume $$v"; \
			$(VIRSH) vol-delete --pool $(POOL) $$v >/dev/null; \
		fi; \
	done
	@id=$(HERE)/.vagrant/machines/host/libvirt/id; \
	if [ -f "$$id" ] && ! $(VIRSH) dominfo "$$(cat "$$id")" >/dev/null 2>&1; then \
		echo "== removing stale vagrant state"; \
		rm -rf "$(HERE)/.vagrant/machines/host/libvirt"; \
	fi
	rm -f $(SSH_CONFIG)

# A reboot from inside the guest, as on a real host: systemd stops the services,
# the LXD snap shuts its instances down. Done when the guest answers with a new
# boot id; the SSH session the reboot cuts off is not an error.
reboot:
	@before=$$(ssh -F $(SSH_CONFIG) host cat /proc/sys/kernel/random/boot_id); \
	ssh -F $(SSH_CONFIG) host sudo systemctl reboot || true; \
	for _ in $$(seq 1 60); do \
		sleep 5; \
		now=$$(ssh -F $(SSH_CONFIG) -o ConnectTimeout=5 host cat /proc/sys/kernel/random/boot_id 2>/dev/null || true); \
		if [ -n "$$now" ] && [ "$$now" != "$$before" ]; then echo "== the VM is back"; exit 0; fi; \
	done; \
	echo "ERROR: the VM did not come back within 5 minutes" >&2; exit 1

ssh:
	cd $(HERE) && $(VAGRANT) ssh host

status:
	cd $(HERE) && $(VAGRANT) status
