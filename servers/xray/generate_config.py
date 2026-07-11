#!/usr/bin/env python3
"""Build a Mihomo config that applies project-owned whitelist routing."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Any

import yaml


class ConfigurationError(ValueError):
    """A user-actionable configuration error."""


PROJECT_PROXY_GROUP = "PROJECT_PROXY"


def load_yaml(path: Path, description: str) -> dict[str, Any]:
    try:
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ConfigurationError(f"{description} not found: {path}") from exc
    except yaml.YAMLError as exc:
        raise ConfigurationError(f"Invalid {description} YAML in {path}: {exc}") from exc
    if not isinstance(document, dict):
        raise ConfigurationError(f"{description} must be a YAML mapping.")
    return document


def validate_whitelist(path: Path) -> None:
    document = load_yaml(path, "proxy whitelist")
    payload = document.get("payload")
    if not isinstance(payload, list) or not all(isinstance(rule, str) for rule in payload):
        raise ConfigurationError(
            f"Proxy whitelist {path} must contain a 'payload' list of Clash/Mihomo rule strings."
        )


def proxy_names(config: dict[str, Any]) -> list[str]:
    proxies = config.get("proxies")
    if not isinstance(proxies, list):
        raise ConfigurationError("Clash config must contain a top-level 'proxies' list.")
    names = [proxy.get("name") for proxy in proxies if isinstance(proxy, dict) and isinstance(proxy.get("name"), str)]
    if not names:
        raise ConfigurationError("Clash config must contain at least one named proxy.")
    if len(names) != len(set(names)):
        raise ConfigurationError("Clash proxy names must be unique.")
    return names


def build_config(clash_config: dict[str, Any], proxies: list[str]) -> dict[str, Any]:
    proxy_groups = clash_config.get("proxy-groups", [])
    if not isinstance(proxy_groups, list):
        raise ConfigurationError("'proxy-groups' must be a list when present in Clash config.")
    if any(isinstance(group, dict) and group.get("name") == PROJECT_PROXY_GROUP for group in proxy_groups):
        raise ConfigurationError(f"'{PROJECT_PROXY_GROUP}' is reserved by this project; rename the group in clash.yaml.")

    rule_providers = clash_config.get("rule-providers", {})
    if not isinstance(rule_providers, dict):
        raise ConfigurationError("'rule-providers' must be a mapping when present in Clash config.")
    if "project-proxy-whitelist" in rule_providers:
        raise ConfigurationError("'project-proxy-whitelist' is reserved by this project; rename it in clash.yaml.")

    managed_rule_providers = dict(rule_providers)
    managed_rule_providers["project-proxy-whitelist"] = {
        "type": "file",
        "behavior": "classical",
        "format": "yaml",
        "path": "./proxy-whitelist.yaml",
    }

    # Replace user routing so this service has one unambiguous policy: whitelist -> proxy,
    # then direct. Other Clash options, proxy nodes, and groups are kept intact.
    config = dict(clash_config)
    config.update(
        {
            "port": 10809,
            "socks-port": 10808,
            "allow-lan": False,
            "bind-address": "*",
            "mode": "rule",
            "log-level": "warning",
            "proxy-groups": [
                *proxy_groups,
                {"name": PROJECT_PROXY_GROUP, "type": "select", "proxies": proxies},
            ],
            "rule-providers": managed_rule_providers,
            "rules": [
                f"RULE-SET,project-proxy-whitelist,{PROJECT_PROXY_GROUP}",
                "MATCH,DIRECT",
            ],
        }
    )
    return config


def main() -> int:
    try:
        clash_path = Path(os.environ.get("CLASH_CONFIG_PATH", "/config/clash.yaml"))
        whitelist_path = Path(os.environ.get("PROXY_WHITELIST_PATH", "/config/proxy-whitelist.yaml"))
        output_path = Path(os.environ.get("MIHOMO_CONFIG_PATH", "/runtime/config.yaml"))
        clash_config = load_yaml(clash_path, "Clash config")
        proxies = proxy_names(clash_config)
        validate_whitelist(whitelist_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(
            yaml.safe_dump(build_config(clash_config, proxies), allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        print(f"Generated {output_path} with {len(proxies)} Clash proxy choice(s).")
    except ConfigurationError as exc:
        print(f"Configuration error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
