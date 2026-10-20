"""The route list of MetaService's own tunnel (pure, no network): one route to the panel and the catch-all that answers 404 to anything else."""
from __future__ import annotations

CATCH_ALL = {"service": "http_status:404"}


def config_for(host: str, service: str) -> dict:
    """The body for the tunnel's configuration call. Nothing else is ever routed through this tunnel."""
    return {"config": {"ingress": [{"hostname": host, "service": service}, dict(CATCH_ALL)]}}


def routes_only_to(config: dict, host: str, service: str) -> bool:
    ingress = (config or {}).get("config", {}).get("ingress", [])
    return ingress == config_for(host, service)["config"]["ingress"]
