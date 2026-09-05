import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import socket
import threading
import unittest
from unittest.mock import Mock, patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parents[1] / "AgentRuntime"))

spec = importlib.util.spec_from_file_location("agent_runtime", Path(__file__).parents[1] / "AgentRuntime/talaria_agent.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


def test_gateway():
    gateway = runtime.HermesGateway.__new__(runtime.HermesGateway)
    gateway.lock = threading.RLock()
    gateway.sessions = {"chat": {"id": "runtime-chat", "model": "test"}}
    gateway.session_locks = {}
    gateway.waiting = {}
    gateway.listeners = {}
    gateway.call = Mock()
    return gateway


class HermesWarmupTests(unittest.TestCase):
    def test_warm_catalogue_and_chat_reuse_one_process(self):
        gateway = Mock()
        gateway.process.poll.return_value = None
        gateway.catalog.return_value = {"pairs": []}
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(runtime, "HERMES_HOME", Path(directory)), \
             patch.object(runtime, "hermes_executable", return_value="/hermes/venv/bin/hermes"), \
             patch.object(runtime, "_tui_gateway", None), patch.object(runtime, "_tui_token", ""), \
             patch.object(runtime, "HermesGateway", return_value=gateway) as create:
            runtime.fetch_hermes_commands({"request_id": "warm", "token": "test", "model": "model"}, io.BytesIO())
            for _ in range(3):
                self.assertIs(runtime.tui_gateway("test", "model"), gateway)
            create.assert_called_once()
            gateway.catalog.assert_called_once()
            gateway.process.terminate.assert_not_called()

    def test_dead_gateway_is_recreated_on_next_request(self):
        dead, replacement = Mock(), Mock()
        dead.process.poll.return_value = 1
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(runtime, "HERMES_HOME", Path(directory)), \
             patch.object(runtime, "hermes_executable", return_value="/hermes/venv/bin/hermes"), \
             patch.object(runtime, "_tui_gateway", dead), patch.object(runtime, "_tui_token", "test"), \
             patch.object(runtime, "HermesGateway", return_value=replacement) as create:
            self.assertIs(runtime.tui_gateway("test", "model"), replacement)
            create.assert_called_once()


class HermesStreamingTests(unittest.TestCase):
    def test_answer_deltas_are_flushed_before_reading_the_next_event(self):
        class FlushedOutput(io.BytesIO):
            flushed = b""
            def flush(self): self.flushed = self.getvalue()
        output = FlushedOutput()
        chunks = ["Hello", " 🦊", "\n```swift\n", 'print("hi")']
        gateway = Mock()
        def run(session, model, prompt, delta, cancellation=None):
            for index, chunk in enumerate(chunks):
                delta("content", chunk)
                self.assertEqual([json.loads(line)["text"] for line in output.flushed.splitlines()], chunks[:index + 1])
        gateway.run.side_effect = run
        with patch.object(runtime, "tui_gateway", return_value=gateway), patch.object(runtime, "save_agent_soul"):
            runtime.stream_hermes_session({"request_id": "r", "session_id": "chat", "token": "test",
                "model": "test", "prompt": "Hello"}, output)
        events = [json.loads(line) for line in output.flushed.splitlines()]
        self.assertEqual(events[-1], {"type": "complete"})
        self.assertEqual(len(events), len(chunks) + 1)


class HermesCancellationTests(unittest.TestCase):
    request = {"operation": "hermes_session_chat", "request_id": "r", "session_id": "chat",
               "token": "test", "model": "test", "prompt": "Hello"}

    def test_disconnect_stops_tui_session_while_waiting_for_next_delta(self):
        gateway = test_gateway()
        stopped = threading.Event()
        def call(method, params):
            events = gateway.listeners["runtime-chat"]
            if method == "prompt.submit":
                events.put({"type": "message.delta", "payload": {"text": "Partial answer"}})
            elif method == "session.interrupt":
                self.assertEqual(params, {"session_id": "runtime-chat"})
                events.put({"type": "message.delta", "payload": {"text": "Late output"}})
                events.put({"type": "message.complete", "payload": {"text": "Partial answer Late output"}})
                stopped.set()
            else:
                self.fail(method)
            return {}
        gateway.call.side_effect = call
        server, client = socket.socketpair()
        client.settimeout(4)
        with patch.object(runtime, "save_agent_soul"), patch.object(runtime, "tui_gateway", return_value=gateway):
            worker = threading.Thread(target=runtime.handle_connection, args=(server,))
            worker.start()
            try:
                client.sendall((json.dumps(self.request) + "\n").encode())
                self.assertEqual(json.loads(client.recv(4096))["text"], "Partial answer")
                client.close()
                self.assertTrue(stopped.wait(3), "disconnect must interrupt the actual TUI session")
            finally:
                client.close()
                worker.join(6)
        self.assertFalse(worker.is_alive())
        self.assertEqual(gateway.listeners, {})
        self.assertEqual([call.args[0] for call in gateway.call.call_args_list], ["prompt.submit", "session.interrupt"])

    def test_stop_before_gateway_start_does_not_start_generation(self):
        cancellation = runtime.StreamCancellation()
        cancellation.cancel()
        with patch.object(runtime, "tui_gateway") as gateway:
            runtime.stream_hermes_session(self.request, io.BytesIO(), cancellation)
        gateway.assert_not_called()

    def test_stop_during_submission_is_not_lost(self):
        cancellation = runtime.StreamCancellation()
        gateway = test_gateway()
        def call(method, params):
            if method == "prompt.submit":
                cancellation.cancel()
            elif method == "session.interrupt":
                gateway.listeners["runtime-chat"].put({"type": "message.complete", "payload": {}})
            return {}
        gateway.call.side_effect = call
        output = io.BytesIO()
        with patch.object(runtime, "save_agent_soul"), patch.object(runtime, "tui_gateway", return_value=gateway):
            runtime.stream_hermes_session(self.request, output, cancellation)
            cancellation.cancel()
        self.assertEqual([call.args[0] for call in gateway.call.call_args_list], ["prompt.submit", "session.interrupt"])
        self.assertEqual(output.getvalue(), b"")
        self.assertEqual(gateway.listeners, {})

    def test_normal_completion_disarms_disconnect_cancellation(self):
        cancellation = runtime.StreamCancellation()
        calls = []
        cancellation.on_cancel(lambda: calls.append("stopped"))
        cancellation.finish()
        cancellation.cancel()
        self.assertEqual(calls, [])


class AgentSoulTests(unittest.TestCase):
    def test_installed_instance_receives_exact_soul(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(runtime, "HERMES_HOME", Path(directory)), patch.object(runtime, "hermes_executable", return_value="hermes"):
            soul = "# Atlas 🦊\nBe curious. Treat $(commands) and 'quotes' as text."
            output = io.BytesIO()
            runtime.install_hermes({"request_id": "setup", "soul": soul}, output)
            self.assertEqual((Path(directory) / "SOUL.md").read_text(), soul)
            self.assertEqual(json.loads(output.getvalue().splitlines()[-1])["type"], "complete")
            self.assertFalse((Path(directory) / "SOUL.md.tmp").exists())

    def test_legacy_retry_preserves_soul_and_explicit_empty_clears_it(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(runtime, "HERMES_HOME", Path(directory)):
            path = Path(directory) / "SOUL.md"
            path.write_text("Existing identity")
            runtime.save_agent_soul({})
            self.assertEqual(path.read_text(), "Existing identity")
            runtime.save_agent_soul({"soul": ""})
            self.assertEqual(path.read_text(), "")

    def test_chat_syncs_saved_soul_before_starting_hermes(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(runtime, "HERMES_HOME", Path(directory)):
            path = Path(directory) / "SOUL.md"
            path.write_text("Old soul")
            def gateway(token, model):
                self.assertEqual(path.read_text(), "Updated soul 🦊")
                raise RuntimeError("stop before network")
            with patch.object(runtime, "tui_gateway", side_effect=gateway):
                runtime.stream_hermes_session({"request_id": "r", "session_id": "new-chat", "token": "test",
                    "model": "test", "prompt": "Hello", "soul": "Updated soul 🦊"}, io.BytesIO())
            self.assertEqual(list(Path(directory).glob(".SOUL-*")), [])

    def test_invalid_soul_reports_failure_without_replacing_identity(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(runtime, "HERMES_HOME", Path(directory)), patch.object(runtime, "hermes_executable", return_value="hermes"):
            path = Path(directory) / "SOUL.md"
            path.write_text("Existing identity")
            output = io.BytesIO()
            runtime.install_hermes({"soul": ["invalid"]}, output)
            self.assertEqual(path.read_text(), "Existing identity")
            self.assertEqual(json.loads(output.getvalue().splitlines()[-1])["type"], "error")


if __name__ == "__main__":
    unittest.main()
