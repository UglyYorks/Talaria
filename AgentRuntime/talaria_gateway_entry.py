"""Register Talaria credential RPCs inside the installed Hermes TUI gateway.

Hermes Client's Tools & Keys uses the installed OPTIONAL_ENV_VARS registry and
Hermes's env store. Expose those same owners over stdio JSON-RPC, without a web
server, provider HTTP transport, shell commands, or a second credential store.
"""
import contextlib
import io
import sys
import threading

_lock = threading.RLock()


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


def register(server):
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


if __name__ == "__main__":
    from tui_gateway import entry
    register(entry.server)
    entry.main()
