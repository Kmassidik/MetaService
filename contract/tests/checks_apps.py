"""PUT /v1/workloads/{id}/app: installs OpenClaw or Hermes inside one running VM. Real helpers are never asked to run an installer here:
the install checks use the Fake Agent's test switch and are skipped by a helper that does not have it."""
from contract.tests.support import expect, expect_error, expect_schema

APPS = ("openclaw", "hermes")
UNKNOWN_WORKLOAD = "nope-nothing-here"
MAX_LOG_LINES = 12
MAX_LOG_LINE_CHARACTERS = 200


def _path(workload_id):
    return f"/v1/workloads/{workload_id}/app"


def _put(ctx, workload_id, body, **kwargs):
    return ctx.client.request("PUT", _path(workload_id), body, **kwargs)


def _stopped_workload(ctx):
    workload_id, _ = ctx.create_small()
    stopped = ctx.post(f"/v1/workloads/{workload_id}/stop")
    expect(stopped.status == 202, f"stop gave {stopped.status}")
    ctx.wait_for(stopped.body["command_id"])
    return workload_id


def _fake_switch(ctx, mode, delay_seconds=0):
    """True when the target is the Fake Agent (it has the test switch); a real helper answers 404 and is never asked to install anything."""
    return ctx.post("/fake/app-install", {"mode": mode, "delay_seconds": delay_seconds}).status == 204


def check_app_needs_the_token(ctx):
    workload_id, _ = ctx.create_small()
    for token in (None, "wrong-token"):
        expect_error(_put(ctx, workload_id, {"app": "openclaw"}, token=token), 401, f"app with token {token!r}")


def check_app_unknown_vm_is_404(ctx):
    expect_error(_put(ctx, UNKNOWN_WORKLOAD, {"app": "openclaw"}), 404, "app of an unknown VM")


def check_app_bad_bodies_are_400(ctx):
    workload_id, _ = ctx.create_small()
    bad_bodies = {
        "an unknown app": {"app": "evil"},
        "a path as the app": {"app": "../openclaw"},
        "an upper case app": {"app": "OpenClaw"},
        "no app": {},
        "an extra field": {"app": "openclaw", "url": "http://evil.example/install.sh"},
        "an app that is not text": {"app": 1},
        "an app that is a list": {"app": ["openclaw"]},
        "a body that is not an object": ["openclaw"],
    }
    for label, body in bad_bodies.items():
        reply = _put(ctx, workload_id, body)
        expect_error(reply, 400, f"app with {label}")
        expect(reply.body["error"]["code"] == "invalid_input", f"{label}: wrong code {reply.body}")


def check_app_body_that_is_not_json_is_400(ctx):
    workload_id, _ = ctx.create_small()
    expect_error(ctx.client.request("PUT", _path(workload_id), raw=b"{not json"), 400, "app with a body that is not JSON")


def check_app_stopped_vm_is_409_not_running(ctx):
    reply = _put(ctx, _stopped_workload(ctx), {"app": "openclaw"})
    expect_error(reply, 409, "app of a stopped VM")
    expect(reply.body["error"]["code"] == "not_running", f"wrong code {reply.body}")


def check_app_installs_once_and_then_changes_nothing(ctx):
    if not _fake_switch(ctx, "works"):
        return
    workload_id, _ = ctx.create_small()
    for app in APPS:
        first, second = _put(ctx, workload_id, {"app": app}), _put(ctx, workload_id, {"app": app})
        for reply in (first, second):
            expect(reply.status == 200, f"{app} install gave {reply.status}: {reply.body}")
            expect_schema("AppInstalled", reply.body, f"{app} install")
            expect(reply.body["app"] == app, f"wrong app in {reply.body}")
        expect(first.body["installed"] is True, f"the first {app} install must say installed: {first.body}")
        expect(second.body["installed"] is False, f"the second {app} install must change nothing: {second.body}")


def check_app_failure_is_502_with_message_and_a_short_log(ctx):
    if not _fake_switch(ctx, "fails"):
        return
    try:
        workload_id, _ = ctx.create_small()
        reply = _put(ctx, workload_id, {"app": "hermes"})
        expect(reply.status == 502, f"a failed install gave {reply.status}: {reply.body}")
        expect_schema("AppInstallError", reply.body, "failed install")
        error = reply.body["error"]
        expect(len(error["log_tail"]) <= MAX_LOG_LINES, "too many log lines")
        expect(all(len(line) <= MAX_LOG_LINE_CHARACTERS for line in error["log_tail"]), "a log line is too long")
    finally:
        _fake_switch(ctx, "works")


def check_app_is_forgotten_with_the_vm(ctx):
    if not _fake_switch(ctx, "works"):
        return
    workload_id, _ = ctx.create_small()
    expect(_put(ctx, workload_id, {"app": "openclaw"}).body["installed"] is True, "the first install must say installed")
    deleted = ctx.delete(f"/v1/workloads/{workload_id}")
    expect(deleted.status == 202, f"delete gave {deleted.status}")
    ctx.wait_for(deleted.body["command_id"])
    expect_error(_put(ctx, workload_id, {"app": "openclaw"}), 404, "app of a deleted VM")


def check_images_says_ready_for_the_apps_a_helper_can_install(ctx):
    reply = ctx.get("/v1/images")
    expect(reply.status == 200, f"images gave {reply.status}")
    expect_schema("HelperImages", reply.body, "images")
    ready = {image["id"]: image["ready"] for image in reply.body["images"]}
    for app in APPS:
        expect(ready.get(app) is True, f"a helper with the app route must say ready for {app}: {ready}")


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
