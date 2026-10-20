"""Remote access for MetaService: reach the panel from outside through Cloudflare, on a tunnel of its own.

  python3 scripts/remote_access check    read-only: is everything ready?
  python3 scripts/remote_access plan     read-only: what `up` would make
  python3 scripts/remote_access up       make the tunnel, the route, the DNS record and the connector
  python3 scripts/remote_access status   is it connected and answering?
  python3 scripts/remote_access down     remove exactly what `up` made

Options: --env FILE  --host NAME (a throwaway name for a first test)  --tunnel-name NAME  --origin URL  --state-dir DIR
It never prints the API token. The tunnel is this tool's own; another project's tunnel (MAAS's) is never read or changed.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONTROL_PLANE = os.path.normpath(os.path.join(HERE, "..", "..", "control-plane", "arm64"))
sys.path.insert(0, HERE)

import cf_api  # noqa: E402
import cf_commands  # noqa: E402
import cf_connector  # noqa: E402
import cf_env  # noqa: E402
import cf_probe  # noqa: E402
import cf_state  # noqa: E402


def parse(argv):
    parser = argparse.ArgumentParser(prog="remote_access", description="Reach the MetaService panel from outside through Cloudflare.")
    parser.add_argument("command", choices=("check", "plan", "up", "status", "down"))
    parser.add_argument("--env", default=os.path.join(CONTROL_PLANE, ".env"))
    parser.add_argument("--state-dir", default=os.path.join(CONTROL_PLANE, "state"))
    parser.add_argument("--host", default="")
    parser.add_argument("--origin", default="")
    parser.add_argument("--tunnel-name", default="")
    parser.add_argument("--api-base", default=cf_api.PRODUCTION_BASE, help="for tests only: a local fake server")
    return parser.parse_args(argv)


def remembered_host(args):
    """`down` and `status` work on what was made, so they use its host even if PUBLIC_BASE_URL has been emptied since."""
    if args.command not in ("down", "status") or args.host:
        return args.host
    return (cf_state.load(args.state_dir) or {}).get("host", "")


def main(argv):
    args = parse(argv)
    try:
        settings = cf_env.settings_from(cf_env.load_env(args.env), remembered_host(args), args.origin, args.tunnel_name)
        api = cf_api.CloudflareApi(settings.token, args.api_base)
    except (cf_env.SettingsError, cf_api.CloudflareError) as failure:
        print(f"Cannot start: {failure}", file=sys.stderr)
        return cf_commands.EXIT_PROBLEMS
    # The two overrides are for tests, so a test run can never touch a real connector on a machine where remote access is working.
    launchctl = os.environ.get("METASERVICE_LAUNCHCTL", "launchctl")
    agents_dir = os.environ.get("METASERVICE_AGENTS_DIR", os.path.expanduser("~/Library/LaunchAgents"))
    tool = cf_commands.Tool(settings, api, cf_probe.status_of, cf_connector.Launchd(os.getuid(), program=launchctl), args.state_dir, agents_dir)
    return getattr(tool, args.command)()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
