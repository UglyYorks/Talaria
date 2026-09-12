"""Host bridge routing and consent boundary; no provider requests."""
import contextvars
import json
from pathlib import Path
import queue
import sys
import threading
import types
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "AgentRuntime"))
from hermes_host_commands import HostCommands, arguments
from hermes_gateway import HermesGateway
import talaria_agent as worker


class HostCommandsTests(unittest.TestCase):
    def setUp(self):
        self.context = types.ModuleType("tools.approval_context")
        self.context._approval_session_id = contextvars.ContextVar("session", default="")
        self.context._approval_tool_call_id = contextvars.ContextVar("call", default="")
        self.patch = patch.dict(sys.modules, {"tools.approval_context": self.context})
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.session = {"agent": types.SimpleNamespace(session_id="stored-chat"), "running": True}
        self.events = queue.Queue()
        self.server = types.SimpleNamespace(_sessions={"runtime-chat": self.session},
            _emit=lambda kind, sid, payload: self.events.put((kind, sid, payload)))
        self.service = HostCommands(self.server)
        self.service.attach("runtime-chat")

    def start_command(self):
        result = queue.Queue()
        def invoke():
            self.context._approval_session_id.set("stored-chat")
            self.context._approval_tool_call_id.set("tool-call")
            result.put(json.loads(self.service.execute({"command": "printf hello"}, session_id="stored-chat")))
        thread = threading.Thread(target=invoke)
        thread.start()
        self.addCleanup(lambda: self.service.detach("runtime-chat"))
        self.addCleanup(lambda: setattr(self.session["agent"], "session_id", "stored-chat"))
        return thread, result

    def test_exact_request_result_and_no_replay(self):
        thread, result = self.start_command()
        kind, sid, event = self.events.get(timeout=2)
        self.assertEqual(kind, "host.command.request")
        self.assertEqual(event["command"], "printf hello")
        self.assertTrue(result.empty(), "tool must wait; it cannot execute in the guest")
        params = {"session_id": sid, "request_id": event["request_id"], "result": {"stdout": "hello", "exit_code": 0}}
        with self.assertRaisesRegex(ValueError, "no longer pending"):
            self.service.respond({**params, "session_id": "another-chat"})
        self.service.respond(params)
        self.assertEqual(result.get(timeout=2), params["result"])
        thread.join(2)
        with self.assertRaisesRegex(ValueError, "no longer pending"):
            self.service.respond(params)
        self.assertFalse(self.service.pending)

    def test_denial_disconnect_and_interrupt_unblock_tool(self):
        for action in ("deny", "detach", "interrupt"):
            with self.subTest(action=action):
                self.service.attach("runtime-chat")
                self.session["_turn_cancel_requested"] = False
                thread, result = self.start_command()
                _, sid, event = self.events.get(timeout=2)
                if action == "deny":
                    self.service.respond({"session_id": sid, "request_id": event["request_id"], "result": {"denied": True}})
                elif action == "detach":
                    self.service.detach(sid)
                else:
                    self.session["_turn_cancel_requested"] = True
                self.assertTrue(result.get(timeout=2))
                thread.join(2)
                self.assertFalse(thread.is_alive())
                self.assertFalse(self.service.pending)

    def test_untrusted_background_and_supporting_calls_cannot_request_execution(self):
        self.assertIn("error", json.loads(self.service.execute({"command": "x"}, session_id="stored-chat")))
        self.context._approval_session_id.set("supporting-model")
        self.context._approval_tool_call_id.set("call")
        result = json.loads(self.service.execute({"command": "x"}, session_id="supporting-model"))
        self.assertIn("active Talaria chat", result["error"])
        self.assertTrue(self.events.empty())

    def test_invalid_arguments_cannot_supply_permissions_or_session_identity(self):
        for invalid in ({"command": "x", "always": True}, {"command": "x", "session_id": "other"},
                        {"command": "x", "cwd": "relative"}, {"command": "x", "timeout_seconds": True},
                        {"command": "x", "timeout_seconds": 121}, {"command": "a\0b"}, {"command": " "}):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                arguments(invalid)
        self.assertEqual(arguments({"command": "printf x"})["timeout_seconds"], 60)

    def test_gateway_relays_request_and_continues_same_turn(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.lock = threading.RLock()
        gateway.sessions = {"chat": {"id": "runtime", "model": "m"}}
        gateway.listeners = {}
        gateway.session = Mock(return_value="runtime")
        def rpc(method, params=None):
            if method == "prompt.submit":
                gateway.listeners["runtime"].put({"type": "host.command.request", "payload": {"request_id": "host-1"}})
                gateway.listeners["runtime"].put({"type": "message.complete", "payload": {"text": "done"}})
            return {}
        gateway.call = Mock(side_effect=rpc)
        delta = Mock()
        gateway.run("chat", "m", "hello", delta, host_commands=True)
        delta.assert_any_call("host_command", {"request_id": "host-1"})
        delta.assert_any_call("content", "done")
        gateway.call.assert_any_call("talaria.host.attach", {"session_id": "runtime"})
        gateway.call.assert_any_call("talaria.host.detach", {"session_id": "runtime"})
        self.assertFalse(gateway.waiting)
        self.assertFalse(gateway.listeners)

    def test_worker_configures_tool_before_turn_and_delivers_result_via_rpc(self):
        import io
        gateway = Mock()
        with patch.object(worker, "tui_gateway", return_value=gateway), patch.object(worker, "save_agent_soul"):
            worker.stream_hermes_session({"request_id": "r", "session_id": "s", "model": "m", "prompt": "hi",
                                         "host_command_description": "native description"}, io.BytesIO())
            gateway.call.assert_called_with("talaria.host.configure", {"description": "native description"})
            self.assertTrue(gateway.run.call_args.kwargs["host_commands"])
            gateway.call.return_value = {"resolved": True}
            output = io.BytesIO()
            worker.handle_request({"operation": "hermes_host_response", "params": {"request_id": "h"}}, output)
            gateway.call.assert_called_with("talaria.host.respond", {"request_id": "h"})
            self.assertEqual(json.loads(output.getvalue().splitlines()[0])["result"], {"resolved": True})


if __name__ == "__main__":
    unittest.main()
