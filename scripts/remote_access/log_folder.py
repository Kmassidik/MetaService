"""Where MetaService keeps its log files: one folder, `logs/`, at the top of the repository."""
import os

LOG_FOLDER = "logs"
LOG_DIR_VARIABLE = "METASERVICE_LOG_DIR"  # for tests and odd installs: the folder to use instead of <root>/logs
CONNECTOR_LOG = "cloudflared.log"
PARENT_LOG = "parent.log"
WATCHDOG_LOG = "watchdog.log"


def log_dir(root: str) -> str:
    return os.environ.get(LOG_DIR_VARIABLE) or os.path.join(root, LOG_FOLDER)
