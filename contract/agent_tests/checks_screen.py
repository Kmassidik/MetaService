"""Screen control on the macOS Agent: off unless turned on, the same token as everything else, strict input, a real picture back."""
import http.client
import json

from contract.agent_tests.support import agent
from contract.root_tests.support import expect

PNG_HEADER = b"\x89PNG\r\n\x1a\n"


def fetch(running, method, path, body=None, token="default"):
    use = running.token if token == "default" else token
    headers = {"Authorization": f"Bearer {use}"} if use else {}
    data = None if body is None else json.dumps(body).encode()
    if data is not None:
        headers["Content-Type"] = "application/json"
    connection = http.client.HTTPConnection("127.0.0.1", running.port, timeout=15)
    connection.request(method, path, body=data, headers=headers)
    response = connection.getresponse()
    raw = response.read()
    connection.close()
    return response.status, response.getheader("Content-Type"), raw


def event(**more):
    return {"events": [more]}


def check_screen_control_is_off_unless_it_was_turned_on():
    with agent() as running:
        status, _, raw = fetch(running, "GET", "/v1/screen")
        expect(status == 200 and json.loads(raw)["access"] == "off", f"status: {status} {raw[:100]!r}")
        status, _, raw = fetch(running, "GET", "/v1/screen/frame")
        expect(status == 403 and json.loads(raw)["error"]["code"] == "screen_not_allowed", f"frame while off: {status} {raw[:100]!r}")
        status, _, _ = fetch(running, "POST", "/v1/screen/input", event(type="move", x=1, y=1))
        expect(status == 403, f"input while off: {status}")


def check_the_screen_needs_the_machine_token():
    with agent(extra=["--screen", "simulated"]) as running:
        for token in (None, "wrong-token"):
            expect(fetch(running, "GET", "/v1/screen", token=token)[0] == 401, f"status with token {token!r}")
            expect(fetch(running, "GET", "/v1/screen/frame", token=token)[0] == 401, f"frame with token {token!r}")
            expect(fetch(running, "POST", "/v1/screen/input", event(type="move", x=1, y=1), token=token)[0] == 401, f"input with token {token!r}")


def check_a_picture_comes_back_and_follows_the_pointer():
    with agent(extra=["--screen", "simulated"]) as running:
        status, kind, first = fetch(running, "GET", "/v1/screen/frame")
        expect(status == 200 and kind == "image/png" and first.startswith(PNG_HEADER), f"frame: {status} {kind} {first[:12]!r}")
        expect(json.loads(fetch(running, "GET", "/v1/screen")[2])["access"] == "ready", "status says ready")
        expect(fetch(running, "POST", "/v1/screen/input", event(type="move", x=5000, y=5000))[0] == 204, "move accepted")
        expect(fetch(running, "GET", "/v1/screen/frame")[2] != first, "the picture did not change after moving the pointer")


def check_input_is_read_strictly():
    with agent(extra=["--screen", "simulated"]) as running:
        bad = [event(type="move", x=10001, y=0), event(type="key", code=500, down=True), event(type="nope"), {"events": [{"type": "move", "x": 1, "y": 1}] * 65}, {"events": "x"}]
        for body in bad:
            status, _, raw = fetch(running, "POST", "/v1/screen/input", body)
            expect(status == 400, f"expected 400 for {str(body)[:60]}: {status} {raw[:80]!r}")


CHECKS = [check_screen_control_is_off_unless_it_was_turned_on, check_the_screen_needs_the_machine_token, check_a_picture_comes_back_and_follows_the_pointer, check_input_is_read_strictly]
