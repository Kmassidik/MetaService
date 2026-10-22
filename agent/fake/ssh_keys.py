"""The rule every helper applies to one authorized_keys line before it writes anything (the same rule as the real helpers)."""
import re

KEY_TYPES = ("ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521", "ssh-rsa", "sk-ssh-ed25519@openssh.com")
MAX_LINE_BYTES = 800
MAX_COMMENT_CHARS = 64
MIN_PARTS, MAX_PARTS = 2, 3
BASE64 = re.compile(r"^[A-Za-z0-9+/]+={0,3}$")
COMMENT = re.compile(r"^[A-Za-z0-9._@+:-]+$")


def is_valid_key(line):
    """A key type, one space, base64, and an optional one-word comment. Options before the type, quotes and line breaks are refused."""
    parts = line.split(" ")
    if len(line.encode()) > MAX_LINE_BYTES or not MIN_PARTS <= len(parts) <= MAX_PARTS:
        return False
    kind, blob, comment = parts[0], parts[1], parts[2:]
    return kind in KEY_TYPES and bool(BASE64.match(blob)) and all(_is_comment(text) for text in comment)


def _is_comment(text):
    return len(text) <= MAX_COMMENT_CHARS and bool(COMMENT.match(text))
