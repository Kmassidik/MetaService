"""A small RFC 6455 WebSocket, standard library only. Shared by the Fake Agent (server side) and the contract checks (client side).

Frames: encode_frame / read_message. Handshake helpers: accept_key. A blocking Client for the checks.
"""
import base64
import hashlib
import json
import os
import socket
import struct
import time

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
OP_CONTINUATION, OP_TEXT, OP_BINARY, OP_CLOSE, OP_PING, OP_PONG = 0x0, 0x1, 0x2, 0x8, 0x9, 0xA
CONTROL_LIMIT = 125
SHORT_LENGTH_MARKER, LONG_LENGTH_MARKER = 126, 127
CLOSE_NORMAL, CLOSE_PROTOCOL, CLOSE_POLICY, CLOSE_INTERNAL = 1000, 1002, 1008, 1011


class ProtocolError(Exception):
    """The peer broke the protocol (close code 1002)."""


class TooBig(Exception):
    """A message is larger than the limit the reader was given (close code 1008)."""


class ConnectionEnded(Exception):
    """The socket ended without a close frame."""


def accept_key(client_key):
    return base64.b64encode(hashlib.sha1((client_key + GUID).encode()).digest()).decode()


def encode_frame(opcode, payload=b"", mask=False, fin=True):
    first = (0x80 if fin else 0) | opcode
    length = len(payload)
    mask_bit = 0x80 if mask else 0
    if length < SHORT_LENGTH_MARKER:
        head = struct.pack("!BB", first, mask_bit | length)
    elif length < 1 << 16:
        head = struct.pack("!BBH", first, mask_bit | SHORT_LENGTH_MARKER, length)
    else:
        head = struct.pack("!BBQ", first, mask_bit | LONG_LENGTH_MARKER, length)
    if not mask:
        return head + payload
    key = os.urandom(4)
    return head + key + _xor(payload, key)


def close_payload(code, reason=""):
    return struct.pack("!H", code) + reason.encode()[:CONTROL_LIMIT - 2]


def parse_close(payload):
    if len(payload) < 2:
        return None, ""
    return struct.unpack("!H", payload[:2])[0], payload[2:].decode(errors="replace")


def _xor(data, key):
    if not data:
        return b""
    stream = (key * (len(data) // 4 + 1))[:len(data)]
    return (int.from_bytes(data, "big") ^ int.from_bytes(stream, "big")).to_bytes(len(data), "big")


def _read_exact(stream, count):
    data = stream.read(count)
    if data is None or len(data) < count:
        raise ConnectionEnded()
    return data


def _read_frame(stream, limit):
    first, second = _read_exact(stream, 2)
    fin, opcode, masked, length = bool(first & 0x80), first & 0x0F, bool(second & 0x80), second & 0x7F
    if first & 0x70:
        raise ProtocolError("reserved bits set")
    if length == SHORT_LENGTH_MARKER:
        length = struct.unpack("!H", _read_exact(stream, 2))[0]
    elif length == LONG_LENGTH_MARKER:
        length = struct.unpack("!Q", _read_exact(stream, 8))[0]
    is_control = opcode >= OP_CLOSE
    if is_control and (length > CONTROL_LIMIT or not fin):
        raise ProtocolError("bad control frame")
    if length > limit:
        raise TooBig(length)
    key = _read_exact(stream, 4) if masked else None
    payload = _read_exact(stream, length) if length else b""
    return fin, opcode, masked, (_xor(payload, key) if key else payload)


def read_message(stream, limit, require_masked=None):
    """Reads one whole message from a file-like stream. Returns (opcode, payload); ping and pong frames are returned as they are.
    require_masked True (server side) refuses unmasked frames; False (client side) refuses masked ones."""
    opcode, parts, total = None, [], 0
    while True:
        fin, code, masked, payload = _read_frame(stream, limit)
        if require_masked is not None and masked != require_masked:
            raise ProtocolError("wrong masking")
        if code >= OP_CLOSE:
            return code, payload
        if (code == OP_CONTINUATION) == (opcode is None):
            raise ProtocolError("bad fragment order")
        opcode = code if opcode is None else opcode
        total += len(payload)
        if total > limit:
            raise TooBig(total)
        parts.append(payload)
        if fin:
            return opcode, b"".join(parts)


class Client:
    """A blocking client for the checks. connect() returns a Refusal when the server answered the upgrade with an ordinary HTTP reply."""

    def __init__(self, sock, stream, leftover_headers=None):
        self.sock, self.stream = sock, stream
        self.headers = leftover_headers or {}
        self.close_code, self.close_reason = None, ""

    @classmethod
    def connect(cls, port, path, headers=None, host="127.0.0.1", timeout=10):
        sock = socket.create_connection((host, port), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        sent = {"Host": f"{host}:{port}", "Upgrade": "websocket", "Connection": "Upgrade", "Sec-WebSocket-Key": key, "Sec-WebSocket-Version": "13"}
        sent.update(headers or {})
        sock.sendall((f"GET {path} HTTP/1.1\r\n" + "".join(f"{k}: {v}\r\n" for k, v in sent.items()) + "\r\n").encode())
        stream = sock.makefile("rb")
        status_line = stream.readline().decode(errors="replace").strip()
        status = int(status_line.split(" ")[1]) if status_line.count(" ") >= 1 else 0
        reply_headers = {}
        while (line := stream.readline().decode(errors="replace").strip()):
            name, _, value = line.partition(":")
            reply_headers[name.strip().lower()] = value.strip()
        if status != 101:
            length = int(reply_headers.get("content-length", "0") or 0)
            body = stream.read(length) if length else b""
            sock.close()
            return Refusal(status, reply_headers, body)
        if reply_headers.get("sec-websocket-accept") != accept_key(key):
            sock.close()
            return Refusal(101, reply_headers, b"bad accept key")
        return cls(sock, stream, reply_headers)

    def send_binary(self, data):
        self.sock.sendall(encode_frame(OP_BINARY, data, mask=True))

    def send_text(self, text):
        self.sock.sendall(encode_frame(OP_TEXT, text.encode(), mask=True))

    def send_close(self, code=CLOSE_NORMAL, reason=""):
        self.sock.sendall(encode_frame(OP_CLOSE, close_payload(code, reason), mask=True))

    def recv(self, limit=1 << 24):
        """Next message as (opcode, payload); answers pings. A close frame comes back as (OP_CLOSE, payload) and sets close_code / close_reason.
        Returns (None, b'') when the socket ended without a close frame."""
        while True:
            try:
                opcode, payload = read_message(self.stream, limit, require_masked=False)
            except (ConnectionEnded, ConnectionError, OSError):
                return None, b""
            if opcode == OP_PING:
                self.sock.sendall(encode_frame(OP_PONG, payload, mask=True))
                continue
            if opcode == OP_PONG:
                continue
            if opcode == OP_CLOSE:
                self.close_code, self.close_reason = parse_close(payload)
            return opcode, payload

    def read_until(self, needle, seconds=10):
        """Collects binary output until `needle` (bytes or a compiled bytes regex) appears. Returns everything read. Raises if the socket closes or time runs out."""
        deadline = time.time() + seconds
        seen = b""
        self.sock.settimeout(1)
        while not _found(needle, seen):
            if time.time() > deadline:
                raise AssertionError(f"never saw {needle!r}; got {seen[-200:]!r}")
            try:
                opcode, payload = self.recv()
            except socket.timeout:
                continue
            if opcode is None or opcode == OP_CLOSE:
                raise AssertionError(f"socket closed (code {self.close_code}) before {needle!r}; got {seen[-200:]!r}")
            if opcode == OP_BINARY:
                seen += payload
        return seen

    def wait_for_close(self, seconds=10):
        """Reads until the server closes. Returns (code, reason); code None means the socket just ended."""
        deadline = time.time() + seconds
        self.sock.settimeout(1)
        while time.time() < deadline:
            try:
                opcode, _ = self.recv()
            except socket.timeout:
                continue
            if opcode is None or opcode == OP_CLOSE:
                return self.close_code, self.close_reason
        raise AssertionError("the server never closed the socket")

    def close(self):
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.stream.close()
        self.sock.close()


def _found(needle, seen):
    return needle.search(seen) is not None if hasattr(needle, "search") else needle in seen


class Refusal:
    """The upgrade was refused with a normal HTTP reply."""

    def __init__(self, status, headers, body):
        self.status, self.headers, self.raw = status, headers, body
        try:
            self.body = json.loads(body) if body else None
        except ValueError:
            self.body = None
