"""Run with a Hermes-capable Python and the installed Hermes source path.

Exercises Hermes's actual RPC dispatcher, event transport, registry and trusted
tool-call context in a disposable profile. No inference or provider calls.
"""
import json
import os
from pathlib import Path
import queue
import sys
import tempfile
import threading
from types import SimpleNamespace


def main():
    source = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="talaria-host-hermes-") as temporary:
        os.environ.update(HERMES_HOME=temporary, HERMES_DISABLE_MCP="1")
        sys.path[:0] = [str(Path(__file__).resolve().parents[1] / "AgentRuntime"), str(source)]
        from tui_gateway import server
        from tools.registry import registry
        from tools.approval_context import set_current_observability_context, reset_current_observability_context
        from hermes_host_commands import register, TOOL
        service = register(server)

        class Sink:
            def __init__(self):
                self.frames = queue.Queue()
            def write(self, frame):
                self.frames.put(json.loads(json.dumps(frame)))
                return True

        transport = Sink()
        def rpc(action, params):
            response = server.dispatch({"jsonrpc": "2.0", "id": "test", "method": "talaria.host." + action,
                                        "params": params}, transport=transport)
            assert "error" not in response, response
            return response["result"]

        assert rpc("configure", {"description": "Native TLPromptBuilder host tool fixture."})["configured"]
        assert registry.get_schema(TOOL)["parameters"]["required"] == ["command"]
        assert registry.get_toolset_for_tool(TOOL) == "terminal"
        server._sessions["runtime-chat"] = {"agent": SimpleNamespace(session_id="durable-chat"),
                                             "running": True, "transport": transport}
        assert rpc("attach", {"session_id": "runtime-chat"})["attached"]
        outcome = queue.Queue()
        def dispatch_tool():
            tokens = set_current_observability_context(session_id="durable-chat", tool_call_id="call-1")
            try:
                outcome.put(registry.dispatch(TOOL, {"command": "printf probe"}, session_id="durable-chat"))
            finally:
                reset_current_observability_context(tokens)
        thread = threading.Thread(target=dispatch_tool)
        thread.start()
        frame = transport.frames.get(timeout=3)
        assert frame["method"] == "event" and frame["params"]["type"] == "host.command.request", frame
        request = frame["params"]["payload"]
        assert request["command"] == "printf probe" and outcome.empty()
        result = {"stdout": "probe", "stderr": "", "exit_code": 0}
        assert rpc("respond", {"session_id": "runtime-chat", "request_id": request["request_id"], "result": result})["resolved"]
        assert json.loads(outcome.get(timeout=3)) == result
        thread.join(3)
        assert not thread.is_alive() and not service.pending
        assert rpc("detach", {"session_id": "runtime-chat"})["detached"]
        server._sessions.pop("runtime-chat")
        print("Installed Hermes host-command RPC/registry integration passed.")


if __name__ == "__main__":
    main()
