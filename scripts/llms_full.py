#!/usr/bin/env python3
"""Print llms-full.txt: every page of the site in navigation order (mkdocs.yml),
with the files a page embeds (`--8<-- "<path>"`) expanded. `make docs` writes
it into the built site; it is not kept in git.
"""
from __future__ import annotations

import pathlib
import re

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
SNIPPET = re.compile(r'^--8<-- "([^"]+)"$', re.M)


class _Loader(yaml.SafeLoader):
    """mkdocs.yml carries !ENV and !!python/name tags; their values are not needed."""


_Loader.add_multi_constructor("!", lambda loader, suffix, node: None)
_Loader.add_multi_constructor("tag:yaml.org,2002:python/", lambda loader, suffix, node: None)


def pages(nav) -> list[str]:
    found: list[str] = []
    for item in nav:
        value = next(iter(item.values())) if isinstance(item, dict) else item
        found += pages(value) if isinstance(value, list) else [value]
    return found


def main() -> None:
    config = yaml.load((ROOT / "mkdocs.yml").read_text(), Loader=_Loader)
    print("# k8s-lab — documentation in one file\n")
    print("> Every page of https://k8s-lab.romancello.net/ in reading order. "
          "Source: https://github.com/kogeler/k8s-lab\n")
    for page in pages(config["nav"]):
        text = (ROOT / "doc" / page).read_text()
        text = SNIPPET.sub(lambda m: (ROOT / m.group(1)).read_text().rstrip("\n"), text)
        print(f"\n---\n\n<!-- source: doc/{page} -->\n\n{text.rstrip()}\n")


if __name__ == "__main__":
    main()
