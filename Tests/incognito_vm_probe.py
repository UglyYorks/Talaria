"""Run inside the disposable Linux VM: python3 -B this_file.py /path/to/hermes/venv/bin/python.

Uses a loopback model fixture only. Checks real Hermes turns, read-only memory,
plugin enforcement, RAM history, and close cleanup without model-provider calls.
"""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from hermes_gateway import HermesGateway
from incognito_runtime import get_gateway, close

requests = []


class Model(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        data = json.dumps({"object": "list", "data": [{"id": "fixture-model", "object": "model"}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        requests.append(body)
        has_tool = any(message.get("role") == "tool" for message in body.get("messages", []))
        message = {"role": "assistant", "content": "PRIVATE_REPLY"} if has_tool else {
            "role": "assistant", "content": None, "tool_calls": [{"id": "memory-test", "type": "function",
            "function": {"name": "memory", "arguments": json.dumps({"action": "add", "target": "memory", "content": "PRIVATE_MEMORY_MARKER"})}}]}
        reason = "stop" if has_tool else "tool_calls"
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream" if body.get("stream") else "application/json")
        self.end_headers()
        if body.get("stream"):
            if not has_tool:
                message["tool_calls"][0]["index"] = 0
            chunk = {"id": "fixture", "object": "chat.completion.chunk", "created": 0, "model": "fixture-model",
                     "choices": [{"index": 0, "delta": message, "finish_reason": None}]}
            self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
            chunk["choices"] = [{"index": 0, "delta": {}, "finish_reason": reason}]
            self.wfile.write(("data: " + json.dumps(chunk) + "\n\ndata: [DONE]\n\n").encode())
        else:
            self.wfile.write(json.dumps({"id": "fixture", "object": "chat.completion", "created": 0,
              "model": "fixture-model", "choices": [{"index": 0, "message": message, "finish_reason": reason}],
              "usage": {"prompt_tokens": 100, "completion_tokens": 10, "total_tokens": 110}}).encode())


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Model)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    source = Path(tempfile.mkdtemp(prefix="private-test-source-", dir="/workspace"))
    identity = "private-integration-window-1234"
    try:
        (source / "memories").mkdir()
        (source / "memories" / "MEMORY.md").write_text("readonly-fixture-fact")
        (source / "config.yaml").write_text(json.dumps({
            "model": {"provider": "custom", "default": "fixture-model", "base_url": f"http://127.0.0.1:{server.server_port}/v1"},
            "platform_toolsets": {"cli": ["memory"], "tui": ["memory"]}}))
        gateway = get_gateway(identity, Path(sys.argv[1]), dict(os.environ), source, HermesGateway)
        profile = gateway.home
        events = []
        gateway.run("private-chat", "custom::fixture-model", "PRIVATE_TRANSCRIPT_MARKER", lambda kind, text: events.append((kind, text)))
        assert any("PRIVATE_REPLY" in text for kind, text in events), events
        assert any("readonly-fixture-fact" in json.dumps(body.get("messages")) for body in requests), "Existing memory was not readable"
        assert any("read-only" in str(message.get("content")) for body in requests for message in body.get("messages", []) if message.get("role") == "tool"), "Memory tool was not blocked"
        assert (source / "memories" / "MEMORY.md").read_text() == "readonly-fixture-fact"
        assert (profile / "memories" / "MEMORY.md").read_text() == "readonly-fixture-fact"
        assert not (source / "state.db").exists(), "Transcript escaped to persistent profile"
        assert (profile / "state.db").exists(), "Fixture did not exercise Hermes persistence"
        close(identity)
        assert not profile.exists(), "Close left the private profile behind"
        print("PRIVATE_TURN_PASS", flush=True)
    finally:
        close(identity)
        server.shutdown()
        shutil.rmtree(source)


if __name__ == "__main__":
    main()
