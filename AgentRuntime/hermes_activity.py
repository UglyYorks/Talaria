"""Bounded, session-scoped presentation of Hermes's out-of-turn TUI events.

This cache observes the existing JSON-RPC stream independently of a prompt's
listener. It never runs a model, reads a transcript, or owns a child process.
"""
from collections import OrderedDict
import hashlib
import re
import threading

MAX_ROWS = 80
MAX_SESSIONS = 64
MAX_OUTPUT = 8000
_ESCAPES = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]|\x1b[@-_]")
_UNFINISHED_ESCAPE = re.compile(r"\x1b(?:\][^\x07\x1b]*\x1b?|\[[0-?]*[ -/]*)?$")
_CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
TERMINAL_STATES = {"completed", "failed", "stopped", "interrupted", "ended"}


def visible_text(value, limit=1000):
    if not isinstance(value, str):
        return ""
    text = _ESCAPES.sub("", _UNFINISHED_ESCAPE.sub("", value))
    text = _CONTROL.sub("", text).replace("\r\n", "\n")
    # A carriage return redraws the current terminal line.
    return "\n".join(line.rsplit("\r", 1)[-1] for line in text.split("\n"))[-limit:]


class HermesActivity:
    def __init__(self):
        self.lock = threading.RLock()
        self.sessions = OrderedDict()
        self.revision = 0

    def _session(self, sid):
        if sid not in self.sessions:
            self.sessions[sid] = {"rows": OrderedDict(), "raw": {}, "versions": {}, "turn": 0}
        self.sessions.move_to_end(sid)
        while len(self.sessions) > MAX_SESSIONS:
            self.sessions.popitem(last=False)
        return self.sessions[sid]

    def _put(self, session, row):
        rows = session["rows"]
        identity = row["id"]
        previous = rows.get(identity, {})
        row = {**previous, **row}
        # A late output chunk or replayed start must not reopen a finished task.
        if previous.get("state") in TERMINAL_STATES and row.get("state") in {"running", "preparing"}:
            row["state"] = previous["state"]
        if previous == row:
            return
        self.revision += 1
        row["updated"] = str(self.revision)
        rows[identity] = row
        session["versions"][identity] = self.revision
        while len(rows) > MAX_ROWS:
            # Prefer evicting finished rows to work that is still running.
            oldest = next((key for key, value in rows.items() if value.get("state") in TERMINAL_STATES), next(iter(rows)))
            rows.pop(oldest)
            session["raw"].pop(oldest, None)
            session["versions"].pop(oldest, None)

    def event(self, event):
        sid, kind, payload = event.get("session_id"), event.get("type"), event.get("payload")
        if not isinstance(sid, str) or not sid or not isinstance(kind, str) or not isinstance(payload, dict):
            return
        if kind not in {"message.start", "agent.terminal.output", "terminal.close", "status.update",
                        "tool.progress", "background.complete", "browser.progress"} and not kind.startswith("subagent."):
            return
        with self.lock:
            session = self._session(sid)
            if kind == "message.start":
                session["turn"] += 1
                return
            if kind == "agent.terminal.output":
                pid = visible_text(payload.get("process_id"), 200)
                chunk = payload.get("chunk")
                if not pid or not isinstance(chunk, str) or not chunk:
                    return
                identity = "process:" + pid
                raw = (session["raw"].get(identity, "") + chunk)[-MAX_OUTPUT - 512:]
                session["raw"][identity] = raw
                previous = session["rows"].get(identity, {})
                self._put(session, {"id": identity, "kind": "process", "name": previous.get("name", "Terminal"),
                                    "state": "running", "output": visible_text(raw, MAX_OUTPUT)})
                return
            if kind == "terminal.close":
                # Closing a Hermes terminal tab does not mean the process exited.
                return
            if kind.startswith("subagent."):
                identifier = visible_text(payload.get("subagent_id") or payload.get("child_session_id"), 200)
                if not identifier:
                    identifier = str(payload.get("delegation_id") or session["turn"])[:200] + ":" + str(payload.get("task_index", 0))[:20]
                identity = "agent:" + identifier
                previous = session["rows"].get(identity, {})
                state = "preparing" if kind == "subagent.spawn_requested" else "running"
                if kind == "subagent.complete":
                    status = visible_text(payload.get("status"), 100)
                    state = ("failed" if status in {"error", "failed", "timeout", "timed_out"} else
                             "stopped" if status in {"cancelled", "canceled", "stopped"} else
                             "interrupted" if status == "interrupted" else "completed")
                row = {"id": identity, "kind": "agent", "name": visible_text(payload.get("goal"), 200) or previous.get("name", "Delegated agent"),
                       "state": state}
                for key in ("parent_id", "model"):
                    if visible_text(payload.get(key), 200): row[key] = visible_text(payload[key], 200)
                detail = visible_text(payload.get("tool_preview") or payload.get("text"))
                tool = visible_text(payload.get("tool_name"), 200)
                if detail or tool:
                    row["detail"] = (tool + " · " + detail) if tool and detail else tool or detail
                summary = visible_text(payload.get("summary"))
                if summary: row["summary"] = summary
                self._put(session, row)
                return
            text = visible_text(payload.get("text") or payload.get("message") or payload.get("preview"), 2000)
            if not text:
                return
            category = visible_text(payload.get("kind"), 100) or kind
            # Process notifications are distinct; spinner/loop progress replaces its last line.
            suffix = hashlib.sha256(text.encode()).hexdigest()[:16] if category == "process" else category
            if kind == "background.complete": suffix = visible_text(payload.get("task_id"), 200) or suffix
            name = {"process": "Process update", "background.complete": "Background task", "browser.progress": "Browser",
                    "tool.progress": visible_text(payload.get("name"), 200) or "Tool update"}.get(category, "Hermes update")
            self._put(session, {"id": "notice:" + suffix, "kind": "notice", "name": name,
                                "state": "failed" if payload.get("level") == "error" else "completed", "detail": text})

    def reconcile_processes(self, sid, processes, observed_revision):
        with self.lock:
            session = self._session(sid)
            for process in processes[-MAX_ROWS:]:
                if not isinstance(process, dict): continue
                pid = visible_text(process.get("session_id"), 200)
                if not pid: continue
                identity = "process:" + pid
                status = process.get("status")
                state = "running" if status == "running" else "failed" if process.get("exit_code") not in (None, 0) else "completed"
                row = {"id": identity, "kind": "process", "name": visible_text(process.get("command"), 200) or "Terminal",
                       "state": state, "detail": visible_text(process.get("cwd"))}
                if status != "running": row["summary"] = "Exited" + (f" · code {process['exit_code']}" if isinstance(process.get("exit_code"), int) else "")
                # The reader can receive output while process.list is in flight.
                if session["versions"].get(identity, 0) <= observed_revision:
                    tail = process.get("output_tail") or process.get("output_preview")
                    if isinstance(tail, str) and tail:
                        raw = session["raw"].get(identity, "")
                        if not raw.endswith(tail): raw = tail[-MAX_OUTPUT - 512:]
                        session["raw"][identity] = raw
                        row["output"] = visible_text(raw, MAX_OUTPUT)
                self._put(session, row)

    def snapshot(self, sid):
        with self.lock:
            session = self.sessions.get(sid)
            return {"activities": [dict(row) for row in session["rows"].values()] if session else [], "revision": self.revision}
