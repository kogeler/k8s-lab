"""
Shared helpers for k8s-lab local-harness Python scripts.

Keeps the entry scripts (`molecule_create.py`, `molecule_destroy.py`,
`tests/vagrant/debian13/inventory.py`) small and consistent.
"""
from __future__ import annotations

import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
VAGRANT_DIR = REPO_ROOT / "tests" / "vagrant" / "debian13"
PLATFORM_HOST_NAME = "k8slab-host"


@dataclass(frozen=True)
class VagrantSSH:
    """Connection details distilled from `vagrant ssh-config`."""

    host: str
    address: str
    user: str
    port: int
    identity_file: str

    @classmethod
    def from_config_output(cls, raw: str, host: str = "host") -> "VagrantSSH":
        """
        Parse the output of `vagrant ssh-config <host>` into a VagrantSSH.

        The output is a sequence of `key value` lines, optionally indented,
        introduced by a `Host <name>` header. We ignore the header and take
        the first value for each key of interest.
        """
        wanted = {"HostName", "User", "Port", "IdentityFile"}
        found: dict[str, str] = {}
        for line in raw.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or stripped.startswith("Host "):
                continue
            key, _, value = stripped.partition(" ")
            if key in wanted and key not in found:
                found[key] = value.strip()
            if wanted.issubset(found):
                break
        missing = wanted - found.keys()
        if missing:
            raise RuntimeError(
                f"vagrant ssh-config for host '{host}' missing keys: "
                f"{sorted(missing)}\n--- raw ---\n{raw}"
            )
        return cls(
            host=host,
            address=found["HostName"],
            user=found["User"],
            port=int(found["Port"]),
            identity_file=found["IdentityFile"],
        )


def require_env(name: str) -> str:
    """Exit with a helpful message if a required env var is missing."""
    value = os.environ.get(name)
    if not value:
        sys.exit(f"[{Path(sys.argv[0]).name}] required env var {name} is not set")
    return value


def query_vagrant_ssh(host: str = "host") -> VagrantSSH | None:
    """
    Return VagrantSSH for `host`, or None if the VM is not up.

    Non-zero exit from `vagrant ssh-config` with "not created" / "not running"
    is treated as "VM absent". Any other failure is re-raised.
    """
    try:
        completed = subprocess.run(
            ["vagrant", "ssh-config", host],
            cwd=str(VAGRANT_DIR),
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        sys.exit("vagrant CLI not found on PATH")
    except subprocess.CalledProcessError as exc:
        combined = (exc.stderr or "") + (exc.stdout or "")
        if any(key in combined for key in ("not created", "not running", "not configured")):
            return None
        raise RuntimeError(
            f"`vagrant ssh-config {host}` failed with rc={exc.returncode}:\n{combined}"
        ) from exc
    return VagrantSSH.from_config_output(completed.stdout, host=host)


def run_make(target: str, *, check: bool = True) -> int:
    """Run `make -C <vagrant_dir> <target>` and return the exit code."""
    return subprocess.run(
        ["make", "-C", str(VAGRANT_DIR), target],
        check=check,
    ).returncode
