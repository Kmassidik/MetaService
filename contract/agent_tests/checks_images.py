"""The helper's images route: GET /v1/images (which ready-made images this machine has prepared). Runs against the real macOS and Linux helpers and, with
`python -m contract.agent_tests.runner --fake`, against the Fake Agent. The create-with-`bundle` checks need a helper that accepts the field, so only the Fake Agent runs them."""
from contract import spec
from contract.agent_tests.checks_terminal import helper
from contract.root_tests.support import expect

IMAGES = "/v1/images"
STOCK_IMAGE = "blank"
VM = {"kind": "vm", "cpu": 1, "ram_mb": 512, "disk_gb": 1}


def check_images_needs_the_command_token():
    with helper() as one:
        expect(one.call("GET", IMAGES, token=None)[0] == 401, "no token must be 401")
        expect(one.call("GET", IMAGES, token="wrong-" + one.token)[0] == 401, "a wrong token must be 401")


def check_images_answers_the_contract_shape_and_the_stock_image_is_ready():
    with helper() as one:
        status, body = one.call("GET", IMAGES)
        expect(status == 200, f"images gave {status}: {body}")
        problems = spec.problems("HelperImages", body)
        expect(not problems, f"the answer does not fit the contract: {problems[:3]}")
        stock = [image for image in body["images"] if image["id"] == STOCK_IMAGE]
        expect(len(stock) == 1 and stock[0]["ready"] is True, f"blank must be listed once and ready: {body}")
        expect(stock[0]["built_at"] is None, "the stock image has no build time")


def check_images_is_read_only():
    with helper() as one:
        for method in ("POST", "DELETE"):
            status = one.call(method, IMAGES, {} if method == "POST" else None)[0]
            expect(status in (404, 405), f"{method} {IMAGES} gave {status}: the route can only look")


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]


def fake_only_accepts_a_catalog_id_as_bundle_and_records_it():
    with helper() as one:
        for name, bundle in (("a", "openclaw"), ("b", "blank")):
            status, body = one.call("POST", "/v1/workloads", {"command_id": f"c-{name}", "name": f"vm-{name}", "bundle": bundle, **VM})
            expect(status == 202, f"a create with bundle {bundle} gave {status}: {body}")
        recorded = [request.get("bundle") for request in one.server.RequestHandlerClass.engine.created_requests]
        expect(recorded == ["openclaw", "blank"], f"the helper should have recorded the bundles it was given: {recorded}")


def fake_only_refuses_a_bundle_that_is_not_an_id():
    with helper() as one:
        for bad in ("Bad Id", "--privileged", "a b", "", "x" * 33, 5, ["blank"]):
            status = one.call("POST", "/v1/workloads", {"command_id": "c-bad", "name": "bad", "bundle": bad, **VM})[0]
            expect(status == 400, f"bundle {bad!r} must be a 400, got {status}")


def fake_only_a_create_without_bundle_is_recorded_without_one():
    with helper() as one:
        expect(one.call("POST", "/v1/workloads", {"command_id": "c-plain", "name": "plain", **VM})[0] == 202, "a plain create must still work")
        recorded = one.server.RequestHandlerClass.engine.created_requests
        expect("bundle" not in recorded[0], f"nothing was asked for, nothing should be recorded: {recorded[0]}")


FAKE_CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("fake_only_")]
