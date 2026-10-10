"""Who may use the chat screen: whoever opened it with this machine's access key. The key itself stays out of cookies; the screen gets a session and a CSRF token."""
import hmac
import secrets
import threading
import time
from http.cookies import CookieError, SimpleCookie

COOKIE = "ms_chat_session"
SESSION_SECONDS = 12 * 60 * 60
MAX_SESSIONS = 50


class Session:
    def __init__(self, token, csrf, expires):
        self.token, self.csrf, self.expires = token, csrf, expires


class Sessions:
    def __init__(self, key, clock=time.monotonic):
        self.key, self.clock = key, clock
        self.lock = threading.Lock()
        self.by_token = {}

    def open(self, presented):
        """A new session for the right key, else None."""
        if not hmac.compare_digest(presented.encode(), self.key.encode()):
            return None
        session = Session(secrets.token_urlsafe(32), secrets.token_urlsafe(32), self.clock() + SESSION_SECONDS)
        with self.lock:
            self._forget_expired()
            self.by_token[session.token] = session
            while len(self.by_token) > MAX_SESSIONS:
                self.by_token.pop(next(iter(self.by_token)))
        return session

    def find(self, cookie_header):
        """The live session a Cookie header carries, else None."""
        token = cookie_value(cookie_header)
        with self.lock:
            session = self.by_token.get(token)
            return session if session and session.expires > self.clock() else None

    def close(self, session):
        with self.lock:
            self.by_token.pop(session.token, None)

    def _forget_expired(self):
        now = self.clock()
        for token in [token for token, session in self.by_token.items() if session.expires <= now]:
            del self.by_token[token]


def cookie_value(header):
    cookie = SimpleCookie()
    try:
        cookie.load(header or "")
    except CookieError:  # a broken Cookie header is just no session
        return ""
    morsel = cookie.get(COOKIE)
    return morsel.value if morsel else ""


def set_cookie(session):
    return f"{COOKIE}={session.token}; Path=/; HttpOnly; SameSite=Strict; Max-Age={SESSION_SECONDS}"


def clear_cookie():
    return f"{COOKIE}=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0"
