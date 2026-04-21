#!/usr/bin/env python3
"""
Emit a minimal Ansible inventory for the running Vagrant host VM.

Used by ad-hoc `ansible-playbook -i ./inventory.py` calls from the
`tests/vagrant/debian13/` directory. NOT a general-purpose inventory
generator — it targets only the local harness.

If the VM is not up, emits a placeholder inventory so callers get a
clear error instead of an opaque YAML parse failure.
"""
from __future__ import annotations

import sys
from pathlib import Path

# Reuse the same ssh-config parsing as the Molecule hooks so both
# entry points stay in sync.
sys.path.insert(
    0, str(Path(__file__).resolve().parents[3] / "scripts")
)
from _harness import PLATFORM_HOST_NAME, query_vagrant_ssh  # noqa: E402


def _render_empty() -> str:
    return (
        "# Vagrant host VM is not up yet — run `make up` first.\n"
        "[k8slab_host]\n"
    )


def _render(ssh) -> str:
    return (
        "[k8slab_host]\n"
        f"{PLATFORM_HOST_NAME} "
        f"ansible_host={ssh.address} "
        f"ansible_user={ssh.user} "
        f"ansible_port={ssh.port} "
        f"ansible_ssh_private_key_file={ssh.identity_file}\n"
        "\n"
        "[k8slab_host:vars]\n"
        "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o "
        "UserKnownHostsFile=/dev/null'\n"
    )


def main() -> int:
    ssh = query_vagrant_ssh("host")
    sys.stdout.write(_render(ssh) if ssh else _render_empty())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
