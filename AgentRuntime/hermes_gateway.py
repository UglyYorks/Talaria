"""Hermes's native JSON-RPC transport, shared by chat and slash commands.

Protocol reference: NousResearch/hermes-agent, tui_gateway/entry.py and
tui_gateway/methods_tools.py (commands.catalog, command.dispatch, slash.exec).
"""
import json
from datetime import datetime, timezone
import queue
import subprocess
import threading
import time
import uuid


class RPCError(RuntimeError):
    def __init__(self, payload):
        self.code = payload.get("code")
        super().__init__(payload.get("message") or "Hermes request failed.")


class HermesGateway:
    def __init__(self, python, environment, home):
        self.home = home
        self.lock = threading.RLock()
        self.pending = {}
        self.listeners = {}
        self.sessions = {}
        self.waiting = {}
        self.session_locks = {}
        self.mapping_path = home / "talaria-sessions.json"
        self.mappings = json.loads(self.mapping_path.read_text()) if self.mapping_path.exists() else {}
        with (home / "talaria-tui-gateway.log").open("ab") as log:
            self.process = subprocess.Popen(
                [str(python), "-u", "-m", "tui_gateway.entry"],
                cwd=str(home.parent), env=environment, stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=log, text=True, bufsize=1,
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
                        listener = self.listeners.get(event.get("session_id"))
                        if listener is not None:
                            listener.put(event)
        finally:
            with self.lock:
                failure = {"error": {"message": "Hermes gateway disconnected. Retry the request."}}
                for pending in self.pending.values():
                    pending.put(failure)
                for listener in self.listeners.values():
                    listener.put({"type": "error", "payload": failure["error"]})

    def call(self, method, params=None, timeout=120):
        request_id = uuid.uuid4().hex
        result_queue = queue.Queue()
        with self.lock:
            if self.process.poll() is not None:
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

    def catalog(self):
        result = self.call("commands.catalog")
        if not isinstance(result.get("pairs"), list):
            raise RuntimeError("This Hermes version does not provide a command catalogue. Update Hermes and retry.")
        return result

    def history_sessions(self):
        # session.list has a limit but no offset. Expand the window until complete;
        # never silently restrict search to its default 200 rows.
        limit = 200
        while True:
            result = self.call("session.list", {"limit": limit})
            rows = result.get("sessions")
            if not isinstance(rows, list) or any(not isinstance(row, dict) or not row.get("id") for row in rows):
                raise RuntimeError("Hermes returned an invalid session list.")
            if len(rows) < limit:
                break
            if limit >= 102400:
                raise RuntimeError("Hermes history is too large to load completely.")
            limit *= 2
        with self.lock:
            aliases = {}
            for chat, stored in self.mappings.items():
                if stored not in aliases or chat != stored:
                    aliases[stored] = chat
        sessions = []
        seen = set()
        for row in rows:
            stored = row["id"]
            if stored in seen:
                continue
            seen.add(stored)
            sessions.append({**row, "hermes_session_id": aliases.get(stored, stored),
                             "title": row.get("title") or row.get("preview") or "Untitled session",
                             "created_at": self.history_date(row.get("started_at")),
                             "updated_at": self.history_date(row.get("last_active") or row.get("started_at"))})
        return {"sessions": sessions}

    @staticmethod
    def history_date(value):
        if isinstance(value, (int, float)):
            return datetime.fromtimestamp(value, timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        return value if isinstance(value, str) else ""

    def history_session(self, stored):
        if not stored:
            raise RuntimeError("A Hermes session ID is required.")
        with self.lock:
            live = next((state for chat, state in self.sessions.items()
                         if self.mappings.get(chat, chat) == stored), None)
        if live:
            sid = live["id"]
            model = live["model"]
        else:
            # Explicit resume: a missing history row must never create a new session.
            result = self.call("session.resume", {"session_id": stored})
            model = (result.get("info") or {}).get("model") or ""
            with self.lock:
                chat_id = next((chat for chat, target in self.mappings.items() if target == stored), stored)
            sid = self._remember(chat_id, result, model)
        result = self.call("session.history", {"session_id": sid})
        messages = result.get("messages")
        if not isinstance(messages, list):
            raise RuntimeError("Hermes returned an invalid transcript.")
        transcript = []
        for message in messages:
            if not isinstance(message, dict):
                raise RuntimeError("Hermes returned an invalid transcript message.")
            if message.get("role") not in {"user", "assistant", "system"}:
                continue
            text = message.get("text", "")
            if not isinstance(text, str):
                raise RuntimeError("Hermes returned an invalid transcript message.")
            transcript.append({"role": message["role"], "content": text,
                               "thinking": message.get("reasoning") or message.get("reasoning_content") or "",
                               "created_at": self.history_date(message.get("timestamp"))})
        return {"messages": transcript, "model": model}

    def delete_history_session(self, stored):
        if not stored:
            raise RuntimeError("A Hermes session ID is required.")
        with self.lock:
            aliases = [chat for chat in self.sessions if self.mappings.get(chat, chat) == stored]
            if any(self.sessions[chat]["id"] in self.listeners for chat in aliases):
                raise RuntimeError("Wait for this Hermes session to finish before deleting it.")
            runtime_ids = {self.sessions[chat]["id"] for chat in aliases}
        for sid in runtime_ids:
            self.call("session.close", {"session_id": sid})
        with self.lock:
            for chat in aliases:
                self.sessions.pop(chat, None)
                self.waiting.pop(chat, None)
        result = self.call("session.delete", {"session_id": stored})
        if not result.get("deleted"):
            raise RuntimeError("Hermes did not confirm session deletion.")
        with self.lock:
            self.mappings = {chat: target for chat, target in self.mappings.items() if target != stored}
            temporary = self.mapping_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(self.mappings))
            temporary.replace(self.mapping_path)
        return {"deleted": stored}

    def model_options(self):
        result = self.call("model.options", {"explicit_only": True})
        if not isinstance(result.get("providers"), list):
            raise RuntimeError("Hermes returned an invalid model catalogue.")
        return result

    def generate_text(self, model, instructions, user_input):
        # A private draft runtime supplies the chosen supporting model to llm.oneshot.
        # No prompt.submit, conversation history, or persistent Talaria mapping is used.
        created = self.call("session.create", {"model": model, "provider": "openrouter", "source": "talaria", "hidden": True})
        sid = created.get("session_id")
        if not sid:
            raise RuntimeError("Hermes did not create a supporting-model session.")
        try:
            # Bare model + --session waits for the lazy agent build and explicitly avoids
            # persisting a global model change. oneshot can then inherit its runtime.
            configured = self.call("config.set", {"session_id": sid, "key": "model", "value": model + " --session"})
            if configured.get("confirm_required"):
                raise RuntimeError(configured.get("confirm_message") or "Hermes requires confirmation of the supporting model.")
            result = self.call("llm.oneshot", {"session_id": sid, "instructions": instructions,
                                               "input": user_input, "max_tokens": 1024})
            text = result.get("text")
            if not isinstance(text, str) or not text.strip():
                raise RuntimeError("Hermes returned an empty text-generation response.")
            return text
        finally:
            # Cleanup must not conceal the original inference error.
            try:
                self.call("session.close", {"session_id": sid})
            except (OSError, RuntimeError):
                pass

    def _remember(self, chat_id, result, model):
        sid = result.get("session_id")
        stored = result.get("stored_session_id") or result.get("session_key") or result.get("resumed")
        if not sid or not stored:
            raise RuntimeError("Hermes returned a session without its persistent identity.")
        with self.lock:
            self.sessions[chat_id] = {"id": sid, "model": model}
            self.mappings[chat_id] = stored
            temporary = self.mapping_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(self.mappings))
            temporary.replace(self.mapping_path)
        return sid

    def _apply_session_model(self, sid, model):
        # A bare model waits for Hermes' lazy agent build. Supplying --provider
        # skips that wait and can race a resumed agent loading its old model.
        result = self.call("config.set", {"session_id": sid, "key": "model",
                                          "value": f"{model} --session"})
        if result.get("confirm_required"):
            raise RuntimeError(result.get("confirm_message") or "Hermes requires confirmation of this model change.")
        if result.get("value") != model:
            raise RuntimeError(f"Hermes did not accept the requested model {model}.")
        status = self.call("session.status", {"session_id": sid})
        if f"Model: {model} (openrouter)" not in status.get("output", "").splitlines():
            raise RuntimeError(f"Hermes has not activated {model}. Wait for the current response to finish and retry.")
        # This audit contains model identifiers only, never prompts or credentials.
        with (self.home / "talaria-model-switches.jsonl").open("a") as log:
            log.write(json.dumps({"session_id": sid, "model": model, "verified": True, "time": time.time()}) + "\n")

    def session(self, chat_id, model, force_model=False):
        if chat_id not in self.sessions:
            try:
                result = self.call("session.resume", {"session_id": self.mappings.get(chat_id, chat_id)})
            except RPCError as exc:
                if exc.code != 4007:
                    raise
                result = self.call("session.create", {"model": model, "provider": "openrouter", "source": "talaria"})
            # Both create and resume are lazy. Pin and verify after loading before
            # remembering a selection, including the very first turn.
            self._remember(chat_id, result, "")
        state = self.sessions[chat_id]
        if force_model or state["model"] != model:
            self._apply_session_model(state["id"], model)
            state["model"] = model
        return state["id"]

    def select_model(self, chat_id, model):
        with self.lock:
            session_lock = self.session_locks.setdefault(chat_id, threading.Lock())
        if not session_lock.acquire(blocking=False):
            raise RuntimeError("Wait for the current response to finish before switching models.")
        try:
            return self.session(chat_id, model, force_model=True)
        finally:
            session_lock.release()

    def command(self, chat_id, sid, text, model, depth=0):
        if depth >= 8:
            raise RuntimeError("Hermes command alias cycle detected.")
        parts = text.lstrip("/").split(maxsplit=1)
        if not parts:
            raise RuntimeError("Choose a Hermes command after /.")
        name, arg = parts[0].lower(), parts[1] if len(parts) > 1 else ""
        catalog = self.catalog()
        canonical = catalog.get("canon", {}).get("/" + name, "/" + name).lstrip("/")
        known = {pair[0] for pair in catalog["pairs"] if isinstance(pair, list) and pair}
        if "/" + canonical not in known and "/" + name not in known:
            raise RuntimeError(f"Unknown Hermes command: /{name}")
        params = {"session_id": sid}
        # These commands are host actions in Hermes's TUI, not slash-worker actions.
        if canonical in {"new", "reset", "clear"}:
            result = self.call("session.create", {"model": model, "provider": "openrouter", "source": "talaria", "title": arg})
            self._remember(chat_id, result, model)
            return {"output": "Started a new Hermes session."}
        if canonical in {"resume"} and arg:
            result = self.call("session.resume", {"session_id": arg})
            self._remember(chat_id, result, model)
            return {"output": "Resumed Hermes session " + self.mappings[chat_id] + "."}
        if canonical in {"sessions", "resume"}:
            result = self.call("session.list")
            return {"output": json.dumps(result, ensure_ascii=False, indent=2)}
        if canonical == "model" and arg:
            result = self.call("config.set", {**params, "key": "model", "value": arg})
            return {"output": result.get("confirm_message") or result.get("warning") or "Model: " + str(result.get("value", arg))}
        if canonical in {"title", "rename"}:
            result = self.call("session.title", {**params, **({"title": arg} if arg else {})})
            return {"output": "Session title: " + str(result.get("title") or "Untitled")}
        if canonical == "save":
            result = self.call("session.save", params)
            return {"output": "Saved conversation to " + str(result.get("file", "Hermes"))}
        if canonical in {"branch", "fork"}:
            result = self.call("session.branch", {**params, **({"title": arg} if arg else {})})
            self._remember(chat_id, result, model)
            return {"output": "Branched Hermes session " + self.mappings[chat_id] + "."}
        if canonical in {"stop", "interrupt"}:
            self.call("session.interrupt", params)
            return {"output": "Interrupted the Hermes session."}
        if canonical in {"quit", "exit"}:
            self.call("session.close", params)
            self.sessions.pop(chat_id, None)
            return {"output": "Closed the Hermes session."}
        try:
            result = self.call("command.dispatch", {**params, "name": name, "arg": arg})
        except RPCError as exc:
            # Only the explicit dispatcher miss may fall through. Never retry a failed
            # command that could already have changed state or executed a custom action.
            if exc.code != 4018 or not str(exc).startswith("not a quick/plugin/bundle/skill command:"):
                raise
            result = self.call("slash.exec", {**params, "command": text})
        if result.get("type") == "alias":
            target = result.get("target", "").strip()
            if not target:
                raise RuntimeError("Hermes returned an empty command alias.")
            return self.command(chat_id, sid, target + (" " + arg if arg else ""), model, depth + 1)
        return result

    def run(self, chat_id, model, text, delta, cancellation=None):
        if cancellation and cancellation.cancelled():
            return
        with self.lock:
            session_lock = self.session_locks.setdefault(chat_id, threading.Lock())
        if not session_lock.acquire(blocking=False):
            name = text.split(maxsplit=1)[0].lower()
            if name not in {"/stop", "/interrupt", "/steer"} or chat_id not in self.sessions:
                raise RuntimeError("Hermes is busy. Use /stop or /steer, or wait for the current turn.")
            result = self.command(chat_id, self.sessions[chat_id]["id"], text, model)
            delta("content", result.get("output") or "Hermes received the command.")
            return
        try:
            sid = self.session(chat_id, model)
            if cancellation and cancellation.cancelled():
                return
            waiting = self.waiting.get(chat_id)
            if waiting:
                sid, events, kind, payload = waiting
                if kind == "approval.request":
                    choice = {"/approve": "once", "/approve once": "once", "/approve session": "session",
                              "/approve always": "always", "/deny": "deny"}.get(text.strip().lower())
                    if choice not in payload.get("choices", ["once", "deny"]):
                        raise RuntimeError("Reply /approve or /deny to the pending Hermes command.")
                    result = self.call("approval.respond", {"session_id": sid, "request_id": payload.get("request_id"), "choice": choice})
                else:
                    result = self.call("clarify.respond", {"session_id": sid, "request_id": payload.get("request_id"), "answer": text})
                self.waiting.pop(chat_id, None)
                if result.get("expired") or (kind == "approval.request" and result.get("resolved") is False):
                    with self.lock:
                        self.listeners.pop(sid, None)
                    raise RuntimeError("Hermes's input request expired. Send your request again.")
            elif text.startswith("/"):
                result = self.command(chat_id, sid, text, model)
                for key in ("notice", "output", "warning"):
                    if result.get(key):
                        delta("content", str(result[key]) + "\n")
                if result.get("type") == "prefill":
                    delta("content", result.get("message", ""))
                    return
                if result.get("type") not in {"send", "skill"}:
                    return
                text = result.get("message", "")
                if not text:
                    raise RuntimeError("Hermes returned an empty command prompt.")
            if not waiting:
                events = queue.Queue()
                with self.lock:
                    if sid in self.listeners:
                        raise RuntimeError("This Hermes session is already running in another chat.")
                    self.listeners[sid] = events
            try:
                if cancellation and cancellation.cancelled():
                    return
                if not waiting:
                    self.call("prompt.submit", {"session_id": sid, "text": text})
                if cancellation:
                    # Bind only after submission; a Stop during submit is delivered here.
                    # Drain its terminal event before releasing this session's lock, so
                    # a following turn cannot receive the interrupted turn's events.
                    cancellation.on_cancel(lambda: self.call("session.interrupt", {"session_id": sid}))
                deadline = time.monotonic() + 600
                streamed = ""
                while True:
                    event = events.get(timeout=max(0.01, deadline - time.monotonic()))
                    kind, payload = event.get("type"), event.get("payload") or {}
                    if cancellation and cancellation.cancelled():
                        if kind in {"message.complete", "error"}:
                            return
                        continue
                    if kind == "message.delta":
                        chunk = payload.get("text", "")
                        streamed += chunk
                        delta("content", chunk)
                    elif kind in {"reasoning.delta", "thinking.delta"}:
                        delta("thinking", payload.get("text", ""))
                    elif kind == "message.complete":
                        if payload.get("status") == "error":
                            raise RuntimeError(payload.get("text") or "Hermes turn failed.")
                        final = payload.get("text", "")
                        if not streamed:
                            delta("content", final)
                        elif final.startswith(streamed):
                            delta("content", final[len(streamed):])
                        elif final and not streamed.endswith(final):
                            delta("content", "\n" + final)
                        return
                    elif kind == "error":
                        raise RuntimeError(payload.get("message") or "Hermes turn failed.")
                    elif kind in {"approval.request", "clarify.request"}:
                        self.waiting[chat_id] = (sid, events, kind, payload)
                        question = payload.get("question") or payload.get("command") or json.dumps(payload.get("questions", []), ensure_ascii=False)
                        suffix = "\nReply /approve or /deny." if kind == "approval.request" else "\nReply with your answer."
                        delta("content", "\n" + question + suffix)
                        return
                    elif kind in {"sudo.request", "secret.request"}:
                        self.call("session.interrupt", {"session_id": sid})
                        raise RuntimeError("Hermes needs a secure credential. Configure it in the Hermes terminal, then retry; do not paste secrets into chat.")
            except queue.Empty:
                self.call("session.interrupt", {"session_id": sid})
                raise RuntimeError("Hermes turn timed out.")
            finally:
                with self.lock:
                    if chat_id not in self.waiting:
                        self.listeners.pop(sid, None)

        finally:
            session_lock.release()
