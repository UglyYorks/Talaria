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
        self.children = {}
        self.registry = types.SimpleNamespace(_active_subagents=self.children, _active_subagents_lock=threading.Lock())
        self.patch = patch.dict(sys.modules, {"tools.approval_context": self.context, "tools.delegate_tool_registry": self.registry})
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.session = {"agent": types.SimpleNamespace(session_id="stored-chat"), "running": True}
        self.events = queue.Queue()
        self.server = types.SimpleNamespace(_sessions={"runtime-chat": self.session},
            _emit=lambda kind, sid, payload: self.events.put((kind, sid, payload)))
        self.service = HostCommands(self.server)
        self.service.attach("runtime-chat")

    def start_command(self, session_id="stored-chat"):
        result = queue.Queue()
        def invoke():
            self.context._approval_session_id.set(session_id)
            self.context._approval_tool_call_id.set("tool-call")
            result.put(json.loads(self.service.execute({"command": "printf hello"}, session_id=session_id)))
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
        self.assertIn("not connected to a Talaria chat", result["error"])
        self.assertTrue(self.events.empty())

    def test_delegated_command_survives_parent_completion_and_is_polled_once(self):
        child = types.SimpleNamespace(session_id="child-chat")
        self.children["child"] = {"agent": child, "owner_session_id": "runtime-chat", "owner_session_record": self.session}
        self.session["running"] = False
        self.service.detach("runtime-chat")
        thread, result = self.start_command("child-chat")
        import time
        deadline = time.monotonic() + 2
        while not self.service.pending and time.monotonic() < deadline: time.sleep(.01)
        self.assertTrue(self.events.empty(), "background calls use polling, not a finished turn listener")
        self.assertEqual(self.service.poll("other"), {"requests": []})
        request = self.service.poll("runtime-chat")["requests"][0]
        self.assertEqual(self.service.poll("runtime-chat"), {"requests": []})
        waiter = threading.Thread(target=lambda: self.service.wait(request))
        waiter.start()
        self.service.respond({**request, "result": {"stdout": "child output", "exit_code": 0}})
        self.assertEqual(result.get(timeout=2)["stdout"], "child output")
        thread.join(2); waiter.join(2)
        self.assertFalse(thread.is_alive() or waiter.is_alive())

    def test_child_cannot_cross_session_generation_and_stop_cancels_pending(self):
        child = types.SimpleNamespace(session_id="child-chat")
        record = {"agent": child, "owner_session_id": "runtime-chat", "owner_session_record": dict(self.session)}
        self.children["child"] = record
        self.context._approval_session_id.set("child-chat")
        self.context._approval_tool_call_id.set("call")
        self.assertIn("not connected", json.loads(self.service.execute({"command":"x"}, session_id="child-chat"))["error"])
        record["owner_session_record"] = self.session
        thread, result = self.start_command("child-chat")
        import time
        deadline = time.monotonic() + 2
        while not self.service.pending and time.monotonic() < deadline: time.sleep(.01)
        self.session["_turn_cancel_requested"] = True
        self.assertIn("cancelled", result.get(timeout=2)["error"])
        thread.join(2)
        self.assertFalse(self.service.pending)

    def test_gateway_poll_delivers_request_and_waits_for_native_result(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.lock = threading.RLock()
        gateway.sessions = {"chat": {"id": "runtime"}}
        request = {"request_id": "r", "session_id": "runtime", "command": "pwd"}
        gateway.call = Mock(side_effect=[{"requests": [request]}, {"finished": True}])
        delivered = Mock()
        gateway.poll_host_commands("chat", delivered)
        delivered.assert_called_once_with(request)
        gateway.call.assert_called_with("talaria.host.wait", {"session_id": "runtime", "request_id": "r"}, timeout=370)

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
