"""Control a machine's screen through the parent: opening needs the machine to allow it, tickets belong to their operator, control is a separate confirmed step, everything is audited."""
import json

from contract.root_tests.checks_remote import authorize_parent, remote
from contract.root_tests.checks_remote_install import add_body, box_folder, start_install, wait_for_job
from contract.root_tests.support import Browser, expect

PNG_HEADER = b"\x89PNG\r\n\x1a\n"


def installed(operator, server, **more):
    authorize_parent(operator, server)
    job = wait_for_job(operator, start_install(operator, add_body(server, box_folder(), **more)).body["id"])
    expect(job["state"] == "done", f"install: {job.get('error')} {job['steps']}")


def frame(operator, ticket):
    reply = operator.request("GET", f"/api/screen/{ticket}/frame")
    return reply.status, reply.raw


def check_a_machine_that_did_not_allow_screen_control_refuses_to_open_one():
    with remote() as (root, operator, server):
        installed(operator, server)
        status = operator.request("GET", "/api/machines/test-box/screen")
        expect(status.status == 200 and status.body["access"] == "off", f"status: {status.status} {status.raw[:100]!r}")
        refused = operator.write("POST", "/api/machines/test-box/screen")
        expect(refused.status == 409 and refused.body["error"]["code"] == "screen_not_ready", f"open: {refused.status} {refused.raw[:140]!r}")
        expect(operator.write("POST", "/api/machines/nobody/screen").status == 404, "a machine that does not exist")


def check_the_screen_is_seen_then_controlled_only_after_the_second_step():
    with remote() as (root, operator, server):
        installed(operator, server, allow_screen=True)
        opened = operator.write("POST", "/api/machines/test-box/screen")
        expect(opened.status == 201 and opened.body["mode"] == "view", f"open: {opened.status} {opened.raw[:140]!r}")
        ticket = opened.body["ticket"]
        status, first = frame(operator, ticket)
        expect(status == 200 and first.startswith(PNG_HEADER), f"frame: {status} {first[:10]!r}")
        move = {"events": [{"type": "move", "x": 5000, "y": 5000}]}
        viewing = operator.write("POST", f"/api/screen/{ticket}/input", move)
        expect(viewing.status == 403 and viewing.body["error"]["code"] == "view_only", f"input while viewing: {viewing.status} {viewing.raw[:100]!r}")
        expect(operator.write("POST", f"/api/screen/{ticket}/control", {"confirm": False}).status == 400, "control without the confirm")
        expect(operator.write("POST", f"/api/screen/{ticket}/control", {"confirm": True}).body["mode"] == "control", "control switched on")
        expect(operator.write("POST", f"/api/screen/{ticket}/input", move).status == 204, "input after control")
        expect(frame(operator, ticket)[1] != first, "the picture did not follow the pointer")
        expect(operator.write("POST", f"/api/screen/{ticket}/input", {"events": [{"type": "move", "x": 99999, "y": 0}]}).status == 400, "the machine's own checks apply")
        second = operator.write("POST", "/api/machines/test-box/screen")
        expect(second.status == 409 and second.body["error"]["code"] == "screen_in_use", f"a second screen on the same machine: {second.status}")
        expect(operator.write("DELETE", f"/api/screen/{ticket}").status == 204, "close")
        expect(frame(operator, ticket)[0] == 404, "a closed ticket gives nothing")
        actions = [entry["action"] for entry in operator.request("GET", "/api/audit?limit=50").body["entries"]]
        expect(all(name in actions for name in ("screen.open", "screen.control", "screen.close")), f"audit: {actions}")
        expect(ticket not in json.dumps(operator.request("GET", "/api/audit?limit=50").body), "the ticket must not be in the audit log")


def check_a_ticket_and_the_screen_calls_need_the_operators_login():
    with remote() as (root, operator, server):
        installed(operator, server, allow_screen=True)
        ticket = operator.write("POST", "/api/machines/test-box/screen").body["ticket"]
        stranger = Browser(root, auto_login=False)
        expect(stranger.request("GET", f"/api/screen/{ticket}/frame").status == 401, "frame without a login")
        expect(stranger.request("GET", "/api/machines/test-box/screen").status == 401, "status without a login")
        expect(stranger.request("POST", "/api/machines/test-box/screen").status in (401, 403), "open without a login")
        expect(operator.request("POST", f"/api/screen/{ticket}/input", {"events": []}).status == 403, "a write without the CSRF token")


def check_removing_the_machine_closes_its_screen():
    with remote() as (root, operator, server):
        installed(operator, server, allow_screen=True)
        ticket = operator.write("POST", "/api/machines/test-box/screen").body["ticket"]
        expect(operator.write("POST", "/api/remote/machines/test-box/remove", {"use_key": True}).status == 204, "removal")
        expect(frame(operator, ticket)[0] == 404, "the screen of a removed machine must be closed")


CHECKS = [check_a_machine_that_did_not_allow_screen_control_refuses_to_open_one, check_the_screen_is_seen_then_controlled_only_after_the_second_step,
          check_a_ticket_and_the_screen_calls_need_the_operators_login, check_removing_the_machine_closes_its_screen]
