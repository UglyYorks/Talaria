"""Unmodified Hermes in a RAM profile with inherited kernel write restrictions."""
import ctypes
import os
from pathlib import Path
from incognito_policy import PLUGIN, VERSION, DESCRIPTION


def restrict_writes(root):
    # Linux arm64/x86_64 Landlock syscall numbers. ABI 3 includes truncate protection.
    libc = ctypes.CDLL(None, use_errno=True)
    abi = libc.syscall(444, 0, 0, 1)
    if abi < 3:
        raise RuntimeError("This VM kernel does not support Incognito filesystem isolation (Landlock ABI 3 required).")
    writes = sum(1 << bit for bit in (1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14))
    class Ruleset(ctypes.Structure):
        _fields_ = [("handled_access_fs", ctypes.c_uint64)]
    class Rule(ctypes.Structure):
        _pack_ = 1
        _fields_ = [("allowed_access", ctypes.c_uint64), ("parent_fd", ctypes.c_int)]
    attr = Ruleset(writes)
    ruleset = libc.syscall(444, ctypes.byref(attr), ctypes.sizeof(attr), 0)
    if ruleset < 0:
        raise OSError(ctypes.get_errno(), "Cannot create Incognito filesystem rules")
    try:
        for path, access in ((root, writes), (Path("/dev/null"), 1 << 1)):
            fd = os.open(path, os.O_PATH | os.O_CLOEXEC)
            try:
                rule = Rule(access, fd)
                if libc.syscall(445, ruleset, 1, ctypes.byref(rule), 0) < 0:
                    raise OSError(ctypes.get_errno(), "Cannot install Incognito filesystem rule")
            finally:
                os.close(fd)
        if libc.prctl(38, 1, 0, 0, 0) or libc.syscall(446, ruleset, 0):
            raise OSError(ctypes.get_errno(), "Cannot enforce Incognito filesystem isolation")
    finally:
        os.close(ruleset)


def private_config(config):
    """Retain inference credentials/options; remove background and external memory integrations."""
    config = dict(config or {})
    config["memory"] = {**(config.get("memory") or {}), "provider": "", "memory_enabled": True,
                        "user_profile_enabled": True, "nudge_interval": 0}
    config["auxiliary"] = {**(config.get("auxiliary") or {}), "background_review": {"enabled": False}}
    config["skills"] = {**(config.get("skills") or {}), "creation_nudge_interval": 0}
    # No external memory ingestion through plugins or MCP startup hooks.
    config["plugins"] = {"enabled": [], "disabled": []}
    config["mcp_servers"] = {}
    config["terminal"] = {"backend": "local", "cwd": os.environ.get("HOME", "/tmp")}
    config["hooks"] = {}
    config.pop("context", None)
    return config


def main():
    root = Path(os.environ["TALARIA_INCOGNITO_ROOT"]).resolve()
    restrict_writes(root)
    import yaml
    path = Path(os.environ["HERMES_HOME"]) / "config.yaml"
    raw = yaml.safe_load(path.read_text()) if path.exists() else {}
    path.write_text(yaml.safe_dump(private_config(raw)))
    # Register policy through Hermes's plugin interface before constructing any agent.
    # Discovery normally enables some bundled plugins by default. Explicitly deny ALL
    # discovered plugins in this isolated profile; no callbacks may ingest private turns.
    from hermes_cli import plugins_cmd
    entries = plugins_cmd._discover_all_plugins()
    cfg = yaml.safe_load(path.read_text())
    cfg["plugins"]["disabled"] = sorted({str(value) for entry in entries for value in (entry[0], entry[5])})
    plugin = path.parent / "plugins" / PLUGIN
    plugin.mkdir(parents=True)
    (plugin / "plugin.yaml").write_text(yaml.safe_dump({"name": PLUGIN, "version": VERSION,
                                                       "description": DESCRIPTION}))
    (plugin / "__init__.py").write_text("from incognito_policy import register\n")
    cfg["plugins"]["enabled"] = [PLUGIN]
    path.write_text(yaml.safe_dump(cfg))
    from hermes_cli.plugins import discover_plugins, get_plugin_manager
    discover_plugins()
    active = {item["key"] for item in get_plugin_manager().list_plugins() if item.get("enabled")}
    if active != {PLUGIN}:
        raise RuntimeError("Could not isolate Hermes plugin hooks for Incognito.")
    from hermes_cli import config as hermes_config
    resolved = hermes_config.load_config_readonly()
    if ((resolved.get("memory") or {}).get("provider") or (resolved.get("hooks") or {}) or
            (resolved.get("auxiliary") or {}).get("background_review", {}).get("enabled") is not False):
        raise RuntimeError("Managed Hermes settings prevent read-only Incognito memory.")
    from tui_gateway import entry
    from talaria_gateway_entry import register
    register(entry.server)
    from hermes_providers import register as register_providers
    register_providers(entry.server)
    @entry.server.method("talaria.incognito.status")
    def status(rid, params):
        return entry.server._ok(rid, {"isolated": True, "memory": "read_only"})
    entry.main()


if __name__ == "__main__":
    main()
