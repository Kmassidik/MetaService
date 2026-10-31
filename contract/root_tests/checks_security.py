"""The Security page routes GET /api/security/overview and GET /api/security/events, the separate security.sqlite3, and the parent's puller, against a real Root and
fake helpers (agent/fake/security.py) that serve GET /v1/security/events. Rules: contract/openapi.yaml, docs/PRD-security-page.md."""
import copy
import sqlite3
import threading
import time
from datetime import datetime, timedelta, timezone

from agent.fake.engine import FakeEngine
from agent.fake.security import BASELINE, BLOCKED_NOW_ADDRESS, EVENTS_IN_LOG, FAILED_BY_ADDRESS, FAILED_BY_USER, FAILED_TOTAL, HOSTILE_USER, FakeSecurity
from agent.fake.server import make_server
from contract import spec
from contract.root_tests.checks_monitor import enroll
from contract.root_tests.support import Browser, expect, good_heartbeat, running

FAST_POLL = "SECURITY_POLL_SECONDS=1\n"
WAIT_SECONDS = 20
PAUSE_SECONDS = 0.3
QUIET_SECONDS = 3.5
DAY = timedelta(days=1)
RETENTION_DAYS = 90
FAILED_ROWS = (5, 6)  # the fake log has 5 failed-login groups; the one that spans two events splits in two when midnight UTC falls between them


class SecurityHelper:
    """A fake helper on loopback with a security log the test can see and change."""

    def __init__(self, token, log=None):
        self.security = FakeSecurity(log)
        self.server = make_server(FakeEngine(), token, "127.0.0.1", 0, security=self.security)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def stop(self):
        self.server.shutdown()
        self.server.server_close()


def heartbeat(root, machine_token, port, security):
    body = copy.deepcopy(good_heartbeat())
    body["agent_port"] = port
    if security:
        body["facts"]["capabilities"]["security"] = True
    reply = Browser(root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {machine_token}"}, origin=None)
    expect(reply.status == 204, f"heartbeat gave {reply.status}: {reply.raw[:150]!r}")


def add_machine(operator, root, name, security=True, log=None):
    machine_token, command_token = enroll(operator, name)
    helper = SecurityHelper(command_token, log=log)
    heartbeat(root, machine_token, helper.port, security)
    helper.token = machine_token
    return helper


def overview(operator, query=""):
    reply = operator.request("GET", f"/api/security/overview{query}")
    expect(reply.status == 200, f"overview gave {reply.status}: {reply.raw[:200]!r}")
    problems = spec.problems("SecurityOverview", reply.body)
    expect(not problems, f"the overview does not fit the contract: {problems[:3]}")
    return reply.body


def events(operator, query=""):
    reply = operator.request("GET", f"/api/security/events{query}")
    expect(reply.status == 200, f"events gave {reply.status}: {reply.raw[:200]!r}")
    problems = spec.problems("SecurityEventsPage", reply.body)
    expect(not problems, f"the events do not fit the contract: {problems[:3]}")
    return reply.body


def line(body, machine):
    found = [item for item in body["machines"] if item["machine"] == machine]
    expect(len(found) == 1, f"{machine} is not once in the overview: {body['machines']}")
    return found[0]


def wait_until_reported(operator, machine, query=""):
    deadline = time.time() + WAIT_SECONDS
    while time.time() < deadline:
        body = overview(operator, query)
        if line(body, machine)["reported"]:
            return body
        time.sleep(PAUSE_SECONDS)
    raise AssertionError(f"{machine} was not reported within {WAIT_SECONDS} s: {line(overview(operator, query), machine)}")


def wait_for_failed(operator, machine, wanted):
    deadline = time.time() + WAIT_SECONDS
    while time.time() < deadline:
        if line(overview(operator), machine)["failed"] == wanted:
            return
        time.sleep(PAUSE_SECONDS)
    raise AssertionError(f"{machine} did not reach {wanted} failed logins: {line(overview(operator), machine)}")


def all_events(operator, query):
    rows, page = [], 1
    while True:
        body = events(operator, f"{query}&page={page}&page_size=100")
        rows += body["events"]
        if len(rows) >= body["total"]:
            return rows
        page += 1


def check_the_security_routes_need_the_session_and_the_right_host_and_refuse_bad_queries():
    with running() as root:
        operator = Browser(root)
        for path in ("/api/security/overview", "/api/security/events"):
            expect(Browser(root, auto_login=False).request("GET", path).status == 401, f"{path}: no session must be 401")
            expect(operator.request("GET", path, headers={"Host": "evil.example"}).status == 403, f"{path}: a foreign Host must be 403")
            expect(operator.request("POST", path, {}).status in (403, 404, 405), f"{path}: a read, POST must not work")
            expect(operator.request("POST", path, {}, origin="http://evil.example").status in (403, 404, 405), f"{path}: a foreign Origin must be refused")
        bad = ["?range=1y", "?range=", "?range=7d&range=30d", "?machine=A%20B", "?type=nope", "?page=0", "?page=05", "?page=-1", "?page_size=101", "?page_size=0",
               "?page_size=2.5", f"?q={'a' * 65}", "?q=a%01b", "?sort=time", "?machine="]
        for query in bad:
            reply = operator.request("GET", f"/api/security/events{query}")
            expect(reply.status == 400 and reply.body["error"]["code"] == "invalid_input", f"events{query} gave {reply.status}: {reply.raw[:120]!r}")
            expect(not spec.problems("Error", reply.body), f"events{query}: not the plain error shape")
        for query in ("?range=1y", "?machine=a", "?range=7d&range=7d"):
            expect(operator.request("GET", f"/api/security/overview{query}").status == 400, f"overview{query} must be 400")
        for good in ("?range=24h", "?range=90d&page=2&page_size=100&type=login&q=abc&machine=a-b"):
            events(operator, good)


def check_before_any_poll_every_machine_is_not_watched_with_no_numbers():
    with running() as root:
        operator = Browser(root)
        watched = add_machine(operator, root, "sec-watched")
        old = add_machine(operator, root, "sec-old", security=False)
        try:
            body = overview(operator)
            expect(body["range"] == "7d" and len(body["machines"]) == 2, f"two machines and the default range: {body}")
            for machine in ("sec-watched", "sec-old"):
                item = line(body, machine)
                expect(item["reported"] is False and item["last_reported"] is None and item["failed"] is None and item["blocked"] is None, f"{machine}: no data, no zeros: {item}")
                expect(all(value is None for value in item["baseline"].values()), f"{machine}: an all-null baseline: {item['baseline']}")
            expect(body["blocked_now"] == [] and body["top_users"] == [] and body["top_addresses"] == [] and body["daily"] == [], f"no data yet: {body}")
            expect(events(operator) == {"events": [], "total": 0, "page": 1, "page_size": 25}, "an empty log")
            expect(watched.security.calls == [] and old.security.calls == [], "the parent must not ask before a poll is due")
        finally:
            watched.stop()
            old.stop()


def check_after_a_poll_the_numbers_match_the_fake_log_and_the_text_is_clean():
    with running(env_text=FAST_POLL) as root:
        operator = Browser(root)
        helper = add_machine(operator, root, "sec-a")
        old = add_machine(operator, root, "sec-old", security=False)
        try:
            body = wait_until_reported(operator, "sec-a")
            item = line(body, "sec-a")
            expect(item["failed"] == FAILED_TOTAL and item["blocked"] == 2, f"numbers: {item}")
            expect(item["baseline"] == BASELINE, f"baseline: {item['baseline']}")
            expect(datetime.fromisoformat(item["last_reported"].replace("Z", "+00:00")) > datetime.now(timezone.utc) - timedelta(minutes=1), "last_reported is recent")
            expect({row["name"]: row["count"] for row in body["top_users"]} == FAILED_BY_USER, f"top users: {body['top_users']}")
            expect({row["name"]: row["count"] for row in body["top_addresses"]} == FAILED_BY_ADDRESS, f"top addresses: {body['top_addresses']}")
            expect(body["top_users"][0]["name"] == "root", "most tried first")
            expect(sum(row["failed"] for row in body["daily"]) == FAILED_TOTAL and all(row["machine"] == "sec-a" for row in body["daily"]), f"daily: {body['daily']}")
            expect(len(body["blocked_now"]) == 1, f"one address blocked now: {body['blocked_now']}")
            blocked = body["blocked_now"][0]
            expect(blocked["address"] == BLOCKED_NOW_ADDRESS and blocked["machine"] == "sec-a" and blocked["until"] and blocked["attempts"] == FAILED_BY_ADDRESS[BLOCKED_NOW_ADDRESS], f"blocked now: {blocked}")
            expect(line(body, "sec-old")["reported"] is False and line(body, "sec-old")["failed"] is None, "a machine without the capability is not watched")
            time.sleep(QUIET_SECONDS)
            expect(old.security.calls == [], f"the parent must not ask a helper that does not say security: {old.security.calls}")
            expect(line(overview(operator, "?range=24h"), "sec-a")["failed"] == FAILED_TOTAL, "the 24 h range holds the whole fake log")
        finally:
            helper.stop()
            old.stop()


def check_the_event_log_filters_pages_newest_first_and_shows_clean_text():
    with running(env_text=FAST_POLL) as root:
        operator = Browser(root)
        helper = add_machine(operator, root, "sec-a")
        try:
            wait_until_reported(operator, "sec-a")
            everything = all_events(operator, "?range=7d")
            expect(EVENTS_IN_LOG - 1 <= len(everything) <= EVENTS_IN_LOG, f"the log: {len(everything)} rows")
            times = [row["time"] for row in everything]
            expect(times == sorted(times, reverse=True), f"newest first: {times}")
            failed = [row for row in everything if row["type"] == "failed_login"]
            expect(sum(row["count"] for row in failed) == FAILED_TOTAL and len(failed) in FAILED_ROWS, f"failed rows: {failed}")
            expect(all(row["count"] is None for row in everything if row["type"] != "failed_login"), "only failed logins carry a count")
            expect(events(operator, "?type=login")["total"] == 2 and events(operator, "?type=blocked")["total"] == 2 and events(operator, "?type=unblocked")["total"] == 1, "types")
            expect(events(operator, "?type=failed_login")["total"] == len(failed), "failed_login filter")
            methods = sorted(row["method"] for row in everything if row["type"] == "login")
            expect(methods == ["key", "password"], f"login methods: {methods}")
            expect([row["user"] for row in events(operator, "?q=KURN")["events"]] == ["kurnia", "kurnia"], "q finds a user, not case sensitive")
            expect(events(operator, "?q=91.200")["total"] in (4,), "q finds an address")
            expect(events(operator, "?q=%25")["total"] == 0 and events(operator, "?q=_")["total"] == 0, "% and _ are plain characters")
            expect(events(operator, "?machine=nobody")["total"] == 0 and events(operator, "?machine=sec-a")["total"] == len(everything), "machine filter")
            first, second = events(operator, "?page_size=3&page=1"), events(operator, "?page_size=3&page=2")
            expect(first["total"] == second["total"] == len(everything) and first["page_size"] == 3 and second["page"] == 2, "paging numbers")
            expect(not {row["id"] for row in first["events"]} & {row["id"] for row in second["events"]}, "pages do not overlap")
            expect(events(operator, "?page=999")["events"] == [], "past the end is an empty page")
            hostile = [row for row in everything if row["user"] == HOSTILE_USER]
            expect(len(hostile) == 1, "hostile markup is plain text and comes back as it is")
            cleaned = [row for row in everything if row["user"] == "bad user"]
            expect(len(cleaned) == 1 and cleaned[0]["address"] is None, f"control characters are gone and a bad address is dropped: {cleaned}")
            text = "".join(str(value) for row in everything for value in (row["user"], row["address"], row["detail"]) if value)
            expect(not any(ord(character) < 32 for character in text), "no control characters in any text")
        finally:
            helper.stop()


def check_a_failing_or_silent_helper_never_breaks_the_others_and_new_events_count_once():
    with running(env_text=FAST_POLL) as root:
        operator = Browser(root)
        broken = add_machine(operator, root, "sec-broken")
        silent = add_machine(operator, root, "sec-silent")
        good = add_machine(operator, root, "sec-good")
        broken.security.set_mode("error")
        silent.security.set_mode("hang")
        try:
            body = wait_until_reported(operator, "sec-good")
            expect(line(body, "sec-broken")["reported"] is False and line(body, "sec-silent")["reported"] is False, "failing machines stay not watched")
            expect(line(body, "sec-broken")["failed"] is None, "no zeros for a machine that never answered")
            broken.security.set_mode("ok")
            wait_until_reported(operator, "sec-broken")
            expect(line(overview(operator), "sec-broken")["failed"] == FAILED_TOTAL, "it recovers and is counted once")
            good.security.append({"type": "failed_login", "user": "root", "address": "45.13.2.9", "count": 4})
            wait_for_failed(operator, "sec-good", FAILED_TOTAL + 4)
            time.sleep(QUIET_SECONDS)
            expect(line(overview(operator), "sec-good")["failed"] == FAILED_TOTAL + 4, "asking again from the cursor never counts twice")
        finally:
            for helper in (broken, silent, good):
                helper.stop()


def check_a_restart_keeps_the_cursor_and_a_reset_deletes_nothing():
    with running(env_text=FAST_POLL) as root:
        operator = Browser(root)
        helper = add_machine(operator, root, "sec-a")
        try:
            wait_until_reported(operator, "sec-a")
            time.sleep(QUIET_SECONDS)
            root.stop()
            before = len(helper.security.calls)
            root.start()
            operator = Browser(root)
            time.sleep(QUIET_SECONDS)
            asked = helper.security.calls[before:]
            expect(asked and all(f"after=g1-{EVENTS_IN_LOG}" in call for call in asked), f"after a restart the parent asks from the stored cursor: {asked}")
            expect(line(overview(operator), "sec-a")["failed"] == FAILED_TOTAL, "no double counting after a restart")
            helper.security.rotate()
            helper.security.append({"type": "failed_login", "user": "root", "address": "45.13.2.9", "count": 1})
            deadline = time.time() + WAIT_SECONDS
            while time.time() < deadline and line(overview(operator), "sec-a")["failed"] < FAILED_TOTAL * 2 + 1:
                time.sleep(PAUSE_SECONDS)
            now = line(overview(operator), "sec-a")["failed"]
            expect(now >= FAILED_TOTAL, f"a reset keeps what was stored and starts afresh with the new log: {now}")
        finally:
            helper.stop()


def check_retention_deletes_rows_older_than_ninety_days_at_start():
    with running(env_text=FAST_POLL) as root:
        operator = Browser(root)
        helper = add_machine(operator, root, "sec-a")
        try:
            wait_until_reported(operator, "sec-a")
            root.stop()
            now = datetime.now(timezone.utc)
            old, young = now - (RETENTION_DAYS + 10) * DAY, now - (RETENTION_DAYS - 1) * DAY
            stamp = lambda moment: moment.strftime("%Y-%m-%dT%H:%M:%SZ")  # noqa: E731
            database = sqlite3.connect(f"{root.dir}/security.sqlite3")
            database.execute("INSERT INTO events (time, machine, type, count) VALUES (?, 'gone', 'login', 1)", (stamp(old),))
            database.execute("INSERT INTO events (time, machine, type, count) VALUES (?, 'gone', 'login', 1)", (stamp(young),))
            for moment in (old, young):
                database.execute("INSERT INTO failed_daily (day, machine, count, last_seen) VALUES (?, 'gone', 9, ?)", (stamp(moment)[:10], stamp(moment)))
            database.commit()
            database.close()
            root.start()
            database = sqlite3.connect(f"{root.dir}/security.sqlite3")
            gone_events = database.execute("SELECT time FROM events WHERE machine = 'gone'").fetchall()
            gone_failed = database.execute("SELECT day FROM failed_daily WHERE machine = 'gone'").fetchall()
            others = database.execute("SELECT COUNT(*) FROM events WHERE machine = 'sec-a'").fetchone()[0]
            database.close()
            expect(gone_events == [(stamp(young),)] and gone_failed == [(stamp(young)[:10],)], f"only the young rows are left: {gone_events} {gone_failed}")
            expect(others > 0, "the machine that is still watched keeps its history")
        finally:
            helper.stop()


CHECKS = [
    check_the_security_routes_need_the_session_and_the_right_host_and_refuse_bad_queries,
    check_before_any_poll_every_machine_is_not_watched_with_no_numbers,
    check_after_a_poll_the_numbers_match_the_fake_log_and_the_text_is_clean,
    check_the_event_log_filters_pages_newest_first_and_shows_clean_text,
    check_a_failing_or_silent_helper_never_breaks_the_others_and_new_events_count_once,
    check_a_restart_keeps_the_cursor_and_a_reset_deletes_nothing,
    check_retention_deletes_rows_older_than_ninety_days_at_start,
]
