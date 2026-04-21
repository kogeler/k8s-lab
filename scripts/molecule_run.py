#!/usr/bin/env python3
"""
Wrapper around `molecule <action> -s <scenario>` for the local harness.

Responsibilities (before handing off to Molecule):

1. Bring the shared Vagrant VM and libvirt networks up — idempotent via
   `make -C tests/vagrant/debian13 up`.
2. Query `vagrant ssh-config` once and export the connection coordinates
   as `K8SLAB_HOST_*` env vars. The scenario's `molecule.yml` reads these
   straight into `host_vars.<host>.ansible_*` via plain `lookup('env', …)`,
   keeping the Molecule config readable.
3. `exec molecule <action> -s <scenario>` — no intermediate temp files,
   no nested `lookup('file', …) | from_yaml` gymnastics.

Invoked by the `tests/molecule/Makefile` pattern rule; also safe to run
directly as `scripts/molecule_run.py <scenario> <action> [extra-molecule-args]`.
"""
from __future__ import annotations

import functools
import glob
import os
import shutil
import sys
from pathlib import Path

# Replace `print` with an unbuffered flushing variant for this module. The
# wrapper exists because we `os.execvpe` later — anything still in Python's
# stdout buffer at exec time is lost, which previously silenced every
# "[molecule_run] …" diagnostic in captured logs.
print = functools.partial(print, flush=True)  # noqa: A001

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _harness import (  # noqa: E402
    REPO_ROOT,
    VAGRANT_DIR,
    query_vagrant_ssh,
    run_make,
)


MOLECULE_DIR = REPO_ROOT / "tests" / "molecule"

# Vagrant libvirt writes the live domain UUID here the moment the VM is
# created and removes it on destroy. We treat this string as the identity
# of the current harness target.
VAGRANT_VM_ID_FILE = VAGRANT_DIR / ".vagrant" / "machines" / "host" / "libvirt" / "id"

# Our own tracker for the last-seen VM identity. Lives in `.artifacts/`
# which is already gitignored.
HARNESS_VM_ID_TRACKER = REPO_ROOT / ".artifacts" / "harness-vm-id"


def _read_text(path: Path) -> str | None:
    try:
        return path.read_text().strip()
    except FileNotFoundError:
        return None


def _invalidate_molecule_state_if_vm_changed() -> None:
    """
    If the live Vagrant VM identity differs from the one we last recorded,
    wipe every Molecule scenario's ephemeral state. This is what makes the
    harness self-healing: no matter how the VM went away (`make destroy`,
    `vagrant destroy`, `virsh destroy`, host reboot, …), the next molecule
    run automatically treats a fresh VM as a fresh target.
    """
    current = _read_text(VAGRANT_VM_ID_FILE)
    if current is None:
        # make up should have materialised the VM just before we got here,
        # so the file not existing is unexpected — but do not crash; fall
        # through with a warning so the operator sees it.
        print(
            "[molecule_run] warning: vagrant libvirt VM id file is missing "
            f"at {VAGRANT_VM_ID_FILE}; skipping staleness check",
            file=sys.stderr,
        )
        return

    previous = _read_text(HARNESS_VM_ID_TRACKER)
    if previous == current:
        return

    stale_dirs = sorted(glob.glob(str(Path.home() / ".ansible" / "tmp" / "molecule.*")))
    if stale_dirs:
        print(
            "[molecule_run] VM identity changed "
            f"({previous or '<none>'} → {current}); "
            f"invalidating {len(stale_dirs)} Molecule scenario state dir(s)"
        )
        for path in stale_dirs:
            shutil.rmtree(path, ignore_errors=True)
    else:
        print(
            f"[molecule_run] recording VM identity {current} "
            "(no prior Molecule state to invalidate)"
        )

    HARNESS_VM_ID_TRACKER.parent.mkdir(parents=True, exist_ok=True)
    HARNESS_VM_ID_TRACKER.write_text(current + "\n")


def _usage() -> int:
    sys.stderr.write(
        "usage: molecule_run.py <scenario> <action> [extra molecule args]\n"
    )
    return 2


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        return _usage()
    scenario, action, *extra = argv[1:]

    scenario_file = MOLECULE_DIR / scenario / "molecule.yml"
    if not scenario_file.is_file():
        sys.exit(f"[molecule_run] scenario not found: {scenario_file}")

    molecule_bin = shutil.which("molecule")
    if molecule_bin is None:
        sys.exit(
            "[molecule_run] molecule not on PATH — activate the project "
            "venv first (see PLAN-stage1-progress.md)"
        )

    print(f"[molecule_run] scenario={scenario} action={action}")
    print("[molecule_run] ensuring libvirt networks + host VM via `make up`")
    run_make("up")

    # Self-heal: if the live VM has a different identity than we saw last
    # run (fresh VM, destroyed-and-recreated, etc.), wipe stale Molecule
    # scenario state so the next phases do not skip prepare-like steps
    # against a blank target.
    _invalidate_molecule_state_if_vm_changed()

    ssh = query_vagrant_ssh("host")
    if ssh is None:
        sys.exit(
            "[molecule_run] vagrant host VM is not up after `make up` — "
            "check `vagrant status` in tests/vagrant/debian13"
        )

    env = os.environ.copy()
    env.update(
        {
            "K8SLAB_HOST_ADDR": ssh.address,
            "K8SLAB_HOST_USER": ssh.user,
            "K8SLAB_HOST_PORT": str(ssh.port),
            "K8SLAB_HOST_KEY": ssh.identity_file,
            # Point Molecule at our non-standard scenario layout —
            # `tests/molecule/<scenario>/` instead of `molecule/<scenario>/`.
            "MOLECULE_GLOB": str(MOLECULE_DIR / "*" / "molecule.yml"),
        }
    )

    print(
        f"[molecule_run]   K8SLAB_HOST_ADDR={ssh.address} "
        f"K8SLAB_HOST_USER={ssh.user} K8SLAB_HOST_PORT={ssh.port}"
    )
    print(f"[molecule_run]   K8SLAB_HOST_KEY={ssh.identity_file}")

    # NOTE: we intentionally do NOT auto-reset Molecule scenario state
    # here. That would break the standard dev loop (re-running
    # `verify`/`converge` alone would re-do `prepare` every time).
    # Scenario state is invalidated where it actually becomes invalid —
    # in the Vagrant `destroy` target, which wipes
    # `~/.ansible/tmp/molecule.*` alongside the VM.

    # execvpe replaces this process with molecule — no extra Python frame
    # in the stack, and molecule inherits the env we just populated.
    cmd = [molecule_bin, action, "-s", scenario, *extra]
    os.chdir(MOLECULE_DIR)
    os.execvpe(cmd[0], cmd, env)  # noqa: returns only on failure


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
