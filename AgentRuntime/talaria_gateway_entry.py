"""Register Talaria credential, skill metadata, and automation RPCs in Hermes's TUI gateway.

Hermes Client's Tools & Keys uses the installed OPTIONAL_ENV_VARS registry and
Hermes's env store. Expose those same owners over stdio JSON-RPC, without a web
server, provider HTTP transport, shell commands, or a second credential store.
"""
import contextlib
import io
import os
import sys
import threading

_lock = threading.RLock()


def configure_vm_database(config=None):
    """Provision SQLite for Talaria's macOS-backed virtiofs volume.

    This is VM storage setup, before the gateway opens its heartbeat/session
    database. Hermes owns the config format and the database connections. Never
    change an existing database's journal mode under live connections; profiles
    already in WAL need a separate offline migration/recovery.
    """
    if config is None:
        from hermes_cli import config
    desired = {"journal_mode": "delete", "mmap_size": 0, "synchronous": "full"}
    current = config.load_config().get("database", {})
    if not isinstance(current, dict):
        raise RuntimeError("Hermes database configuration must be a mapping.")
    if all(current.get(key) == value for key, value in desired.items()):
        return
    config.save_config({"database": desired}, merge_existing=True,
                       preserve_keys={("database", key) for key in desired})
    verified = config.load_config().get("database", {})
    if not isinstance(verified, dict) or any(verified.get(key) != value for key, value in desired.items()):
        raise RuntimeError("Could not configure Hermes database storage for the shared VM volume.")


def credentials(action, params, config=None):
    if config is None:
        from hermes_cli import config
    registry = config.OPTIONAL_ENV_VARS
    # Provider keys remain in Model; platform credentials belong to messaging.
    entries = {key: info for key, info in registry.items()
               if info.get("category") in ("tool", "setting")}
    if action == "list":
        stored = config.load_env()
        return {"entries": [{"key": key, "description": info.get("description", ""),
                            "url": info.get("url") or "", "category": info.get("category"),
                            "is_password": bool(info.get("password", True)),
                            "is_set": bool(stored.get(key)), "tools": info.get("tools", [])}
                           for key, info in sorted(entries.items())]}
    key = params.get("key")
    if key not in entries:
        raise ValueError("This credential is not in the installed Hermes tool/settings catalogue.")
    if config.is_managed():
        raise ValueError("This Hermes installation is managed; credentials are read-only.")
    from hermes_cli import managed_scope
    if managed_scope.is_env_managed(key):
        raise ValueError("This credential is managed by your administrator.")
    if action == "set":
        value = params.get("value")
        if not isinstance(value, str) or not value.strip():
            raise ValueError("Enter a value before saving.")
        if "\n" in value or "\r" in value or "\x00" in value:
            raise ValueError("Credential values must be a single line.")
        config.validate_env_var_name_for_write(key)
        # Hermes helpers may print diagnostics; never put them on the RPC stream.
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            config.save_env_value(key, value)
        if config.load_env().get(key) != value:
            raise ValueError("Hermes could not save this value unchanged.")
    elif action == "remove":
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            config.remove_env_value(key)
        if config.load_env().get(key):
            raise ValueError("Hermes could not remove this credential.")
    else:
        raise ValueError("Unsupported credential action.")
    return {"ok": True, "key": key, "is_set": action == "set"}


def skill_metadata():
    # profiles.describe omits descriptions. Read only installed metadata through
    # Hermes's index and parser, retaining disabled and platform-specific skills.
    # Do not invoke skills or load their instructions into a conversation.
    from agent.skill_utils import iter_skill_index_files, parse_frontmatter
    from hermes_constants import get_skills_dir
    rows = []
    for path in iter_skill_index_files(get_skills_dir(), "SKILL.md"):
        metadata, _ = parse_frontmatter(path.read_text(encoding="utf-8"))
        description = metadata.get("description")
        rows.append({"name": path.parent.name,
                     "description": description.strip().strip("'\"") if isinstance(description, str) else ""})
    return {"skills": rows}


def register(server):
    from hermes_host_commands import register as register_host_commands
    register_host_commands(server)

    @server.method("talaria.skills.describe")
    def describe_skills(rid, params):
        try:
            return server._ok(rid, skill_metadata())
        except (ImportError, AttributeError, TypeError):
            return server._err(rid, -32601, "This Hermes version does not support skill descriptions. Update Hermes and retry.")
        except Exception:
            return server._err(rid, -32602, "Could not read Hermes skill descriptions. Reload the skill list and retry.")

    for action in ("list", "set", "remove"):
        def handler(rid, params, action=action):
            try:
                with _lock:
                    result = credentials(action, params)
                return server._ok(rid, result)
            except (ImportError, AttributeError):
                return server._err(rid, -32601, "This Hermes version does not support tool credentials. Update Hermes and retry.")
            except Exception:
                # Secrets can occur in upstream exception messages. Keep RPC
                # errors useful without returning a supplied or stored value.
                return server._err(rid, -32602, "Could not update Hermes credentials. Check the value and whether this installation is managed, then retry.")
        server.method("talaria.credentials." + action)(handler)


def main():
    # Must precede entry/server import and its background database maintenance.
    configure_vm_database()
    from tui_gateway import entry
    from hermes_automations import register as register_automations
    from hermes_notifications import register_rpc as register_notifications, DESCRIPTION_FILE
    from hermes_plugins import register_rpc as register_plugins
    from pathlib import Path
    register(entry.server)
    from hermes_providers import register as register_providers
    register_providers(entry.server)
    register_plugins(entry.server)
    notifications = register_notifications(entry.server, os.environ["HERMES_HOME"])
    description_path = Path(os.environ["HERMES_HOME"]) / DESCRIPTION_FILE
    if description_path.exists():
        try:
            notifications.prepare(description_path.read_text(encoding="utf-8"))
        except Exception:
            # The next description-bearing sync reports setup failure to the
            # user and retries. Existing schedules stay gated until it succeeds.
            pass
    automations = register_automations(entry.server, os.environ["HERMES_HOME"],
                                       can_dispatch=notifications.ready.is_set)
    try:
        entry.main()
    finally:
        automations.stop_event.set()


if __name__ == "__main__":
    main()
