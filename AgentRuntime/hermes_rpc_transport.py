"""Subprocess JSON-RPC framing and event routing, independent of session policy."""
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import uuid


class RPCError(RuntimeError):
    def __init__(self, payload):
        self.code = payload.get("code")
        super().__init__(payload.get("message") or "Hermes request failed.")


class HermesRPCTransport:
    def __init__(self, python, environment, home, entry_module="talaria_gateway_entry"):
        self.home = home
        self.lock = threading.RLock()
        self.disconnected = False
        self.pending = {}
        self.listeners = {}
        environment = dict(environment)
        environment["PYTHONPATH"] = os.pathsep.join(filter(None, [str(Path(__file__).parent), environment.get("PYTHONPATH")]))
        with (home / "talaria-tui-gateway.log").open("ab") as log:
            self.process = subprocess.Popen(
                [str(python), "-u", "-m", entry_module],
                cwd=str(home.parent), env=environment, stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=log, text=True, bufsize=1,
                start_new_session=entry_module == "incognito_entry",
            )
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        try:
            for line in self.process.stdout:
                try:
                    frame = json.loads(line)
                except ValueError:
                    continue  # Startup diagnostics must not corrupt the JSON stream.
                if not isinstance(frame, dict):
                    continue
                with self.lock:
                    if frame.get("id") in self.pending:
                        self.pending[frame["id"]].put(frame)
                    elif frame.get("method") == "event":
                        event = frame.get("params", {})
                        if not isinstance(event, dict): continue
                        listener = self.listeners.get(event.get("session_id"))
                        if listener is not None:
                            listener.put(event)
        finally:
            with self.lock:
                self.disconnected = True
                failure = {"error": {"message": "Hermes gateway disconnected. Retry the request."}}
                for pending in self.pending.values():
                    pending.put(failure)
                for listener in self.listeners.values():
                    listener.put({"type": "error", "payload": failure["error"]})

    def call(self, method, params=None, timeout=120):
        request_id = uuid.uuid4().hex
        result_queue = queue.Queue()
        with self.lock:
            if self.disconnected or self.process.poll() is not None:
                raise RuntimeError("Hermes gateway is not running. Retry the request.")
            self.pending[request_id] = result_queue
            try:
                self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": request_id,
                                                    "method": method, "params": params or {}}) + "\n")
                self.process.stdin.flush()
            except (OSError, ValueError):
                self.pending.pop(request_id, None)
                raise RuntimeError("Could not write to the Hermes gateway.")
        try:
            response = result_queue.get(timeout=timeout)
            if "error" in response:
                raise RPCError(response["error"])
            return response.get("result", {})
        except queue.Empty:
            raise RuntimeError(f"Hermes timed out during {method}.")
        finally:
            with self.lock:
                self.pending.pop(request_id, None)
