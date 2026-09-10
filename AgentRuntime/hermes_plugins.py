"""Installed Hermes plugins and Talaria's bundled private policy over the TUI gateway."""
from hermes_notifications import _setup_lock
from incognito_policy import PLUGIN as INCOGNITO_PLUGIN, catalogue_entry as incognito_entry


class Plugins:
    def __init__(self):
        self.initial_states = {}

    def handle(self, params):
        from hermes_cli import config, managed_scope, plugins_cmd
        from hermes_cli.plugins import discover_plugins, get_plugin_manager
        if not isinstance(params, dict) or params.get("action") not in {"list", "set_enabled"}:
            raise ValueError("Unsupported plugin action.")
        if params["action"] == "set_enabled" and params.get("id") == INCOGNITO_PLUGIN:
            raise ValueError("Talaria Incognito runs automatically in Incognito windows and cannot be disabled.")
        with _setup_lock:
            # Normal, idempotent startup discovery only. Never reload the
            # registrations of an already-running session after a toggle.
            discover_plugins()
            # Hermes's metadata-only catalogue includes disabled plugins without
            # importing their code, and resolves source precedence itself.
            entries = plugins_cmd._discover_all_plugins()
            raw = config.load_config_readonly() or {}
            settings = dict(raw.get("plugins") or {})
            enabled, disabled = settings.get("enabled", []), settings.get("disabled", [])
            if not isinstance(enabled, list) or not isinstance(disabled, list) or not all(
                    isinstance(name, str) for name in [*enabled, *disabled]):
                raise ValueError("Hermes plugin settings must contain lists of plugin names.")
            enabled, disabled = set(enabled), set(disabled)
            managed = config.is_managed() or any(managed_scope.is_key_managed(key)
                for key in ("plugins", "plugins.enabled", "plugins.disabled"))

            def is_enabled(entry):
                name, _, _, source, path, key = entry
                names = {name, key}
                return not bool(names & disabled) and (bool(names & enabled) or
                    (source == "bundled" and plugins_cmd._bundled_default_on(path)))

            for entry in entries:
                self.initial_states.setdefault(entry[5], is_enabled(entry))
            if params["action"] == "set_enabled":
                if managed:
                    raise ValueError("Plugin settings are managed by your administrator.")
                key, desired = params.get("id"), params.get("enabled")
                entry = next((entry for entry in entries if entry[5] == key), None)
                if entry is None or not isinstance(desired, bool):
                    raise ValueError("Choose an installed plugin and an enabled state.")
                # Canonicalize installed legacy aliases before editing one key,
                # retaining unknown names and every unrelated plugin setting.
                def canonicalize(names):
                    result = set()
                    for name in names:
                        matches = {item[5] for item in entries if name in (item[0], item[5])}
                        result.update(matches or {name})
                    return result
                enabled, disabled = canonicalize(enabled), canonicalize(disabled)
                (enabled.add if desired else enabled.discard)(key)
                (disabled.discard if desired else disabled.add)(key)
                stored = dict((config.read_raw_config() or {}).get("plugins") or {})
                stored.update(enabled=sorted(enabled), disabled=sorted(disabled))
                # Keep grants and tool selection unchanged. Plugin code reloads
                # on the next agent start; never interrupt an active tool call.
                config.save_config({"plugins": stored}, merge_existing=True)
                actual = config.load_config_readonly().get("plugins") or {}
                enabled, disabled = set(actual.get("enabled", [])), set(actual.get("disabled", []))
                if is_enabled(entry) != desired:
                    raise ValueError("Hermes did not retain the requested plugin setting. Refresh and retry.")
            runtime = {item["key"]: item for item in get_plugin_manager().list_plugins()}
            plugins = []
            for entry in sorted(entries, key=lambda entry: (entry[3] == "bundled", entry[0].casefold(), entry[5])):
                name, version, description, source, _, key = entry
                active = runtime.get(key, {})
                desired = is_enabled(entry)
                plugins.append({"id": key, "name": name, "version": str(version or ""),
                    "description": description or "", "source": source, "enabled": desired,
                    "active": bool(active.get("enabled")), "error": active.get("error") or "",
                    "restart_required": desired != self.initial_states[key]})
            plugins.append(incognito_entry())
            return {"plugins": plugins, "managed": managed,
                    "restart_required": any(item["restart_required"] for item in plugins)}


def register_rpc(server):
    service = Plugins()
    server._LONG_HANDLERS = server._LONG_HANDLERS | {"talaria.plugins"}

    @server.method("talaria.plugins")
    def handler(request_id, params):
        try:
            return server._ok(request_id, service.handle(params))
        except (ImportError, AttributeError):
            return server._err(request_id, -32601, "Update Hermes to manage installed plugins.")
        except Exception as exc:
            return server._err(request_id, -32000, f"Hermes plugins: {exc}")
    return service
