"""Current helpers scan on startup and retain the completed map after restart."""
from contract.agent_tests.support import CheckFailed, RunningAgent, wait_for


def check_storage_starts_without_storage_tab_and_survives_restart():
    running = RunningAgent().start()
    try:
        def initial_progress():
            status, body = running.call("GET", "/v1/storage")
            if status != 200:
                raise CheckFailed(f"GET /v1/storage returned {status}")
            if body["scanning"] or body["map"] is not None:
                return body
            return None

        first = wait_for(initial_progress, 20, "no Storage scan started without a Storage tab POST")
        wait_for(lambda: _completed(running), 600, "the automatic Storage scan did not finish")
        _, completed = running.call("GET", "/v1/storage")
        finished_at = completed["map"]["finished_at"]

        running.stop()
        running.start()
        status, restored = running.call("GET", "/v1/storage")
        if status != 200:
            raise CheckFailed(f"GET after restart returned {status}")
        if restored["scanning"]:
            raise CheckFailed("a completed map caused another startup scan")
        if restored["map"] is None or restored["map"]["finished_at"] != finished_at:
            raise CheckFailed("the completed map did not survive the helper restart")
    finally:
        running.stop()


def _completed(running):
    _, body = running.call("GET", "/v1/storage")
    if not body["scanning"] and body["map"] is not None:
        return body
    return None


CHECKS = [check_storage_starts_without_storage_tab_and_survives_restart]
