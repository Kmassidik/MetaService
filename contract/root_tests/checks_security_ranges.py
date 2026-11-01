"""The short ranges of the Security page (1 h, 6 h, 12 h, 24 h) read the ten-minute failed_buckets of security.sqlite3. Rules: contract/openapi.yaml, docs/PRD-security-page.md."""
import sqlite3
import time
from datetime import datetime, timedelta, timezone

from agent.fake.security import FAILED_BY_ADDRESS, FAILED_TOTAL
from contract.root_tests.checks_security import FAST_POLL, QUIET_SECONDS, add_machine, events, line, overview, wait_for_failed, wait_until_reported
from contract.root_tests.support import Browser, expect, running

BUCKET_MINUTES = 10
BUCKET_RETENTION_DAYS = 8
SHORT_RANGES = ("1h", "6h", "12h", "24h")
LONG_RANGES = ("7d", "30d", "90d")
LAST_HOUR_FAILED = 2  # only the failed-login group 20 minutes ago of the fake log falls in the last hour
LAST_HOUR_BLOCKED = 1  # the block 55 minutes ago; the one 60 minutes ago is just outside
MORE_FAILED = 4
BAD_RANGES = ("2h", "48h", "1H", "0h", "")


def stamp(moment):
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def on_ten_minute_mark(row):
    moment = datetime.strptime(row["start"], "%Y-%m-%dT%H:%M:%SZ")
    return moment.minute % BUCKET_MINUTES == 0 and moment.second == 0


def check_security_ranges_refuse_bad_values_and_accept_the_short_ones():
    with running() as root:
        operator = Browser(root)
        for name in SHORT_RANGES + LONG_RANGES:
            expect(overview(operator, f"?range={name}")["range"] == name, f"range {name} is accepted")
            events(operator, f"?range={name}")
        for name in BAD_RANGES:
            expect(operator.request("GET", f"/api/security/overview?range={name}").status == 400, f"overview range={name!r} must be 400")
            expect(operator.request("GET", f"/api/security/events?range={name}").status == 400, f"events range={name!r} must be 400")
        body = overview(operator, "?range=1h")
        expect(body["buckets"] == [] and body["bucket_minutes"] == BUCKET_MINUTES and body["daily"] == [], f"no data: an empty chart and no zeros: {body}")


def check_security_short_ranges_show_the_new_totals_and_buckets_and_long_ones_stay_as_before():
    with running(env_text=FAST_POLL) as root:
        operator = Browser(root)
        helper = add_machine(operator, root, "sec-a")
        old = add_machine(operator, root, "sec-old", security=False)
        try:
            wait_until_reported(operator, "sec-a")
            hour = overview(operator, "?range=1h")
            item = line(hour, "sec-a")
            expect(item["failed"] == LAST_HOUR_FAILED and item["blocked"] == LAST_HOUR_BLOCKED, f"1 h numbers: {item}")
            expect(hour["bucket_minutes"] == BUCKET_MINUTES and hour["daily"] == [], f"1 h has buckets and no days: {hour}")
            expect(len(hour["buckets"]) == 1 and hour["buckets"][0]["failed"] == LAST_HOUR_FAILED and hour["buckets"][0]["machine"] == "sec-a", f"1 h buckets: {hour['buckets']}")
            expect(all(on_ten_minute_mark(row) for row in hour["buckets"]), "buckets start on ten-minute marks")
            expect(hour["top_users"] == [{"name": "root", "count": LAST_HOUR_FAILED}], f"1 h top users: {hour['top_users']}")
            expect(hour["top_addresses"] == [{"name": "45.13.2.9", "count": LAST_HOUR_FAILED}], f"1 h top addresses: {hour['top_addresses']}")
            expect(line(hour, "sec-old")["failed"] is None, "a machine that is not watched has no numbers")
            rows = events(operator, "?range=1h&type=failed_login")["events"]
            expect(len(rows) == 1 and rows[0]["count"] == LAST_HOUR_FAILED, f"1 h log: {rows}")
            for name in ("6h", "12h", "24h"):
                body = overview(operator, f"?range={name}")
                expect(line(body, "sec-a")["failed"] == FAILED_TOTAL, f"{name} holds the whole fake log: {line(body, 'sec-a')}")
                expect(sum(row["failed"] for row in body["buckets"]) == FAILED_TOTAL and body["daily"] == [], f"{name} buckets add up: {body['buckets']}")
                expect({row["name"]: row["count"] for row in body["top_addresses"]} == FAILED_BY_ADDRESS, f"{name} top addresses")
                expect(all(row["failed"] > 0 and on_ten_minute_mark(row) for row in body["buckets"]), f"{name}: no zero bucket")
            expect(line(overview(operator, "?range=6h"), "sec-a")["blocked"] == 2, "6 h holds both blocks")
            week = overview(operator, "?range=7d")
            expect(week["buckets"] == [] and sum(row["failed"] for row in week["daily"]) == FAILED_TOTAL, f"7 d keeps the day counts: {week['daily']}")
            expect(line(week, "sec-a")["failed"] == FAILED_TOTAL, "7 d total as before")
            helper.security.append({"type": "failed_login", "user": "root", "address": "45.13.2.9", "count": MORE_FAILED})
            wait_for_failed(operator, "sec-a", FAILED_TOTAL + MORE_FAILED)
            time.sleep(QUIET_SECONDS)
            expect(line(overview(operator, "?range=1h"), "sec-a")["failed"] == LAST_HOUR_FAILED + MORE_FAILED, "a live event is added once to the last hour")
        finally:
            helper.stop()
            old.stop()


def check_retention_deletes_buckets_older_than_eight_days_at_start():
    with running(env_text=FAST_POLL) as root:
        operator = Browser(root)
        helper = add_machine(operator, root, "sec-a")
        try:
            wait_until_reported(operator, "sec-a")
            root.stop()
            now = datetime.now(timezone.utc)
            old, young = now - timedelta(days=BUCKET_RETENTION_DAYS + 1), now - timedelta(days=BUCKET_RETENTION_DAYS - 1)
            database = sqlite3.connect(f"{root.dir}/security.sqlite3")
            for moment in (old, young):
                database.execute("INSERT INTO failed_buckets (bucket_start, machine, count, last_seen) VALUES (?, 'gone', 9, ?)", (stamp(moment), stamp(moment)))
            database.commit()
            database.close()
            root.start()
            database = sqlite3.connect(f"{root.dir}/security.sqlite3")
            left = database.execute("SELECT bucket_start FROM failed_buckets WHERE machine = 'gone'").fetchall()
            version = database.execute("SELECT MAX(version) FROM schema_version").fetchone()[0]
            database.close()
            expect(left == [(stamp(young),)], f"only the young bucket is left: {left}")
            expect(version >= 2, f"the migration ran: {version}")
        finally:
            helper.stop()


CHECKS = [
    check_security_ranges_refuse_bad_values_and_accept_the_short_ones,
    check_security_short_ranges_show_the_new_totals_and_buckets_and_long_ones_stay_as_before,
    check_retention_deletes_buckets_older_than_eight_days_at_start,
]
