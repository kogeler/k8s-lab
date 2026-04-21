#!/usr/bin/env python3
"""
Render a kubeconfig artifact from a source (e.g. a k3s node or an exported
CAPI cluster kubeconfig) into `.artifacts/clusters/<cluster>.kubeconfig`.

Consumed by later phases (plan §5.05, §8.13, §8.18). Current stage: stub.

Usage (planned):
    render_kubeconfig.py --source /var/lib/rancher/k3s/server/cred/admin.kubeconfig \\
                        --server https://host.example:16443 \\
                        --output .artifacts/bootstrap.kubeconfig

This stub exits 2 with a helpful message when called, so pipelines that
reach it before the feature is implemented fail loudly rather than silently
producing a bad kubeconfig.
"""
from __future__ import annotations

import sys


def main() -> int:
    print(
        "render_kubeconfig.py: not implemented yet (phase 5.05). "
        "See PLAN-stage1.md §8.13 / §8.18 / §12 Phase 5.05.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
