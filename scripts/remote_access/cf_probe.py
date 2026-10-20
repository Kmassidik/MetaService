"""Asking a web address "are you alive?" The tool takes this as a plain function so tests can swap it."""
from __future__ import annotations

import urllib.error
import urllib.request

TIMEOUT_SECONDS = 10


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def status_of(url: str) -> int:
    """The HTTP status the address answers (redirects are not followed), or 0 when nothing answers."""
    opener = urllib.request.build_opener(_NoRedirect)
    request = urllib.request.Request(url, headers={"User-Agent": "metaservice-remote-access"})
    try:
        with opener.open(request, timeout=TIMEOUT_SECONDS) as reply:
            return reply.status
    except urllib.error.HTTPError as failure:
        return failure.code
    except (urllib.error.URLError, OSError, ValueError):
        return 0


def reached(status: int) -> bool:
    """Something answered, even if it said no (a 403 from the panel is still the panel). Cloudflare's own tunnel-down pages are 5xx, and 0 is silence."""
    return 0 < status < 500
