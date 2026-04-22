#!/usr/bin/env python3
"""
Export bootstrap-cluster facts as `.auto.tfvars.json` so Terraform fixtures
can consume them without hard-coding cluster endpoint / secret name / etc.

Planned outputs (plan §11.1):
    * bootstrap API endpoint
    * capn-identity secret name
    * infrastructure provider version
    * cluster topology toggles

Current stage: stub. Exits 2 with a helpful message.
"""
from __future__ import annotations

import sys


def main() -> int:
    print(
        "export_bootstrap_facts.py: not implemented yet. "
        "See plan §16.8 (Phase 4) and §11.1 (`.artifacts/` spec).",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
