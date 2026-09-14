"""Session activity stays visible independently of turn listeners and model work."""
import io
import json
from pathlib import Path
import queue
import sys
import threading
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "AgentRuntime"))
from hermes_activity import HermesActivity, MAX_OUTPUT, MAX_ROWS, MAX_SESSIONS, visible_text
from hermes_gateway import HermesGateway, RPCError
from hermes_rpc_transport import HermesRPCTransport
import talaria_agent as worker
import incognito_runtime


class ActivityTests(unittest.TestCase):
    def setUp(self):
        self.activity = HermesActivity()

    def emit(self, kind, payload, sid="one"):
        self.activity.event({"session_id": sid, "type": kind, "payload": payload})

    def rows(self, sid="one"):
        return self.activity.snapshot(sid)["activities"]

    def test_live_terminal_output_is_bounded_and_split_ansi_is_hidden(self):
        self.emit("agent.terminal.output", {"process_id": "p", "chunk": "Building\n\x1b[3"})
        self.assertEqual(self.rows()[0]["output"], "Building\n")
        self.emit("agent.terminal.output", {"process_id": "p", "chunk": "2mTests passed\x1b[0m\n"})
        self.assertEqual(self.rows()[0]["output"], "Building\nTests passed\n")
        self.emit("agent.terminal.output", {"process_id": "p", "chunk": "z" * (MAX_OUTPUT * 2)})
        self.assertEqual(len(self.rows()[0]["output"]), MAX_OUTPUT)
        self.assertEqual(visible_text("\x1b]8;;https://example.com\x1b\\label\x1b]8;;\x1b\\"), "label")
        self.assertEqual(visible_text("10%\r20%\r100%\r\nDone"), "100%\nDone")

    def test_completion_is_authoritative_and_poll_cannot_overwrite_newer_output(self):
        self.emit("agent.terminal.output", {"process_id": "p", "chunk": "old\n"})
        revision = self.activity.snapshot("one")["revision"]
        self.emit("agent.terminal.output", {"process_id": "p", "chunk": "new\n"})
        self.activity.reconcile_processes("one", [{"session_id": "p", "command": "codex exec task", "cwd": "/work",
            "status": "running", "output_tail": "old\n"}], revision)
        self.assertEqual(self.rows()[0]["output"], "old\nnew\n")
        self.activity.reconcile_processes("one", [{"session_id": "p", "status": "exited", "exit_code": 2}], 999)
        self.emit("agent.terminal.output", {"process_id": "p", "chunk": "late"})
        self.assertEqual(self.rows()[0]["state"], "failed")
        self.assertIn("code 2", self.rows()[0]["summary"])
        self.emit("terminal.close", {"process_id": "p"})
        self.assertEqual(self.rows()[0]["state"], "failed")

    def test_poll_hydrates_quiet_processes_without_notifications(self):
        self.activity.reconcile_processes("one", [{"session_id": "p", "command": "codex", "status": "running"}], 0)
        self.assertEqual(self.rows()[0]["state"], "running")
        self.activity.reconcile_processes("one", [{"session_id": "p", "command": "codex", "status": "exited", "exit_code": 0}], 10)
        self.assertEqual(self.rows()[0]["state"], "completed")

    def test_delegated_agents_keep_distinct_identity_and_progress_after_parent_turn(self):
        self.emit("subagent.spawn_requested", {"subagent_id": "a", "goal": "Fix tests", "parent_id": "root"})
        self.emit("subagent.start", {"subagent_id": "a", "model": "test-model"})
        self.emit("subagent.tool", {"subagent_id": "a", "tool_name": "terminal", "tool_preview": "pytest"})
        self.emit("subagent.thinking", {"subagent_id": "b", "goal": "Review changes", "text": "Checking"})
        self.emit("message.complete", {"text": "Work continues"})
        self.emit("subagent.progress", {"subagent_id": "a", "text": "8 tests passed"})
        self.emit("subagent.complete", {"subagent_id": "a", "status": "success", "summary": "Fixed"})
        self.emit("subagent.start", {"subagent_id": "a"})
        a, b = self.rows()
        self.assertEqual((a["state"], a["name"], a["model"], a["parent_id"]), ("completed", "Fix tests", "test-model", "root"))
        self.assertEqual(a["summary"], "Fixed")
        self.assertEqual(b["state"], "running")

    def test_long_goals_keep_the_start_and_completion_notice_is_not_duplicated(self):
        goal = "Implement input suggestions. " + "Additional instructions " * 140
        self.emit("status.update", {"kind": "process", "text": "Subagent Task Completed: " + goal})
        self.emit("subagent.start", {"subagent_id": "a", "goal": goal})
        self.emit("subagent.complete", {"subagent_id": "a", "goal": goal, "status": "completed", "text": "Finished", "summary": "Finished"})
        row, = self.rows()
        self.assertTrue(row["name"].startswith("Implement input suggestions."))
        self.assertLessEqual(len(row["name"]), 100)
        self.assertEqual(row["summary"], "Finished")
        self.assertEqual(row["detail"], "")

    def test_notifications_deduplicate_and_sessions_do_not_mix(self):
        for _ in range(3): self.emit("status.update", {"kind": "process", "text": "Codex finished"})
        self.emit("status.update", {"kind": "process", "text": "Other finished"}, "two")
        self.emit("background.complete", {"task_id": "task", "text": "Background summary"})
        self.emit("tool.progress", {"name": "terminal", "preview": "Waiting"})
        self.emit("browser.progress", {"message": "Loading page"})
        self.assertEqual(len(self.rows()), 4)
        self.assertEqual(len(self.rows("two")), 1)
        self.assertNotIn("Other finished", str(self.rows()))
        for index in range(MAX_ROWS * 2): self.emit("status.update", {"kind": "process", "text": str(index)})
        self.assertEqual(len(self.rows()), MAX_ROWS)
        for index in range(MAX_SESSIONS * 2): self.emit("status.update", {"text": "update"}, str(index))
        self.assertEqual(len(self.activity.sessions), MAX_SESSIONS)

    def test_malformed_payloads_do_not_break_the_reader(self):
        for payload in [None, [], "text", {}, {"process_id": {}, "chunk": []}, {"subagent_id": [], "status": {}}]:
            for kind in ("agent.terminal.output", "subagent.complete", "status.update"):
                self.emit(kind, payload)
        self.assertTrue(all(isinstance(row["id"], str) for row in self.rows()))

    def test_transport_captures_events_after_parent_completion_without_listener(self):
        frames = [{"method": "event", "params": {"session_id": "one", "type": kind, "payload": payload}}
                  for kind, payload in [("message.complete", {"text": "Launched"}),
                       ("agent.terminal.output", {"process_id": "p", "chunk": "Still working"}),
                       ("status.update", {"kind": "process", "text": "Finished"})]]
        transport = HermesRPCTransport.__new__(HermesRPCTransport)
        transport.lock = threading.RLock()
        transport.pending = {}; transport.listeners = {}
        transport.event_handler = self.activity.event
        transport.process = Mock(stdout=io.StringIO("\n".join(json.dumps(frame) for frame in frames)))
        transport._read()
        self.assertEqual(self.rows()[0]["output"], "Still working")
        self.assertEqual(self.rows()[1]["detail"], "Finished")

    def test_snapshot_uses_alias_and_tui_only_without_inference(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.lock = threading.RLock()
        gateway.sessions = {"chat": {"id": "one"}}
        gateway.mappings = {"chat": "stored"}
        gateway.activity = self.activity
        gateway.call = Mock(return_value={"processes": []})
        self.emit("status.update", {"text": "Update"})
        self.assertTrue(gateway.activity_snapshot("stored")["available"])
        gateway.call.assert_called_once_with("process.list", {"session_id": "one"}, timeout=10)
        gateway.call.reset_mock()
        self.assertFalse(gateway.activity_snapshot("unknown")["available"])
        gateway.call.assert_not_called()
        gateway.call.side_effect = RPCError({"message": "Missing process.list", "code": -32601})
        with self.assertRaisesRegex(RuntimeError, "Missing process.list"): gateway.activity_snapshot("chat")

    def test_worker_reads_existing_runtime_and_never_starts_one(self):
        with patch.object(worker, "_tui_gateway", None), patch.object(worker, "tui_gateway") as start:
            output = io.BytesIO()
            worker.handle_request({"operation": "hermes_activity", "request_id": "r", "session_id": "chat"}, output)
            frames = [json.loads(line) for line in output.getvalue().splitlines()]
            self.assertEqual([frame["type"] for frame in frames], ["result", "complete"])
            self.assertFalse(frames[0]["result"]["available"])
            start.assert_not_called()

    def test_worker_relays_background_host_request_before_finishing_poll(self):
        gateway = Mock()
        gateway.process.poll.return_value = None
        gateway.activity_snapshot.return_value = {"available": True, "activities": []}
        request = {"request_id": "host", "session_id": "runtime", "command": "pwd"}
        gateway.poll_host_commands.side_effect = lambda sid, deliver: deliver(request)
        with patch.object(worker, "_tui_gateway", gateway):
            output = io.BytesIO()
            worker.hermes_activity({"request_id": "poll", "session_id": "chat", "host_commands": True}, output)
        frames = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([frame["type"] for frame in frames], ["delta", "result", "complete"])
        self.assertEqual(frames[0]["payload"], request)
        self.assertEqual(frames[0]["kind"], "host_command")

    def test_private_activity_cannot_read_normal_gateway(self):
        identity = "private-window-123456"
        private = Mock(); private.process.poll.return_value = None
        private.activity_snapshot.return_value = {"available": True, "activities": []}
        token = incognito_runtime.scope.set(identity)
        try:
            with patch.dict(incognito_runtime._runtimes, {identity: {"gateway": private}}), patch.object(worker, "_tui_gateway") as normal:
                worker.hermes_activity({"request_id": "r", "session_id": "chat"}, io.BytesIO())
                private.activity_snapshot.assert_called_once_with("chat")
                normal.activity_snapshot.assert_not_called()
        finally:
            incognito_runtime.scope.reset(token)


if __name__ == "__main__": unittest.main()
