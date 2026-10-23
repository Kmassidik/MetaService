"""Apps on top of a VM (OpenClaw, Hermes) as the Fake Agent plays them: an in-memory set of what is installed in which VM, and a test switch for how an install goes."""
APP_NAMES = ("openclaw", "hermes")
APP_CAPTION = "Installs after the VM starts, about 2 minutes"
# What a helper of this build says in GET /v1/images for each app.
APP_IMAGES = [{"id": name, "ready": True, "built_at": None, "caption": APP_CAPTION} for name in APP_NAMES]
FAKE_VERSION = "2026.10.1"
FAKE_INSTALLER_SHA256 = "0123456789abcdef" * 4
FAILURE_MESSAGE = "The installer could not download the app. Check that the VM has internet access."
FAILURE_LOG_TAIL = ["Downloading the installer", "curl: (6) Could not resolve host", "Install aborted"]
MODES = ("works", "fails")


class AppInstallFailed(Exception):
    """The installer ran inside the VM and failed; carries the plain reason and the last lines it printed."""

    def __init__(self, message, log_tail):
        super().__init__(message)
        self.message, self.log_tail = message, list(log_tail)


class FakeApps:
    def __init__(self):
        self.mode = "works"
        self.delay_seconds = 0.0
        # Per VM, the apps now installed in it.
        self._installed = {}
        # How many installs actually ran, so a test can tell "once" from "again".
        self.installs = 0

    def set_install(self, mode, delay_seconds):
        self.mode = mode
        self.delay_seconds = float(delay_seconds)

    def installed_in(self, workload_id):
        return sorted(self._installed.get(workload_id, ()))

    def forget(self, workload_id):
        self._installed.pop(workload_id, None)

    def already_there(self, workload_id, app):
        return app in self._installed.get(workload_id, ())

    def answer(self, app, installed):
        return {"app": app, "installed": installed, "version": FAKE_VERSION, "installer_sha256": FAKE_INSTALLER_SHA256}

    def finish_installer(self, workload_id, app):
        """The end of the installer: it either installed the app or failed."""
        if self.mode == "fails":
            raise AppInstallFailed(FAILURE_MESSAGE, FAILURE_LOG_TAIL)
        self._installed.setdefault(workload_id, set()).add(app)
        self.installs += 1
        return self.answer(app, True)
