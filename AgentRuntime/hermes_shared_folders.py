"""Required Hermes plugin: shared-folder instructions belong in the system prompt."""
import json
import os
from pathlib import Path

PLUGIN = "talaria-shared-folders"
STATE_FILE = "talaria-shared-folders.json"
CONTEXT_FILE = "talaria-shared-folders.txt"
SECTION_LIMIT = 4000


def context_state(home):
    path = Path(home) / STATE_FILE
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"context": "", "summary": ""}


def section_text(state):
    return state["context"] if len(state["context"]) <= SECTION_LIMIT else state["summary"]


def register(ctx):
    # Each normal/private gateway has its own Hermes home. Capture it when the
    # plugin is loaded, rather than relying on a child thread's environment.
    home = Path(os.environ["HERMES_HOME"])
    ctx.register_system_prompt_section(PLUGIN, lambda _session: section_text(context_state(home)),
                                       max_chars=SECTION_LIMIT)


def install(home):
    """Install before discovery/agent construction; preserve unrelated settings."""
    from hermes_cli import config
    from hermes_cli.plugins import PluginContext
    from hermes_notifications import _atomic_write
    if not hasattr(PluginContext, "register_system_prompt_section"):
        raise RuntimeError("Update Hermes to support Talaria's shared-folder system context.")
    home = Path(home)
    directory = home / "plugins" / PLUGIN
    _atomic_write(directory / "__init__.py", Path(__file__).read_text(encoding="utf-8"))
    _atomic_write(directory / "plugin.yaml", 'name: talaria-shared-folders\nversion: "1.0.0"\n'
                  'description: "Always provides the agent with shared-folder paths and access instructions."\n')
    settings = dict((config.read_raw_config() or {}).get("plugins") or {})
    enabled, disabled = settings.get("enabled", []), settings.get("disabled", [])
    if not isinstance(enabled, list) or not isinstance(disabled, list):
        raise ValueError("Hermes plugin settings must contain lists of plugin names.")
    if PLUGIN not in enabled or PLUGIN in disabled:
        settings.update(enabled=list(dict.fromkeys([*enabled, PLUGIN])), disabled=[name for name in disabled if name != PLUGIN])
        config.save_config({"plugins": settings}, merge_existing=True)
    actual = (config.load_config_readonly() or {}).get("plugins") or {}
    if PLUGIN not in actual.get("enabled", []) or PLUGIN in actual.get("disabled", []):
        raise RuntimeError("Hermes settings prevent Talaria's required shared-folder plugin from loading.")


class SharedFolders:
    def __init__(self, server, home):
        self.server, self.home = server, Path(home)

    def configure(self, params):
        from hermes_notifications import _atomic_write, _setup_lock
        context, summary = params.get("context"), params.get("summary")
        if not isinstance(context, str) or len(context) > 200000 or not isinstance(summary, str) or not 0 < len(summary) <= SECTION_LIMIT:
            raise ValueError("Invalid native shared-folder context.")
        # The full native-generated mapping remains available when it exceeds
        # Hermes's section budget; the always-loaded section tells agents where.
        state = {"context": context, "summary": summary}
        with _setup_lock:
            _atomic_write(self.home / CONTEXT_FILE, context)
            _atomic_write(self.home / STATE_FILE, json.dumps(state))
        return {"configured": True}

    def attach(self, rid, params):
        sid = params.get("session_id", "")
        session = self.server._sessions.get(sid)
        if not session:
            raise ValueError("Hermes session not found.")
        self.server._start_agent_build(sid, session)
        failure = self.server._wait_agent(session, rid)
        if failure:
            return failure
        agent = session["agent"]
        state = context_state(self.home)
        if getattr(agent, "_talaria_shared_folder_context", None) != state:
            if session.get("running"):
                raise ValueError("Wait for the current turn before updating shared-folder context.")
            # Hermes restores frozen plugin sections on resume. Use its own
            # invalidation boundary so pre-plugin chats and changed VM mounts
            # get fresh instructions without rewriting any user message.
            from agent.system_prompt import invalidate_system_prompt
            invalidate_system_prompt(agent)
            agent._talaria_shared_folder_context = state
        return self.server._ok(rid, {"attached": True})


def register_rpc(server, home):
    service = SharedFolders(server, home)
    server._LONG_HANDLERS = server._LONG_HANDLERS | {"talaria.shared_folders.attach"}
    for action in ("configure", "attach"):
        def handler(rid, params, action=action):
            try:
                return service.attach(rid, params) if action == "attach" else server._ok(rid, service.configure(params))
            except (ImportError, AttributeError):
                return server._err(rid, -32601, "Update Hermes to support shared-folder system context.")
            except Exception as exc:
                return server._err(rid, -32602, f"Shared folders: {exc}")
        server.method("talaria.shared_folders." + action)(handler)
    return service
