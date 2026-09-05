import importlib.util
from contextlib import nullcontext
import io
import json
from pathlib import Path
import sys
import tempfile
import socket
import threading
import urllib.error
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("agent_runtime", Path(__file__).parents[1] / "AgentRuntime/openrouter_agent.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class HermesStreamingTests(unittest.TestCase):
    def test_answer_deltas_are_flushed_before_reading_the_next_event(self):
        class FlushedOutput(io.BytesIO):
            flushed = b""

            def flush(self):
                self.flushed = self.getvalue()

        output = FlushedOutput()
        chunks = ["Hello", " 🦊", "\n```swift\n", 'print("hi")']

        def response_lines():
            for index, chunk in enumerate(chunks):
                yield b"event: assistant.delta\n"
                yield ("data: " + json.dumps({"delta": chunk}) + "\n").encode()
                events = [json.loads(line) for line in output.flushed.splitlines()]
                self.assertEqual(events, [
                    {"type": "delta", "request_id": "r", "kind": "content", "text": text}
                    for text in chunks[:index + 1]
                ])
                yield b"\n"
            yield b"event: run.completed\n"
            yield b"data: {}\n"

        with patch.object(runtime, "ensure_hermes_gateway"), patch.object(runtime, "ensure_hermes_session"), \
                patch.object(runtime, "api_request", return_value=nullcontext(response_lines())):
            runtime.stream_hermes_session({"request_id": "r", "session_id": "chat", "token": "test",
                "model": "test", "prompt": "Hello"}, output)
        events = [json.loads(line) for line in output.flushed.splitlines()]
        self.assertEqual(events[-1], {"type": "complete"})
        self.assertEqual(len(events), len(chunks) + 1)


class HermesCancellationTests(unittest.TestCase):
    request = {"operation": "hermes_session_chat", "request_id": "r", "session_id": "chat",
               "token": "test", "model": "test", "prompt": "Hello"}

    def test_disconnect_stops_upstream_while_stream_is_waiting(self):
        stopped = threading.Event()
        response_closed = threading.Event()
        calls = []

        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): self.close()
            def close(self): response_closed.set()
            def __iter__(self):
                yield b'event: run.started\n'
                yield b'data: {"run_id":"run_test"}\n'
                yield b'event: assistant.delta\n'
                yield b'data: {"run_id":"run_test","delta":"Partial answer"}\n'
                if not stopped.wait(3):
                    raise RuntimeError("Stop did not reach Hermes while waiting for the next delta")
                yield b'event: run.completed\n'
                yield b'data: {"run_id":"run_test"}\n'

        def api(path, **kwargs):
            calls.append((path, kwargs))
            if path.endswith("/stop"):
                stopped.set()
                return nullcontext()
            return Response()

        server, client = socket.socketpair()
        client.settimeout(4)
        with patch.object(runtime, "save_agent_soul"), patch.object(runtime, "ensure_hermes_gateway"), \
                patch.object(runtime, "ensure_hermes_session"), patch.object(runtime, "api_request", side_effect=api):
            worker = threading.Thread(target=runtime.handle_connection, args=(server,))
            worker.start()
            try:
                client.sendall((json.dumps(self.request) + "\n").encode())
                self.assertEqual(json.loads(client.recv(4096))["text"], "Partial answer")
                client.close()
                self.assertTrue(stopped.wait(3), "client disconnect must call the real Hermes stop endpoint")
            finally:
                client.close()
                worker.join(6)
        self.assertFalse(worker.is_alive())
        self.assertTrue(response_closed.is_set())
        stop_calls = [call for call in calls if call[0].endswith("/stop")]
        self.assertEqual(stop_calls, [("/v1/runs/run_test/stop", {"method": "POST", "body": {}, "timeout": 5})])

    def test_stop_before_gateway_start_does_not_start_generation(self):
        cancellation = runtime.StreamCancellation()
        cancellation.cancel()
        with patch.object(runtime, "ensure_hermes_gateway") as gateway, patch.object(runtime, "api_request") as api:
            runtime.stream_hermes_session(self.request, io.BytesIO(), cancellation)
        gateway.assert_not_called()
        api.assert_not_called()

    def test_stop_before_run_id_arrives_is_not_lost(self):
        cancellation = runtime.StreamCancellation()
        output = io.BytesIO()
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def close(self): pass
            def __iter__(self):
                cancellation.cancel()
                yield b'event: run.started\n'
                yield b'data: {"run_id":"run_early"}\n'
                raise AssertionError("cancelled stream should not read more events")
        with patch.object(runtime, "save_agent_soul"), patch.object(runtime, "ensure_hermes_gateway"), \
                patch.object(runtime, "ensure_hermes_session"), patch.object(runtime, "api_request", return_value=Response()), \
                patch.object(runtime, "stop_hermes_run") as stop:
            runtime.stream_hermes_session(self.request, output, cancellation)
            cancellation.cancel()
        stop.assert_called_once_with("run_early")
        self.assertEqual(output.getvalue(), b"")

    def test_stop_retries_hermes_registration_race(self):
        conflict = urllib.error.HTTPError("test", 409, "not active yet", {}, io.BytesIO())
        with patch.object(runtime, "api_request", side_effect=[conflict, nullcontext()]) as api, \
                patch.object(runtime.time, "sleep"):
            runtime.stop_hermes_run("run_queued")
        self.assertEqual(api.call_count, 2)

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
            with patch.object(runtime, "ensure_hermes_gateway", side_effect=gateway):
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
