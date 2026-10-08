"""Rate limits, lockout, oversized input and a Root that survives rude clients."""
from contract.root_tests.support import Browser, enrolled_machine, expect, good_heartbeat, raw_exchange, running

BIG_BODY_BYTES = 70 * 1024


def check_enroll_attempts_are_rate_limited():
    with running() as root:
        agent = Browser(root)
        codes = [agent.request("POST", "/v1/agents/enroll", {"enrollment_token": "z" * 43, "name": "dgx"}, origin=None).status for _ in range(12)]
        expect(codes[:10] == [401] * 10 and codes[10:] == [429, 429], f"enroll status codes: {codes}")


def check_bad_machine_tokens_lock_the_address_out():
    with running() as root:
        operator = Browser(root)
        token = enrolled_machine(operator, "mini")
        agent = Browser(root)
        codes = [agent.request("POST", "/v1/agents/heartbeat", good_heartbeat(), headers={"Authorization": f"Bearer wrong-{i}"}, origin=None).status for i in range(12)]
        expect(codes[:10] == [401] * 10 and 429 in codes[10:], f"bad-token codes: {codes}")
        good = agent.request("POST", "/v1/agents/heartbeat", good_heartbeat(), headers={"Authorization": f"Bearer {token}"}, origin=None)
        expect(good.status == 429, f"the lockout let a correct token through: {good.status}")


def check_login_attempts_are_rate_limited():
    env = "ALLOWED_EMAILS=kurnia@example.com\nGOOGLE_CLIENT_ID=test-client\nGOOGLE_CLIENT_SECRET=test-secret\n"
    with running(env_text=env) as root:
        browser = Browser(root)
        codes = [browser.request("GET", "/auth/login").status for _ in range(33)]
        expect(codes[:30] == [302] * 30 and 429 in codes[30:], f"login codes: {codes}")


def check_oversized_bodies_get_413():
    with running() as root:
        operator = Browser(root)
        operator.sign_in()
        big = b'{"name":"' + b"a" * BIG_BODY_BYTES + b'"}'
        expect(operator.write("POST", "/api/enrollments", raw=big).status == 413, "a 70 KB operator body was not refused")
        expect(Browser(root).request("POST", "/v1/agents/enroll", raw=big, origin=None).status == 413, "a 70 KB enroll body was not refused")


def check_a_huge_declared_length_is_refused_at_once():
    with running() as root:
        request = (b"POST /v1/agents/enroll HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n"
                   b"Content-Length: 99999999999\r\nConnection: close\r\n\r\n{}")
        answer = raw_exchange(root, request, wait=3.0)
        expect(answer.startswith(b"HTTP/1.1 413") or answer.startswith(b"HTTP/1.1 400"), f"huge Content-Length: {answer[:60]!r}")
        expect(Browser(root).request("GET", "/health").status == 200, "the Root died after a huge Content-Length")


def check_a_huge_header_does_not_hurt():
    with running() as root:
        request = b"GET /health HTTP/1.1\r\nHost: localhost\r\nX-Big: " + b"a" * (300 * 1024) + b"\r\nConnection: close\r\n\r\n"
        answer = raw_exchange(root, request, wait=3.0)
        expect(not answer.startswith(b"HTTP/1.1 200"), f"a 300 KB header was accepted: {answer[:40]!r}")
        expect(Browser(root).request("GET", "/health").status == 200, "the Root died after a huge header")


def check_garbage_and_half_requests_do_not_kill_the_root():
    with running() as root:
        for payload in (b"\x00\x01\x02garbage\r\n\r\n", b"GET", b"POST /v1/agents/enroll HTTP/1.1\r\nContent-Length: 50\r\n\r\n{", b"G" * 100000):
            raw_exchange(root, payload, wait=0.5)
        expect(Browser(root).request("GET", "/health").status == 200, "the Root stopped answering after garbage input")


def check_conflicting_content_lengths_are_refused():
    with running() as root:
        request = (b"POST /v1/agents/enroll HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2\r\nContent-Length: 40\r\nConnection: close\r\n\r\n{}")
        answer = raw_exchange(root, request, wait=2.0)
        expect(not answer.startswith(b"HTTP/1.1 200") and not answer.startswith(b"HTTP/1.1 401"), f"conflicting lengths were processed: {answer[:50]!r}")


CHECKS = [
    check_enroll_attempts_are_rate_limited, check_bad_machine_tokens_lock_the_address_out, check_login_attempts_are_rate_limited,
    check_oversized_bodies_get_413, check_a_huge_declared_length_is_refused_at_once, check_a_huge_header_does_not_hurt,
    check_garbage_and_half_requests_do_not_kill_the_root, check_conflicting_content_lengths_are_refused,
]
