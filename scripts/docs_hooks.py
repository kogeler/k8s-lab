"""mkdocs build-time hook: rewrite relative markdown links that leave doc/
to absolute github.com blob URLs.

The Pages site serves only doc/ (see mkdocs.yml). Cross-references from
pages under doc/ into tests/, ansible/, charts/, terraform/, scripts/, and
LICENSE land outside docs_dir, so they would 404 on Pages. We rewrite them at
on_page_markdown so they resolve back to the canonical GitHub source instead.
A link is resolved against its page's own directory, so `../02-x.md` from
doc/runbooks/ stays a site link and `../../ansible/` from there is rewritten.
"""

import posixpath
import re

REPO_BLOB = "https://github.com/kogeler/k8s-lab/blob/main"

# A markdown link target that starts with `../`. Inline code spans containing
# the literal sequence are not expected in doc/; fenced code blocks do not use
# markdown link syntax.
_LINK_PATTERN = re.compile(r"\]\((\.\./[^)]+)\)")


def on_page_markdown(markdown, page, **_kwargs):
    page_dir = posixpath.join("doc", posixpath.dirname(page.file.src_uri))

    def rewrite(match):
        target = posixpath.normpath(posixpath.join(page_dir, match.group(1)))
        if target == "doc" or target.startswith("doc/"):
            return match.group(0)
        return f"]({REPO_BLOB}/{target})"

    return _LINK_PATTERN.sub(rewrite, markdown)
