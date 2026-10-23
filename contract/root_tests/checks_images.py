"""The ready-made images, against a real Root and fake helpers: the catalog route GET /api/images, the per-machine route GET /api/machines/{id}/images (guards, the merge,
an older helper, a machine that is offline, a helper that lies) and the optional `bundle` on POST /api/workloads (unknown 400, planned 409, blank or nothing as before,
a free `image` name from the browser refused and never forwarded)."""
import threading

from agent.fake.engine import BLANK_IMAGE, FakeEngine, MachineSpec
from agent.fake.server import make_server
from contract import spec
from contract.root_tests.checks_monitor import NoStatsHelper, beat, enroll
from contract.root_tests.support import Browser, expect, running

MACHINE = "mini"
CATALOG_PATH = "/api/images"
MACHINE_PATH = f"/api/machines/{MACHINE}/images"
CATALOG_IDS = ["blank", "openclaw", "hermes"]
COMING_SOON = "Coming soon: needs the image to be prepared on the machine"
WAITING_FOR_PIN = "Waiting for a pinned release and checksum"
VM = {"kind": "vm", "cpu": 1, "ram_mb": 1024, "disk_gb": 5}
HOSTILE_ID = "evil-image"
UPDATE_HELPER = "Update the helper on this machine first"


class ImageHelper:
    """A fake helper on loopback that keeps every request it accepted, so a test can see what the parent really sent."""

    def __init__(self, token, machine_spec=None):
        self.engine = FakeEngine(machine_spec or MachineSpec())
        self.server = make_server(self.engine, token, "127.0.0.1", 0)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def stop(self):
        self.server.shutdown()
        self.server.server_close()


def machine_with_helper(operator, root, machine_spec=None):
    machine_token, command_token = enroll(operator, MACHINE)
    helper = ImageHelper(command_token, machine_spec)
    beat(root, machine_token, helper.port)
    return helper


def machine_images_of(operator, machine_spec):
    """What the panel route says for a machine whose helper is built as `machine_spec` says (a second machine, so the first one stays as it is)."""
    machine_token, command_token = enroll(operator, "other")
    helper = ImageHelper(command_token, machine_spec)
    try:
        beat(operator.root, machine_token, helper.port)
        reply = operator.request("GET", "/api/machines/other/images")
        expect(reply.status == 200, f"machine images gave {reply.status}")
        return reply.body["images"]
    finally:
        helper.stop()


def machine_images(operator):
    reply = operator.request("GET", MACHINE_PATH)
    expect(reply.status == 200, f"machine images gave {reply.status}: {reply.raw[:200]!r}")
    problems = spec.problems("MachineImages", reply.body)
    expect(not problems, f"the reply does not fit the contract: {problems[:3]}")
    return reply.body


def by_id(images):
    return {image["id"]: image for image in images}


def create(operator, **changes):
    return operator.write("POST", "/api/workloads", {"name": "pic", "machine": MACHINE, **VM, **changes})


def check_the_image_routes_need_the_session_and_the_right_host_and_know_their_machines():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            for path in (CATALOG_PATH, MACHINE_PATH):
                expect(Browser(root, auto_login=False).request("GET", path).status == 401, f"{path}: no session must be 401")
                expect(operator.request("GET", path, headers={"Host": "evil.example"}).status == 403, f"{path}: a foreign Host must be 403")
                expect(operator.request("POST", path, {}).status in (403, 404, 405), f"{path}: it is a read, POST must not work")
            expect(operator.request("GET", "/api/machines/nobody/images").status == 404, "an unknown machine must be 404")
            expect(operator.request("GET", "/api/machines/BAD%20ID/images").status == 404, "a malformed id must be 404")
        finally:
            helper.stop()


def check_the_catalog_lists_blank_openclaw_and_hermes_with_plain_reasons_and_nothing_pinned():
    with running() as root:
        operator = Browser(root)
        reply = operator.request("GET", CATALOG_PATH)
        expect(reply.status == 200, f"catalog gave {reply.status}")
        problems = spec.problems("ImageCatalog", reply.body)
        expect(not problems, f"the catalog does not fit the contract: {problems[:3]}")
        images = reply.body["images"]
        expect([image["id"] for image in images] == CATALOG_IDS, f"ids: {[image['id'] for image in images]}")
        expect([image["state"] for image in images] == ["ready", "planned", "planned"], "only blank can be chosen today")
        expect([image["reason"] for image in images] == [None, COMING_SOON, WAITING_FOR_PIN], f"reasons: {[image['reason'] for image in images]}")
        expect(not any("sha256" in image or "pinned_version" in image for image in images), "pins stay on the parent")


def check_the_machine_route_merges_the_catalog_with_what_the_helper_has():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            body = machine_images(operator)
            expect(body["helper"] == "answered", f"helper: {body['helper']}")
            images = by_id(body["images"])
            expect(images["blank"]["ready"] and images["blank"]["available"] and images["blank"]["reason"] is None, f"blank: {images['blank']}")
            for app in ("openclaw", "hermes"):
                expect(images[app]["ready"] and images[app]["available"] and images[app]["reason"] is None, f"{app} is installed after the VM starts, so a helper that says ready makes it selectable: {images[app]}")
            old = by_id(machine_images_of(operator, MachineSpec(serves_apps=False)))
            for app in ("openclaw", "hermes"):
                expect(not old[app]["available"] and old[app]["reason"] == UPDATE_HELPER, f"{app} on a helper that does not report ready: {old[app]}")
        finally:
            helper.stop()


def check_a_helper_that_names_a_stranger_or_says_an_app_is_not_ready_changes_nothing_for_the_panel():
    claims = [dict(BLANK_IMAGE), {"id": "openclaw", "ready": False, "built_at": None}, {"id": HOSTILE_ID, "ready": True, "built_at": None}]
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root, MachineSpec(images=claims, serves_apps=False))
        try:
            body = machine_images(operator)
            expect([image["id"] for image in body["images"]] == CATALOG_IDS, "a name outside the catalog must never reach the panel")
            expect(by_id(body["images"])["openclaw"]["available"] is False, "an app the helper says is not ready cannot be chosen")
        finally:
            helper.stop()


def check_an_older_helper_without_the_route_means_only_blank():
    with running() as root:
        operator = Browser(root)
        machine_token, _ = enroll(operator, MACHINE)
        helper = NoStatsHelper()
        try:
            beat(root, machine_token, helper.port)
            body = machine_images(operator)
            expect(body["helper"] == "old_helper", f"helper: {body['helper']}")
            expect(by_id(body["images"])["blank"]["available"] is True, "blank works on every helper")
        finally:
            helper.stop()


def check_a_helper_that_answers_garbage_or_a_machine_that_never_reported_means_only_blank():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root, MachineSpec(images=[{"id": "Bad Id", "ready": "yes"}]))
        try:
            body = machine_images(operator)
            expect(body["helper"] == "unreachable", f"garbage: {body['helper']}")
            expect(by_id(body["images"])["blank"]["available"] is True, "blank still works")
        finally:
            helper.stop()
    with running() as root:
        operator = Browser(root)
        enroll(operator, MACHINE)
        body = machine_images(operator)
        expect(body["helper"] == "unreachable" and by_id(body["images"])["blank"]["available"], f"never reported: {body['helper']}")


def check_creating_with_blank_or_nothing_is_todays_request_and_sends_no_bundle_to_the_helper():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            for name, extra in (("none", {}), ("blank", {"bundle": "blank"}), ("null", {"bundle": None})):
                reply = create(operator, name=f"vm-{name}", **extra)
                expect(reply.status == 202, f"{name}: create gave {reply.status}: {reply.raw[:200]!r}")
            sent = helper.engine.created_requests
            expect(len(sent) == 3, f"the helper should have been asked three times: {len(sent)}")
            expect(all("bundle" not in request and "image" not in request for request in sent), f"nothing extra may reach the helper: {sent}")
        finally:
            helper.stop()


def check_an_app_the_helper_cannot_install_is_a_409_in_plain_words_and_nothing_is_started():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root, MachineSpec(serves_apps=False))
        try:
            for bundle, reason in (("openclaw", UPDATE_HELPER), ("hermes", UPDATE_HELPER)):
                reply = create(operator, bundle=bundle)
                error = (reply.body or {}).get("error", {})
                expect(reply.status == 409 and error.get("code") == "image_not_available" and error.get("message") == reason, f"{bundle}: {reply.status} {reply.body}")
            expect(helper.engine.created_requests == [], "a refused image must not reach the helper")
            commands = operator.request("GET", "/api/commands").body["commands"]
            expect(commands == [], f"a refused image must not leave a command behind: {commands}")
        finally:
            helper.stop()


def check_an_unknown_or_malformed_bundle_is_a_400_in_the_plain_shape():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            for bad in ("nope", "Blank", "../etc", "ubuntu:24.04", "", "x" * 33, 5, True, ["blank"], {"id": "blank"}):
                reply = create(operator, bundle=bad)
                expect(reply.status == 400 and reply.body["error"]["code"] == "invalid_input", f"bundle {bad!r}: {reply.status} {reply.body}")
            expect(helper.engine.created_requests == [], "a refused bundle must not reach the helper")
        finally:
            helper.stop()


def check_a_free_image_name_from_the_browser_is_refused_and_never_reaches_the_helper():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            for image in ("ubuntu:24.04", "docker.io/library/ubuntu:24.04", "images:ubuntu/24.04", "--privileged", ""):
                reply = create(operator, image=image)
                expect(reply.status == 400 and reply.body["error"]["code"] == "invalid_input", f"image {image!r}: {reply.status} {reply.body}")
            expect(helper.engine.created_requests == [], "a browser-supplied image must never reach the helper")
        finally:
            helper.stop()


def check_only_the_machines_own_saved_default_image_is_ever_forwarded():
    saved = "images:ubuntu/24.04"
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            expect(operator.write("PATCH", f"/api/machines/{MACHINE}/settings", {"vm_image": saved}).status == 200, "the machine setting was not saved")
            expect(create(operator).status == 202, "create failed")
            expect([request.get("image") for request in helper.engine.created_requests] == [saved], f"sent: {helper.engine.created_requests}")
        finally:
            helper.stop()


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
