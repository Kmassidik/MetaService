"""Add machine, Verify: the security baseline shown before anything is installed. The other computer is the pretend Debian of fakes/fake_linux.py (its security look
prints canned lines, as the real script would) or a plain replaying server; a failing or hostile look must never fail the check."""
from contract.root_tests.checks_remote import authorize_parent, remote, rows, verify_body
from contract.root_tests.checks_remote_fix import fake_computer
from contract.root_tests.support import expect

KEYS = ["password_login", "ban_tool", "firewall", "auto_updates", "pending_updates", "has_key_login"]
ALL_UNKNOWN = {key: None for key in KEYS}
PLAIN_LINUX = "os=Linux\narch=x86_64\nuser=build\nhome=/home/build\nversion=Ubuntu 24.04.1 LTS\nchip=Intel Xeon\ncpu=8\nram_mb=32108\nkvm=yes\ndisk_free_gb=412\ntool=curl\nsudo=none\nport_9101=free\n"
UBUNTU_FRESH = {"password_login": True, "ban_tool": "not_running", "firewall": False, "auto_updates": False, "pending_updates": 4, "has_key_login": True}
MAC_HARDENED = "password_login=no\nban_tool=not_available\nfirewall=yes\nauto_updates=yes\nhas_key_login=yes\npending_updates=0\n"


def verify(operator, server):
    reply = operator.write("POST", "/api/remote/verify", verify_body(server))
    expect(reply.status == 200, f"verify: {reply.status} {reply.raw[:300]!r}")
    return reply


def check_verify_shows_the_security_baseline_of_a_fresh_ubuntu():
    with fake_computer() as (root, operator, server):
        reply = verify(operator, server)
        expect(reply.body["security"] == UBUNTU_FRESH, f"security: {reply.body.get('security')}")
        expect(server.security_runs() == 1, f"the look runs once per check, over its own login: {server.commands()!r}")
        expect("starts_after_reboot" not in reply.body["security"], "the helper is not installed yet, so it is not asked")


def check_a_hardened_mac_answer_is_shown_as_it_is_with_no_ban_tool_available():
    with fake_computer() as (root, operator, server):
        server.security(MAC_HARDENED)
        security = verify(operator, server).body["security"]
        expect(security == {"password_login": False, "ban_tool": "not_available", "firewall": True, "auto_updates": True, "pending_updates": 0, "has_key_login": True}, f"security: {security}")


def check_a_missing_key_and_an_unknown_answer_are_not_turned_into_yes_or_no():
    with fake_computer() as (root, operator, server):
        server.security("password_login=unknown\nhas_key_login=no\nfirewall=unknown\npending_updates=unknown\n")
        security = verify(operator, server).body["security"]
        expect(security == {**ALL_UNKNOWN, "has_key_login": False}, f"security: {security}")


def check_hostile_output_of_the_look_is_ignored_and_verify_still_works():
    with fake_computer() as (root, operator, server):
        hostile = "password_login=yes; reboot\nban_tool=$(id)\nfirewall=\x1b[31myes\nauto_updates=" + "y" * 9000 + "\nevil_key=yes\npending_updates=-1\nhas_key_login=`id`\n" + "x" * 100000 + "\n"
        server.security(hostile)
        reply = verify(operator, server)
        expect(reply.body["security"] == ALL_UNKNOWN, f"security: {reply.body['security']}")
        expect(reply.body["facts"]["os"] == "Linux" and "evil_key" not in reply.raw.decode() and "\x1b" not in reply.raw.decode(), "nothing hostile is passed on")


def check_a_failing_look_never_fails_verify():
    with fake_computer() as (root, operator, server):
        server.state("security_fails")
        reply = verify(operator, server)
        expect(reply.body["security"] == ALL_UNKNOWN, f"a look that fails is all unknown: {reply.body['security']}")
        expect(list(rows(reply))[:2] == ["login", "system"] and reply.body["facts"]["user"] == "build", "the rest of the check is the same")


def check_a_computer_that_answers_every_login_with_the_same_facts_has_an_unknown_baseline():
    with remote(answer=PLAIN_LINUX) as (root, operator, server):
        authorize_parent(operator, server)
        reply = verify(operator, server)
        expect(reply.body["security"] == ALL_UNKNOWN, f"security: {reply.body['security']}")


def check_a_windows_computer_has_no_security_object():
    with fake_computer() as (root, operator, server):
        server.state("windows")
        reply = verify(operator, server)
        expect("security" not in reply.body, f"windows: {sorted(reply.body)}")


CHECKS = [check_verify_shows_the_security_baseline_of_a_fresh_ubuntu, check_a_hardened_mac_answer_is_shown_as_it_is_with_no_ban_tool_available,
          check_a_missing_key_and_an_unknown_answer_are_not_turned_into_yes_or_no, check_hostile_output_of_the_look_is_ignored_and_verify_still_works,
          check_a_failing_look_never_fails_verify, check_a_computer_that_answers_every_login_with_the_same_facts_has_an_unknown_baseline,
          check_a_windows_computer_has_no_security_object]
