#!/usr/bin/env python3
"""Check the common-variable contract (doc/variable-contract.md).

Fails when a common variable (`k8s_lab_*`) is
  * set in the reference tests/playbooks/group_vars/all.yml but read by no role
    or reference playbook,
  * read by a role or reference playbook but not set in the reference file,
  * set in the reference file but missing from doc/variable-contract.md.

For every role with meta/argument_specs.yml it also fails when
  * the role reads a common variable outside defaults/main.yml,
  * a common variable read in defaults/main.yml is not declared `required: true`,
  * an option carries `default:` (defaults/main.yml is the only place for it),
  * a role input is in defaults/main.yml but not declared, or declared without
    a default and without `required: true`, or lacks the role's prefix,
  * two roles declare a common variable with a different type or description.

The registry tables of doc/variable-contract.md (between the `generated`
markers) are rendered from argument_specs, defaults and the reference file;
the check fails when they are stale. `--write` renders them in place.
"""
from __future__ import annotations

import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
REFERENCE = ROOT / "tests" / "playbooks" / "group_vars" / "all.yml"
CONTRACT = ROOT / "doc" / "variable-contract.md"
SOURCES = [
    *sorted((ROOT / "ansible" / "roles").rglob("*.yml")),
    *sorted((ROOT / "ansible" / "roles").rglob("*.j2")),
    *sorted((ROOT / "tests" / "playbooks").glob("*.yml")),
]

# Facts the roles publish for each other (set by management_cluster's `state`
# entry point); never set in group_vars.
PUBLISHED = {
    "k8s_lab_management_state",
    "k8s_lab_management_kubeconfig",
    "k8s_lab_management_kubeconfig_runner",
}

JINJA = re.compile(r"\{\{(.*?)\}\}|\{%(.*?)%\}", re.S)
JINJA_COMMENT = re.compile(r"\{#.*?#\}", re.S)
# A variable reference: not an attribute (`x.k8s_lab_y`) and not a quoted key.
NAME = re.compile(r"(?<![\w.'\"])k8s_lab_[a-z0-9_]+\b")


def reads(path: pathlib.Path) -> set[str]:
    return reads_text(path.read_text())


def reads_text(text: str) -> set[str]:
    text = JINJA_COMMENT.sub("", text)
    text = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
    found: set[str] = set()
    for match in JINJA.finditer(text):
        found.update(NAME.findall(match.group(1) or match.group(2) or ""))
    return found


def load(path: pathlib.Path) -> dict:
    return (yaml.safe_load(path.read_text()) or {}) if path.exists() else {}


def roles() -> list[tuple[str, dict, dict]]:
    """(role, defaults, options of every entry point) for each role with argument_specs."""
    found = []
    for spec_path in sorted((ROOT / "ansible" / "roles").glob("*/meta/argument_specs.yml")):
        role_dir = spec_path.parent.parent
        options: dict[str, dict] = {}
        for entry in (load(spec_path).get("argument_specs") or {}).values():
            options.update({name: option or {} for name, option in (entry.get("options") or {}).items()})
        found.append((role_dir.name, load(role_dir / "defaults" / "main.yml"), options))
    return found


def cell(text: str | list[str]) -> str:
    # argument_specs allows a description as a string or a list of paragraphs.
    if isinstance(text, list):
        text = " ".join(str(part) for part in text)
    return " ".join(str(text).split()).replace("|", "\\|")


def shown(value) -> str:
    """A reference value as the table shows it."""
    if isinstance(value, str) and "{{" in value:
        return "*harness*"
    if isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value):
        return f"`{value[:8]}…{value[-5:]}`"
    return f"`{cell(value)}`"


def tables(reference: dict) -> tuple[dict[str, str], list[str]]:
    """The generated blocks of the contract document, and declaration conflicts."""
    declared: dict[str, set[tuple[str, str]]] = {}
    readers: dict[str, list[str]] = {}
    required = []
    for role, defaults, options in roles():
        for name, option in options.items():
            if name.startswith("k8s_lab_") and name not in PUBLISHED:
                declared.setdefault(name, set()).add((option.get("type", "str"), cell(option.get("description", ""))))
            elif option.get("required") and not name.startswith("k8s_lab_"):
                required.append((name, role, cell(option.get("description", ""))))
        for name, value in defaults.items():
            for read in sorted(reads_text(yaml.safe_dump(value)) - PUBLISHED):
                readers.setdefault(read, []).append(f"`{name}`")

    conflicts = [f"{name}: declared differently by the roles: {sorted(seen)}"
                 for name, seen in sorted(declared.items()) if len(seen) > 1]
    common = ["| Variable | Type | Reference value | Meaning | Role inputs that default to it |",
              "|---|---|---|---|---|"]
    for name, value in reference.items():
        if not name.startswith("k8s_lab_"):
            continue
        kind, meaning = sorted(declared.get(name, {("", "")}))[0]
        common.append(f"| `{name}` | {kind} | {shown(value)} | {meaning} | {', '.join(readers.get(name, []))} |")
    inputs = ["| Input | Role | Reference value | Meaning |", "|---|---|---|---|"]
    for name, role, meaning in sorted(required):
        inputs.append(f"| `{name}` | `{role}` | {shown(reference.get(name, ''))} | {meaning} |")
    return {"common-variables": "\n".join(common), "required-inputs": "\n".join(inputs)}, conflicts


def render(contract: str, blocks: dict[str, str]) -> str:
    for key, body in blocks.items():
        contract = re.sub(rf"(<!-- generated: {key} -->\n)(.*?)(<!-- end generated -->)",
                          lambda m, body=body: m.group(1) + body + "\n" + m.group(3), contract, flags=re.S)
    return contract


def role_spec_errors() -> list[str]:
    errors = []
    for spec_path in sorted((ROOT / "ansible" / "roles").glob("*/meta/argument_specs.yml")):
        role_dir = spec_path.parent.parent
        role = role_dir.name
        defaults_path = role_dir / "defaults" / "main.yml"
        defaults = load(defaults_path)
        options: dict[str, dict] = {}
        for entry in (load(spec_path).get("argument_specs") or {}).values():
            options.update({name: option or {} for name, option in (entry.get("options") or {}).items()})

        for path in sorted(p for p in role_dir.rglob("*") if p.suffix in {".yml", ".j2"}):
            if path in (defaults_path, spec_path):
                continue
            for name in sorted(reads(path) - PUBLISHED):
                errors.append(f"{role}: reads {name} in {path.relative_to(ROOT)}; only defaults/main.yml may")
        for name in sorted(reads(defaults_path) - PUBLISHED) if defaults_path.exists() else []:
            if not options.get(name, {}).get("required"):
                errors.append(f"{role}: reads {name} but argument_specs.yml does not declare it required")
        for name, option in sorted(options.items()):
            if "default" in option:
                errors.append(f"{role}: {name} has a default in argument_specs.yml; put it in defaults/main.yml")
            if name.startswith("k8s_lab_"):
                continue
            if not name.startswith(f"{role}_"):
                errors.append(f"{role}: input {name} lacks the prefix {role}_")
            if name not in defaults and not option.get("required"):
                errors.append(f"{role}: input {name} has no default and is not declared required")
        for name in sorted(set(defaults) - set(options)):
            errors.append(f"{role}: input {name} is in defaults/main.yml but not in argument_specs.yml")
    return errors


def main() -> int:
    reference = yaml.safe_load(REFERENCE.read_text()) or {}
    declared = {key for key in reference if key.startswith("k8s_lab_")}
    readers: dict[str, set[str]] = {}
    for path in SOURCES:
        for name in reads(path):
            readers.setdefault(name, set()).add(str(path.relative_to(ROOT)))
    contract = CONTRACT.read_text() if CONTRACT.exists() else ""

    errors = []
    for name in sorted(declared & PUBLISHED):
        errors.append(f"{name}: a published fact, must not be set in {REFERENCE.relative_to(ROOT)}")
    for name in sorted(declared - readers.keys()):
        errors.append(f"{name}: set in {REFERENCE.relative_to(ROOT)} but read by no role or playbook")
    for name in sorted(readers.keys() - declared - PUBLISHED):
        files = ", ".join(sorted(readers[name]))
        errors.append(f"{name}: read by {files} but not set in {REFERENCE.relative_to(ROOT)}")
    for name in sorted(declared | PUBLISHED):
        if f"`{name}`" not in contract:
            errors.append(f"{name}: not described in {CONTRACT.relative_to(ROOT)}")
    errors.extend(role_spec_errors())

    blocks, conflicts = tables(reference)
    errors.extend(conflicts)
    rendered = render(contract, blocks)
    if "--write" in sys.argv[1:] and rendered != contract:
        CONTRACT.write_text(rendered)
        print(f"contract: rendered the tables of {CONTRACT.relative_to(ROOT)}")
    elif rendered != contract:
        errors.append(f"{CONTRACT.relative_to(ROOT)}: generated tables are stale; run {pathlib.Path(__file__).name} --write")
    for key in blocks:
        if f"<!-- generated: {key} -->" not in contract:
            errors.append(f"{CONTRACT.relative_to(ROOT)}: marker for the {key} table missing")

    for error in errors:
        print(f"contract: {error}")
    if not errors:
        print(f"contract: {len(declared)} common variables and {len(PUBLISHED)} published facts, all consistent")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
