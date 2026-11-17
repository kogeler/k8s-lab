#!/usr/bin/env python3
"""Fail when a page names something the repository does not have.

Checked in doc/**/*.md, the role READMEs, the root README, AGENTS,
CONTRIBUTING, SECURITY, CHANGELOG, ROADMAP, llms.txt and the pull request
template:
  * `make <target>` and `make -C <dir> <target>`: the target exists;
  * a role input (`<role>_*`) or common variable (`k8s_lab_*`) in backticks:
    a role declares it in meta/argument_specs.yml;
  * a repository path in backticks, and every relative link: it exists.
mkdocs build --strict checks links inside doc/; links that leave doc/ become
GitHub URLs in the site, so only this check sees them.
"""
from __future__ import annotations

import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
PAGES = [*sorted(p for p in (ROOT / "doc").rglob("*.md") if not p.is_symlink()),
         *sorted((ROOT / "ansible" / "roles").glob("*/README.md")),
         *(ROOT / name for name in ["README.md", "AGENTS.md", "CONTRIBUTING.md", "SECURITY.md",
                                    "CHANGELOG.md", "ROADMAP.md", "llms.txt",
                                    ".github/PULL_REQUEST_TEMPLATE.md"])]
ROLES = sorted(p.name for p in (ROOT / "ansible" / "roles").iterdir())
TOP = ("ansible/", "charts/", "terraform/", "tests/", "scripts/", "doc/", ".github/", ".config/")
FILES = {"Makefile", "mkdocs.yml", "pyproject.toml", "uv.lock", ".tool-versions", "CHANGELOG.md",
         "ROADMAP.md", "llms.txt", ".gitignore", ".yamllint", ".ansible-lint", ".tflint.hcl"}
# Role-prefixed words that are not inputs: Ansible's directory, a key of handoff.json.
NOT_INPUTS = {"host_vars", "lxd_host_address"}
CODE = re.compile(r"```.*?```|`[^`\n]+`", re.S)


def targets(makefile: pathlib.Path) -> set[str]:
    names = set(re.findall(r"(?m)^([A-Za-z0-9_.%-]+):(?!=)", makefile.read_text()))
    return {n for n in names if "%" not in n and not n.startswith(".")}


def molecule_targets() -> set[str]:
    text = (ROOT / "tests" / "molecule" / "Makefile").read_text()
    scenarios = re.search(r"(?m)^SCENARIOS\s*:=\s*(.+)$", text).group(1).split()
    actions = re.search(r"(?m)^ACTIONS\s*:=\s*(.+)$", text).group(1).split()
    return {f"{s}-{a}" for s in scenarios for a in actions} | targets(ROOT / "tests" / "molecule" / "Makefile")


def declared() -> set[str]:
    names: set[str] = set()
    for role in ROLES:
        for spec in yaml.safe_load((ROOT / "ansible/roles" / role / "meta/argument_specs.yml").read_text())[
                "argument_specs"].values():
            names |= set((spec.get("options") or {}).keys())
    return names


def main() -> int:
    make = {"": targets(ROOT / "Makefile"), "tests/molecule": molecule_targets(),
            "tests/vagrant/debian13": targets(ROOT / "tests/vagrant/debian13/Makefile")}
    inputs = declared()
    role_word = re.compile(r"^(?:k8s_lab|" + "|".join(ROLES) + r")_[a-z0-9_]+$")
    errors: list[str] = []
    for page in PAGES:
        text = page.read_text()
        where = page.relative_to(ROOT)
        code = "\n".join(CODE.findall(text))
        # A name followed by `-*` or `-<…>` is a placeholder (`test-*`, `gha-<action>`).
        for directory, target in re.findall(r"\bmake (?:-C ([\w./-]+) )?([a-z][a-z0-9-]*)(?![\w<*-])", code):
            directory = directory.rstrip("/")
            if directory in make and target not in make[directory]:
                errors.append(f"{where}: make {'-C ' + directory + ' ' if directory else ''}{target}: no such target")
        for word in re.findall(r"`([^`\s]+)`", text):
            if role_word.match(word) and word not in inputs and word not in NOT_INPUTS:
                errors.append(f"{where}: `{word}`: no role declares it")
            path = word.split("#")[0].rstrip("/,.")
            if (path.startswith(TOP) or path in FILES) and not re.search(r"[<*{$]", path):
                if not (ROOT / path).exists():
                    errors.append(f"{where}: `{word}`: no such path")
        for link in re.findall(r"\]\(([^)\s]+)\)", text):
            if re.match(r"^[a-z]+:|^#", link):
                continue
            target = (page.parent / link.split("#")[0]).resolve()
            if not target.exists():
                errors.append(f"{where}: link {link}: no such file")
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
