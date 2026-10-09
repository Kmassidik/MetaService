"""How the chat reaches the AI: only through the Root's metered proxy, never with a provider key.

The chat shows the Root its own access key to get a short-lived capability, then asks the Root for each reply.
Standard library only. Redirects are refused, so a reply can never send the capability to another host.
"""
import json
import time
import urllib.error
import urllib.parse
import urllib.request

REQUEST_SECONDS = 60
RENEW_BEFORE_SECONDS = 30
MAX_REPLY_BYTES = 256 * 1024


class BrainNotConfigured(Exception):
    """The Root has no AI provider set up yet."""


class BrainUnavailable(Exception):
    """The Root or the provider could not answer. The text is safe to show to the person chatting."""


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def check_root_url(text):
    """The Root's address as given by the Agent: http or https with a host, nothing else."""
    parts = urllib.parse.urlsplit(text)
    if parts.scheme not in ("http", "https") or not parts.hostname or parts.username or parts.query or parts.fragment:
        raise SystemExit("--brain-url must be an http or https address of the Root")
    return text.rstrip("/")


class Brain:
    def __init__(self, root_url, access_key, clock=time.monotonic):
        self.root_url, self.access_key, self.clock = check_root_url(root_url), access_key, clock
        self.capability, self.renew_at = None, 0.0
        self.opener = urllib.request.build_opener(_NoRedirect)

    def reply(self, message):
        """One answer for one message. A capability that was refused is replaced once, then the failure is reported."""
        for attempt in (1, 2):
            token = self._capability()
            status, body = self._post("/v1/brain/chat", token, {"message": message})
            if status == 401 and attempt == 1:
                self.capability = None
                continue
            return self._text(status, body)
        raise BrainUnavailable("the Root refused this chat")

    def _capability(self):
        if self.capability and self.clock() < self.renew_at:
            return self.capability
        status, body = self._post("/v1/brain/capability", self.access_key, None)
        if status == 503:
            raise BrainNotConfigured()
        if status != 200 or not isinstance(body.get("capability"), str):
            raise BrainUnavailable("the Root did not give this chat access to the AI")
        self.capability = body["capability"]
        self.renew_at = self.clock() + max(1, int(body.get("expires_in", 60)) - RENEW_BEFORE_SECONDS)
        return self.capability

    @staticmethod
    def _text(status, body):
        if status == 200 and isinstance(body.get("reply"), str):
            return body["reply"]
        if status == 429:
            raise BrainUnavailable("the AI is busy, try again in a moment")
        if status == 503:
            raise BrainNotConfigured()
        raise BrainUnavailable("the AI could not answer right now")

    def _post(self, path, bearer, payload):
        data = json.dumps(payload).encode() if payload is not None else b""
        request = urllib.request.Request(self.root_url + path, data=data, method="POST",
                                         headers={"Authorization": f"Bearer {bearer}", "Content-Type": "application/json"})
        try:
            with self.opener.open(request, timeout=REQUEST_SECONDS) as response:
                return response.status, self._json(response.read(MAX_REPLY_BYTES))
        except urllib.error.HTTPError as problem:
            with problem:
                return problem.code, self._json(problem.read(MAX_REPLY_BYTES))
        except (urllib.error.URLError, OSError):
            raise BrainUnavailable("the Root cannot be reached")

    @staticmethod
    def _json(raw):
        try:
            body = json.loads(raw)
        except ValueError:
            return {}
        return body if isinstance(body, dict) else {}
