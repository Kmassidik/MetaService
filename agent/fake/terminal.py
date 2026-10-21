"""The console of the Fake Agent: GET /v1/workloads/{id}/terminal as a WebSocket, /bin/sh in a real pty on this host."""
import fcntl
import json
import os
import pty
import select
import signal
import struct
import subprocess
import termios
import threading

from contract import wsproto

SHELL = "/bin/sh"
MAX_FRAME_BYTES = 65536
COLS_RANGE, ROWS_RANGE = range(1, 501), range(1, 301)
START_SIZE = (80, 24)
POLL_SECONDS = 0.2
READ_BYTES = 4096


class Consoles:
    """Which workloads have a console open; at most one each."""

    def __init__(self):
        self._open, self._lock = set(), threading.Lock()

    def claim(self, workload_id):
        with self._lock:
            if workload_id in self._open:
                return False
            self._open.add(workload_id)
            return True

    def is_open(self, workload_id):
        with self._lock:
            return workload_id in self._open

    def release(self, workload_id):
        with self._lock:
            self._open.discard(workload_id)


def parse_resize(payload):
    """Returns (cols, rows) from a text frame, or None when it is anything but a valid resize."""
    try:
        message = json.loads(payload)
        cols, rows = message["resize"]
    except (ValueError, KeyError, TypeError):
        return None
    if set(message) != {"resize"} or not all(type(n) is int for n in (cols, rows)):
        return None
    return (cols, rows) if cols in COLS_RANGE and rows in ROWS_RANGE else None


def set_size(fd, cols, rows):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def start_shell():
    """Starts the shell on a new pty. Returns (process, master fd)."""
    master, slave = pty.openpty()
    set_size(master, *START_SIZE)
    process = subprocess.Popen([SHELL], stdin=slave, stdout=slave, stderr=slave, start_new_session=True, close_fds=True,
                               preexec_fn=lambda: fcntl.ioctl(0, termios.TIOCSCTTY, 0), env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "TERM": "xterm-256color"})
    os.close(slave)
    return process, master


def kill_shell(process, master):
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()
    try:
        os.close(master)
    except OSError:
        pass


class Session:
    """One open console. run() blocks until it ends; the shell is always dead afterwards."""

    def __init__(self, sock, stream, still_running):
        self.sock, self.stream, self.still_running = sock, stream, still_running
        self.process, self.master = start_shell()
        self.ended = threading.Event()
        self._send_lock = threading.Lock()
        self._closing = False

    def run(self):
        threading.Thread(target=self._client_to_shell, daemon=True).start()
        try:
            self._shell_to_client()
        finally:
            self.ended.set()
            kill_shell(self.process, self.master)

    def _send(self, opcode, payload):
        with self._send_lock:
            try:
                self.sock.sendall(wsproto.encode_frame(opcode, payload))
            except OSError:
                self.ended.set()

    def _close(self, code, reason):
        with self._send_lock:
            if self._closing:
                return
            self._closing = True
        self._send_close_frame(code, reason)
        self.ended.set()

    def _send_close_frame(self, code, reason):
        with self._send_lock:
            try:
                self.sock.sendall(wsproto.encode_frame(wsproto.OP_CLOSE, wsproto.close_payload(code, reason)))
            except OSError:
                pass

    def _shell_to_client(self):
        while not self.ended.is_set():
            if not self.still_running():
                return self._close(wsproto.CLOSE_NORMAL, "the VM stopped")
            ready, _, _ = select.select([self.master], [], [], POLL_SECONDS)
            if not ready:
                continue
            try:
                data = os.read(self.master, READ_BYTES)
            except OSError:
                data = b""
            if not data:
                return self._close(wsproto.CLOSE_NORMAL, "the shell ended")
            self._send(wsproto.OP_BINARY, data)

    def _client_to_shell(self):
        while not self.ended.is_set():
            try:
                opcode, payload = wsproto.read_message(self.stream, MAX_FRAME_BYTES, require_masked=True)
            except wsproto.TooBig:
                return self._close(wsproto.CLOSE_POLICY, "frame too large")
            except wsproto.ProtocolError:
                return self._close(wsproto.CLOSE_PROTOCOL, "protocol error")
            except (wsproto.ConnectionEnded, OSError):
                return self.ended.set()
            if not self._handle(opcode, payload):
                return

    def _handle(self, opcode, payload):
        """Applies one message. Returns False when the session is over."""
        if opcode == wsproto.OP_PING:
            self._send(wsproto.OP_PONG, payload)
        elif opcode == wsproto.OP_PONG:
            pass
        elif opcode == wsproto.OP_CLOSE:
            self._close(wsproto.CLOSE_NORMAL, "")
            return False
        elif opcode == wsproto.OP_BINARY:
            self._type(payload)
        else:
            return self._resize(payload)
        return True

    def _type(self, payload):
        try:
            os.write(self.master, payload)
        except OSError:
            self.ended.set()

    def _resize(self, payload):
        size = parse_resize(payload)
        if size is None:
            self._close(wsproto.CLOSE_POLICY, "not a valid resize")
            return False
        set_size(self.master, *size)
        return True
