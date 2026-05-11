"""mkdocs build-time hook: rewrite ../<dir>/<path> relative markdown links
to absolute github.com blob URLs.

The Pages site serves only doc/ (see mkdocs.yml). Cross-references from
chapters under doc/ into plans/, tests/, ansible/, charts/, terraform/,
scripts/, and LICENSE land outside docs_dir, so they would 404 on Pages.
We rewrite them at on_page_markdown so they resolve back to the canonical
GitHub source instead.
"""

import re

REPO_BLOB = "https://github.com/kogeler/k8s-lab/blob/main"

# Matches a markdown link target of the form `](../<rest>)` where <rest>
# does not start with another dot-segment. Inline code spans containing
# the literal sequence are not expected in doc/*.md; fenced code blocks
# do not use markdown link syntax.
_LINK_PATTERN = re.compile(r"\]\(\.\./([^)]+)\)")


def on_page_markdown(markdown, **_kwargs):
    return _LINK_PATTERN.sub(rf"]({REPO_BLOB}/\1)", markdown)
