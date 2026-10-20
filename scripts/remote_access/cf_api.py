"""The Cloudflare API calls this tool makes, and nothing else. The token travels only in a request header and is scrubbed from every message."""
from __future__ import annotations

import json
import re
import urllib.error
import urllib.request

PRODUCTION_BASE = "https://api.cloudflare.com/client/v4"
LOOPBACK_BASE = re.compile(r"^http://127\.0\.0\.1:\d{2,5}(/.*)?$")  # only for tests against a fake server
TIMEOUT_SECONDS = 20


class CloudflareError(Exception):
    """What Cloudflare said went wrong, in one sentence, without the token."""


class CloudflareApi:
    def __init__(self, token: str, base: str = PRODUCTION_BASE):
        if base != PRODUCTION_BASE and not LOOPBACK_BASE.match(base):
            raise CloudflareError("The API address may only be Cloudflare's own, or a local test server.")
        self._token = token
        self._base = base.rstrip("/")

    def _scrub(self, text: str) -> str:
        return text.replace(self._token, "***")

    def _call(self, method: str, path: str, body=None):
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(self._base + path, data=data, method=method, headers={
            "Authorization": f"Bearer {self._token}", "Content-Type": "application/json", "User-Agent": "metaservice-remote-access"})
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as reply:
                payload = json.loads(reply.read() or b"{}")
        except urllib.error.HTTPError as failure:
            raw, status = failure.read(), failure.code
            failure.close()
            raise CloudflareError(self._reason(raw, status)) from None
        except (urllib.error.URLError, OSError, ValueError):
            raise CloudflareError("Cloudflare could not be reached.") from None
        if not payload.get("success", False):
            raise CloudflareError(self._reason(json.dumps(payload).encode(), 0))
        return payload.get("result")

    def _reason(self, raw: bytes, status: int) -> str:
        try:
            errors = json.loads(raw).get("errors") or []
            message = errors[0].get("message", "") if errors else ""
        except (ValueError, AttributeError, IndexError):
            message = ""
        suffix = f" (HTTP {status})" if status else ""
        return self._scrub((message or "Cloudflare refused the request") + suffix)[:200]

    # The token and where it may act
    def verify_token(self, account: str) -> bool:
        """A user-owned token verifies at /user, an account-owned one under its account."""
        for path in ("/user/tokens/verify", f"/accounts/{account}/tokens/verify"):
            try:
                if (self._call("GET", path) or {}).get("status") == "active":
                    return True
            except CloudflareError:
                continue
        return False

    def zone_name(self, zone_id: str) -> str:
        return (self._call("GET", f"/zones/{zone_id}") or {}).get("name", "")

    # Tunnels
    def tunnels_named(self, account: str, name: str) -> list:
        return self._call("GET", f"/accounts/{account}/cfd_tunnel?name={name}&is_deleted=false") or []

    def create_tunnel(self, account: str, name: str) -> dict:
        return self._call("POST", f"/accounts/{account}/cfd_tunnel", {"name": name, "config_src": "cloudflare"})

    def tunnel(self, account: str, tunnel_id: str) -> dict:
        return self._call("GET", f"/accounts/{account}/cfd_tunnel/{tunnel_id}") or {}

    def put_config(self, account: str, tunnel_id: str, config: dict) -> None:
        self._call("PUT", f"/accounts/{account}/cfd_tunnel/{tunnel_id}/configurations", config)

    def tunnel_token(self, account: str, tunnel_id: str) -> str:
        token = self._call("GET", f"/accounts/{account}/cfd_tunnel/{tunnel_id}/token")
        if not isinstance(token, str) or not token:
            raise CloudflareError("Cloudflare gave no tunnel token.")
        return token

    def clean_connections(self, account: str, tunnel_id: str) -> None:
        self._call("DELETE", f"/accounts/{account}/cfd_tunnel/{tunnel_id}/connections")

    def delete_tunnel(self, account: str, tunnel_id: str) -> None:
        self._call("DELETE", f"/accounts/{account}/cfd_tunnel/{tunnel_id}")

    # DNS
    def dns_find(self, zone: str, name: str):
        found = self._call("GET", f"/zones/{zone}/dns_records?name={name}") or []
        return found[0] if found else None

    def dns_create(self, zone: str, name: str, content: str) -> dict:
        return self._call("POST", f"/zones/{zone}/dns_records", {"type": "CNAME", "name": name, "content": content, "proxied": True})

    def dns_delete(self, zone: str, record_id: str) -> None:
        self._call("DELETE", f"/zones/{zone}/dns_records/{record_id}")
