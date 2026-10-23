"""The remote-access commands: check, plan, up, status, down.

`up` records everything it makes in the state file as it goes, so a failure half way (or `down` later) removes exactly what exists and
nothing else. Nothing here prints a token or an id: only the hostname, the tunnel's name and plain sentences.
"""
from __future__ import annotations

import os
import time

import cf_connector
import cf_ingress
import cf_state
import log_folder
from cf_api import CloudflareError
from cf_probe import reached

EXIT_OK, EXIT_PROBLEMS, EXIT_NOT_REACHABLE, EXIT_ROLLED_BACK = 0, 1, 2, 3
CONNECTION_ATTEMPTS = 20
REACH_ATTEMPTS = 20
PAUSE_SECONDS = 3
TOKEN_FILE = "cloudflared.token"
PRIVATE_FOLDER_MODE = 0o700


class Tool:
    def __init__(self, settings, api, probe, launchd, state_dir, agents_dir, log_dir, find_binary=cf_connector.find_binary, say=print, sleep=time.sleep):
        self.s = settings
        self.api = api
        self.probe = probe
        self.launchd = launchd
        self.state_dir = state_dir
        self.agents_dir = agents_dir
        self.log_dir = log_dir
        self.find_binary = find_binary
        self.say = say
        self.sleep = sleep

    # ---- read-only checks ----------------------------------------------------------------------------------------------

    def problems(self) -> list:
        state = cf_state.load(self.state_dir) or {}
        return [*self._token_and_zone(), *self._name_clash(state), *self._dns_clash(state), *self._origin_and_program()]

    def _token_and_zone(self) -> list:
        try:
            if not self.api.verify_token(self.s.account_id):
                return ["The Cloudflare API token is not active."]
            zone = self.api.zone_name(self.s.zone_id)
        except CloudflareError as failure:
            return [f"Cloudflare would not answer for this token and zone: {failure}"]
        if not zone:
            return ["This token cannot see the zone."]
        inside = self.s.host == zone or self.s.host.endswith("." + zone)
        return [] if inside else [f"{self.s.host} is not inside the zone {zone}."]

    def _name_clash(self, state: dict) -> list:
        if state.get("tunnel_id"):
            return []
        try:
            taken = self.api.tunnels_named(self.s.account_id, self.s.tunnel_name)
        except CloudflareError as failure:
            return [f"The token cannot list tunnels (it needs Cloudflare Tunnel: Edit): {failure}"]
        return [f"A tunnel named {self.s.tunnel_name} already exists and is not this tool's. Pick another with --tunnel-name."] if taken else []

    def _dns_clash(self, state: dict) -> list:
        try:
            record = self.api.dns_find(self.s.zone_id, self.s.host)
        except CloudflareError as failure:
            return [f"The token cannot read DNS records (it needs Zone DNS: Edit): {failure}"]
        if not record or record.get("id") == state.get("dns_record_id"):
            return []
        return [f"{self.s.host} already has a DNS record that this tool did not make. It will not be changed."]

    def _origin_and_program(self) -> list:
        found = []
        if not reached(self.probe(self.s.origin + "/")):
            found.append(f"The panel is not answering on {self.s.origin}. Start MetaService first.")
        try:
            self.find_binary()
        except cf_connector.ConnectorError as failure:
            found.append(str(failure))
        return found

    def _report(self, found: list) -> int:
        self.say("Not ready:")
        for line in found:
            self.say(f"  - {line}")
        return EXIT_PROBLEMS

    def check(self) -> int:
        found = self.problems()
        if found:
            return self._report(found)
        self.say(f"Ready: the token works, {self.s.host} is in the zone, the panel answers, and cloudflared is installed.")
        return EXIT_OK

    def plan(self) -> int:
        found = self.problems()
        if found:
            return self._report(found)
        self.say(f"Nothing has been changed. `up` would make: a tunnel named {self.s.tunnel_name} (its own, MAAS's is not touched), "
                 f"one route {self.s.host} to {self.s.origin}, one proxied DNS record for {self.s.host}, an owner-only token file, "
                 f"and a launchd job {cf_connector.LABEL} for its connector.")
        return EXIT_OK

    # ---- up ------------------------------------------------------------------------------------------------------------

    def up(self) -> int:
        found = self.problems()
        if found:
            return self._report(found)
        try:
            self._build()
        except (CloudflareError, cf_connector.ConnectorError, OSError) as failure:
            self.say(f"Something failed ({failure}). Undoing what was made.")
            self.down()
            return EXIT_ROLLED_BACK
        return self._wait_until_reachable()

    def _build(self) -> None:
        state = cf_state.load(self.state_dir) or {"host": self.s.host}
        account = self.s.account_id
        if "tunnel_id" not in state:
            made = self.api.create_tunnel(account, self.s.tunnel_name)
            state.update(tunnel_id=made["id"], tunnel_name=self.s.tunnel_name)
            cf_state.save(self.state_dir, state)
        self.api.put_config(account, state["tunnel_id"], cf_ingress.config_for(self.s.host, self.s.origin))
        if "dns_record_id" not in state:
            record = self.api.dns_create(self.s.zone_id, self.s.host, f"{state['tunnel_id']}.cfargotunnel.com")
            state["dns_record_id"] = record["id"]
            cf_state.save(self.state_dir, state)
        self._write_token(state)
        cf_state.save(self.state_dir, state)
        self._start_connector(state)
        cf_state.save(self.state_dir, state)

    def _token_path(self) -> str:
        return os.path.join(self.state_dir, TOKEN_FILE)

    def _plist_path(self) -> str:
        return os.path.join(self.agents_dir, cf_connector.LABEL + ".plist")

    def _log_path(self) -> str:
        return os.path.join(self.log_dir, log_folder.CONNECTOR_LOG)

    def _write_token(self, state: dict) -> None:
        token = self.api.tunnel_token(self.s.account_id, state["tunnel_id"])
        os.makedirs(self.state_dir, mode=0o700, exist_ok=True)
        handle = os.open(self._token_path(), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(handle, "w", encoding="utf-8") as file:
            file.write(token)
        state["token_file"] = True

    def _start_connector(self, state: dict) -> None:
        if cf_connector.daemon_installed():
            self.say(f"The connector is the boot-time daemon {cf_connector.DAEMON_LABEL} (./install.sh autostart on), so no user job is made.")
            state["connector_domain"] = "system"
            return
        os.makedirs(self.agents_dir, exist_ok=True)
        os.makedirs(self.log_dir, mode=PRIVATE_FOLDER_MODE, exist_ok=True)
        with open(self._plist_path(), "w", encoding="utf-8") as file:
            file.write(cf_connector.plist_text(self.find_binary(), self._token_path(), self._log_path()))
        state["connector_domain"] = self.launchd.start(self._plist_path())

    def _wait_until_reachable(self) -> int:
        state = cf_state.load(self.state_dir) or {}
        if not self._wait_for_connection(state["tunnel_id"]):
            self.say(f"The tunnel made and the connector started, but Cloudflare shows no connection yet. Look at {self._log_path()}, then run `status`.")
            return EXIT_NOT_REACHABLE
        self.say("The connector is connected.")
        status = self._wait_for_host()
        if not reached(status):
            self.say(f"The tunnel is up but https://{self.s.host}/ does not answer yet (last answer {status}). DNS can take a minute; run `status`.")
            return EXIT_NOT_REACHABLE
        self.say(f"https://{self.s.host}/ answers (HTTP {status}).")
        return EXIT_OK

    def _wait_for_connection(self, tunnel_id: str) -> bool:
        for _ in range(CONNECTION_ATTEMPTS):
            if self.api.tunnel(self.s.account_id, tunnel_id).get("connections"):
                return True
            self.sleep(PAUSE_SECONDS)
        return False

    def _wait_for_host(self) -> int:
        status = 0
        for _ in range(REACH_ATTEMPTS):
            status = self.probe(f"https://{self.s.host}/")
            if reached(status):
                break
            self.sleep(PAUSE_SECONDS)
        return status

    # ---- status ---------------------------------------------------------------------------------------------------------

    def status(self) -> int:
        state = cf_state.load(self.state_dir)
        if not state:
            self.say("Remote access is not set up (nothing recorded). `plan` shows what `up` would do.")
            return EXIT_PROBLEMS
        connections = self._connection_count(state)
        self.say(f"Host: {state.get('host')}. Tunnel: {state.get('tunnel_name')} ({connections} connection(s)). "
                 f"Connector job: {self._connector_name()} {'loaded' if self.launchd.is_loaded() else 'NOT loaded'}.")
        public = self.probe(f"https://{state.get('host')}/")
        self.say(f"https://{state.get('host')}/ answers HTTP {public}." if public else f"https://{state.get('host')}/ does not answer.")
        return EXIT_OK if connections and reached(public) else EXIT_PROBLEMS

    def _connector_name(self) -> str:
        return f"{cf_connector.DAEMON_LABEL} (boot-time daemon)" if cf_connector.daemon_installed() else cf_connector.LABEL

    def _connection_count(self, state: dict) -> int:
        try:
            return len(self.api.tunnel(self.s.account_id, state["tunnel_id"]).get("connections") or [])
        except (CloudflareError, KeyError):
            return 0

    # ---- down -----------------------------------------------------------------------------------------------------------

    def down(self) -> int:
        state = cf_state.load(self.state_dir)
        if not state:
            self.say("Nothing to remove: this tool has not made anything here.")
            return EXIT_OK
        self._remove_connector(state)
        self._remove_tunnel(state)
        self._remove_dns(state)
        left = [name for name in ("tunnel_id", "dns_record_id") if name in state]
        if left:
            cf_state.save(self.state_dir, state)
            self.say("Not everything could be removed; it is still recorded. Run `down` again.")
            return EXIT_PROBLEMS
        cf_state.forget(self.state_dir)
        self.say("Removed: the connector job, the token file, the tunnel and the DNS record this tool made. Nothing else was touched.")
        return EXIT_OK

    def _remove_connector(self, state: dict) -> None:
        if cf_connector.daemon_installed():
            self.say(f"The connector daemon {cf_connector.DAEMON_LABEL} is still installed and will keep restarting. Run ./install.sh autostart off to remove it.")
        self.launchd.stop()
        for path in (self._plist_path(), self._token_path()):
            if os.path.exists(path):
                os.remove(path)
        state.pop("token_file", None)
        state.pop("connector_domain", None)

    def _remove_tunnel(self, state: dict) -> None:
        tunnel_id = state.get("tunnel_id")
        if not tunnel_id:
            return
        try:
            self._clean_and_delete(tunnel_id)
        except CloudflareError as failure:
            self.say(f"The tunnel could not be deleted: {failure}")
            return
        state.pop("tunnel_id")

    def _clean_and_delete(self, tunnel_id: str) -> None:
        try:
            self.api.clean_connections(self.s.account_id, tunnel_id)
        except CloudflareError:
            pass  # nothing connected, or already gone; the delete below says if there is a real problem
        self.api.delete_tunnel(self.s.account_id, tunnel_id)

    def _remove_dns(self, state: dict) -> None:
        record_id = state.get("dns_record_id")
        if not record_id:
            return
        try:
            current = self.api.dns_find(self.s.zone_id, state.get("host", self.s.host))
            if current and current.get("id") == record_id:
                self.api.dns_delete(self.s.zone_id, record_id)
        except CloudflareError as failure:
            self.say(f"The DNS record could not be removed: {failure}")
            return
        state.pop("dns_record_id")
