"""Session-bound host command requests over Hermes TUI JSON-RPC.

This adapter never executes commands or stores permissions. The macOS client
owns consent and execution; only an attached, foreground chat can request it.
"""
import json
import threading
import time
import uuid

TOOL = "run_host_command"


def arguments(value):
    if not isinstance(value, dict) or set(value) - {"command", "cwd", "timeout_seconds"}:
        raise ValueError("Expected command, optional cwd and timeout_seconds only.")
    command = value.get("command")
    cwd = value.get("cwd", "")
    timeout = value.get("timeout_seconds", 60)
    if not isinstance(command, str) or not command.strip() or len(command) > 32768 or "\0" in command:
        raise ValueError("Command must contain 1–32768 characters without NUL bytes.")
    if not isinstance(cwd, str) or len(cwd) > 4096 or "\0" in cwd or (cwd and not cwd.startswith(("/", "~/"))):
        raise ValueError("cwd must be an absolute macOS path or start with ~/.")
    if type(timeout) is not int or not 1 <= timeout <= 120:
        raise ValueError("timeout_seconds must be an integer from 1 to 120.")
    return {"command": command, "cwd": cwd, "timeout_seconds": timeout}


class HostCommands:
    def __init__(self, server):
        self.server = server
        self.lock = threading.RLock()
        self.attached = set()
        self.pending = {}
        self.description = None

    def configure(self, description):
        if not isinstance(description, str) or not description.strip() or len(description) > 16000:
            raise ValueError("A native host command tool description is required.")
        from tools.registry import registry
        from tools.approval_context import _approval_session_id, _approval_tool_call_id
        if not all(hasattr(value, "get") for value in (_approval_session_id, _approval_tool_call_id)):
            raise RuntimeError("Update Hermes to enable trusted host command requests.")
        with self.lock:
            if self.description == description:
                return {"configured": True}
            registry.register(name=TOOL, toolset="terminal", handler=self.execute,
                schema={"name": TOOL, "description": description,
                        "parameters": {"type": "object", "additionalProperties": False,
                            "properties": {"command": {"type": "string"}, "cwd": {"type": "string"},
                                "timeout_seconds": {"type": "integer", "minimum": 1, "maximum": 120}},
                            "required": ["command"]}})
            if registry.get_entry(TOOL).handler != self.execute:
                raise RuntimeError("Hermes could not register the Talaria host command tool.")
            self.description = description
        return {"configured": True}

    def attach(self, sid):
        with self.lock:
            session = self.server._sessions.get(sid)
            if not session:
                raise ValueError("The host command chat is no longer available.")
            agent = session.get("agent")
            if agent and self.description and not session.get("running") and getattr(agent, "_talaria_host_description", None) != self.description:
                # History/model discovery may have built the agent before the
                # first chat request installed this tool. Use Hermes's shared
                # snapshot refresh at this idle turn boundary.
                from tools.mcp_tool_agent import refresh_agent_mcp_tools
                refresh_agent_mcp_tools(agent, quiet_mode=True, preserve_prefix=True)
                agent._talaria_host_description = self.description
            self.attached.add(sid)
        return {"attached": True}

    def detach(self, sid):
        with self.lock:
            self.attached.discard(sid)
            for request in self.pending.values():
                if request["session_id"] == sid:
                    request["result"] = {"error": "Host command chat disconnected."}
                    request["ready"].set()
        return {"detached": True}

    def execute(self, args, *, session_id=None, **_kwargs):
        from tools.approval_context import _approval_session_id, _approval_tool_call_id
        try:
            clean = arguments(args)
            if not session_id or _approval_session_id.get() != session_id or not _approval_tool_call_id.get():
                raise ValueError("Host commands require a trusted Hermes chat tool call.")
            with self.lock:
                # Resolve from Hermes dispatch identity, never model arguments.
                matches = [(sid, self.server._sessions.get(sid)) for sid in self.attached]
                matches = [(sid, s) for sid, s in matches if s and
                           getattr(s.get("agent"), "session_id", None) == session_id]
                if len(matches) != 1:
                    raise ValueError("Host commands require an active Talaria chat.")
                sid, session = matches[0]
                if session.get("_turn_cancel_requested") or not session.get("running"):
                    raise ValueError("The chat has stopped.")
                rid = uuid.uuid4().hex
                request = {"session_id": sid, "ready": threading.Event(), "result": None}
                self.pending[rid] = request
            try:
                self.server._emit("host.command.request", sid, {**clean, "request_id": rid, "session_id": sid})
                deadline = time.monotonic() + 360
                while not request["ready"].wait(0.1):
                    if session.get("_turn_cancel_requested") or not session.get("running"):
                        raise ValueError("Host command cancelled.")
                    if time.monotonic() >= deadline:
                        raise ValueError("Host command permission or execution timed out.")
                return json.dumps(request["result"], ensure_ascii=False)
            finally:
                with self.lock:
                    self.pending.pop(rid, None)
        except (ValueError, RuntimeError) as exc:
            return json.dumps({"error": str(exc)})

    def respond(self, params):
        with self.lock:
            request = self.pending.get(params.get("request_id"))
            if not request or request["session_id"] != params.get("session_id") or request["ready"].is_set():
                raise ValueError("This host command is no longer pending.")
            result = params.get("result")
            if not isinstance(result, dict) or len(json.dumps(result)) > 1000000:
                raise ValueError("Invalid host command result.")
            request["result"] = result
            request["ready"].set()
        return {"resolved": True}


def register(server):
    service = HostCommands(server)
    for action in ("configure", "attach", "detach", "respond"):
        def handler(rid, params, action=action):
            try:
                if action == "configure":
                    result = service.configure(params.get("description"))
                elif action == "respond":
                    result = service.respond(params)
                else:
                    result = getattr(service, action)(params.get("session_id"))
                return server._ok(rid, result)
            except (ImportError, AttributeError, TypeError):
                return server._err(rid, -32601, "This Hermes version does not support host commands. Update Hermes and retry.")
            except (ValueError, RuntimeError) as exc:
                return server._err(rid, -32602, str(exc))
        server.method("talaria.host." + action)(handler)
    return service
