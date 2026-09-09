import concurrent.futures
import contextlib
import contextvars
import io
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "AgentRuntime"))
import hermes_notifications as module
from hermes_notifications import Notifications, HermesSources
import talaria_agent as worker


ARGS = {"title": "Payment pending", "summary": "Invoice 123 is due tomorrow.",
        "urgency": "medium", "finding_key": "gmail:account-1:message-123:payment",
        "change_key": "unpaid:50:2026-09-10"}


class Sources:
    def verify(self, task_id, session_id, tool_call_id, args):
        # Encodes trusted execution order in the fixture's run ID, not model args.
        _, job, run = task_id.split(":")
        return {"task_id": job, "task_name": "Daily Email", "source_kind": "cron", "run_id": run,
                "session_id": session_id, "message_id": int(tool_call_id[4:]), "tool_call_id": tool_call_id,
                "run_order": float(run), "execution_status": "running"}

    def open(self, notification, related_notifications=()):
        return {"notification": notification, "related": related_notifications}


class NotificationLedgerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.service = Notifications(self.home, Sources())

    def create(self, run=1, call=1, job="job", **changes):
        return self.service.create({**ARGS, **changes}, task_id=f"cron:{job}:{run}",
                                   session_id=f"session-{job}-{run}", tool_call_id=f"call{call}")

    def test_retry_survives_restart_and_does_not_undo_read_state(self):
        first = self.create()
        note = first["notification"]
        self.service.set_read({"id": note["id"], "version": 1, "read": True})
        self.service = Notifications(self.home, Sources())
        self.assertEqual(self.create(), first)
        self.assertTrue(self.service.sync({})["notifications"][0]["is_read"])
        self.assertEqual(len(self.service.sync({})["notifications"]), 1)

    def test_unchanged_findings_preserve_anchor_text_time_read_and_sequence(self):
        note = self.create()["notification"]
        expected = self.service.set_read({"id": note["id"], "version": 1, "read": True})
        unchanged = self.create(run=2, call=2, title="Different wording", summary="Paraphrase", urgency="low")
        self.assertEqual(unchanged, {"status": "unchanged", "notification": expected})
        self.assertEqual(self.service.sync({})["notifications"], [expected])

    def test_changes_and_escalations_version_and_reopen(self):
        first = self.create()["notification"]
        self.service.set_read({"id": first["id"], "version": 1, "read": True})
        second = self.create(run=2, call=2, change_key="paid:50:2026-09-10")["notification"]
        self.assertEqual((second["id"], second["version"], second["is_read"]), (first["id"], 2, False))
        self.assertEqual(second["created_at"], first["created_at"])
        third = self.create(run=3, call=3, change_key="paid:50:2026-09-10", urgency="high")["notification"]
        self.assertEqual(third["version"], 3)
        old_source = self.service.open_source({"id": first["id"], "version": 1})["notification"]
        self.assertEqual(old_source["session_id"], "session-job-1")
        self.assertEqual(self.service.set_read({"id": first["id"], "version": 1, "read": True}), third)

    def test_older_run_cannot_roll_back_after_newer_unchanged_observation(self):
        self.create(run=1)
        self.create(run=3, call=3)
        late = self.create(run=2, call=2, change_key="stale value", urgency="high")
        self.assertEqual(late["status"], "stale")
        self.assertEqual(late["notification"]["version"], 1)
        self.assertEqual(self.create(run=2, call=2, change_key="stale value", urgency="high"), late)

    def test_same_run_calls_have_stable_order(self):
        self.create(call=2)
        self.assertEqual(self.create(call=1, change_key="older")["status"], "stale")
        self.assertEqual(self.create(call=3, change_key="newer")["notification"]["version"], 2)

    def test_same_finding_is_separate_in_different_tasks(self):
        self.create(job="a")
        self.create(job="b")
        notes = self.service.sync({})["notifications"]
        self.assertEqual({note["task_id"] for note in notes}, {"a", "b"})
        self.assertEqual(len({note["id"] for note in notes}), 2)

    def test_concurrent_retries_are_atomic_across_service_instances(self):
        def attempt(_):
            service = Notifications(self.home, Sources())
            return service.create(ARGS, task_id="cron:job:1", session_id="session-job-1", tool_call_id="call1")
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(attempt, range(24)))
        self.assertTrue(all(result == results[0] for result in results))
        self.assertEqual(len(self.service.sync({})["notifications"]), 1)

    def test_transaction_failure_rolls_back_receipt_and_finding(self):
        with patch.object(self.service, "next_sequence", side_effect=sqlite3.OperationalError("disk full")):
            with self.assertRaises(sqlite3.OperationalError):
                self.create()
        self.assertEqual(self.service.sync({})["notifications"], [])
        self.assertEqual(self.create()["status"], "created")

    def test_sync_pages_changes_and_resets_when_database_generation_changes(self):
        for index in range(5):
            self.create(call=index + 1, finding_key=f"finding-{index}")
        first = self.service.sync({"limit": 2})
        second = self.service.sync({"generation": first["generation"], "cursor": first["cursor"], "limit": 2})
        third = self.service.sync({"generation": second["generation"], "cursor": second["cursor"], "limit": 2})
        self.assertTrue(first["reset"])
        self.assertFalse(second["reset"])
        self.assertEqual([len(part["notifications"]) for part in (first, second, third)], [2, 2, 1])
        self.assertEqual([part["has_more"] for part in (first, second, third)], [True, True, False])
        empty = self.service.sync({"generation": third["generation"], "cursor": third["cursor"]})
        self.assertEqual(empty["notifications"], [])
        self.service.path.unlink()
        reset = self.service.sync({"generation": third["generation"], "cursor": third["cursor"]})
        self.assertTrue(reset["reset"])
        self.assertNotEqual(reset["generation"], third["generation"])

    def test_validation_rejects_model_attribution_and_invalid_paging(self):
        for change in ({"urgency": "urgent"}, {"title": " "}, {"summary": "x" * 2001}, {"task_id": "other"}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.create(**change)
        for params in ({"limit": 0}, {"limit": 1001}, {"cursor": True}, {"cursor": -1}):
            with self.subTest(params=params), self.assertRaises(ValueError):
                self.service.sync(params)


class HermesSourceTests(unittest.TestCase):
    def setUp(self):
        self.database = Mock()
        self.database.get_session.return_value = {"id": "stored", "title": "Run", "model": "test-model"}
        self.database.resolve_resume_session_id.return_value = "continuation"
        self.database._resume_lineage_ids.return_value = ["stored", "continuation"]
        self.row = {"id": 42, "role": "assistant", "content": "", "timestamp": 100,
                    "tool_calls": [{"id": "call-42", "function": {"name": module.TOOL, "arguments": json.dumps(ARGS)}}]}
        self.database.get_messages.return_value = [self.row]
        def fetch(_lineage, _clause, **_kwargs):
            return [{"session_id": "stored", "active": 1, "compacted": 0, **row}
                    for row in self.database.get_messages.return_value]
        def dedupe(rows):
            groups, first = {}, {}
            for row in rows:
                key = (row.get("role"), json.dumps(row.get("content")), row.get("timestamp"),
                       row.get("tool_call_id"), json.dumps(row.get("tool_calls")), row.get("tool_name"))
                first[key] = min(first.get(key, row["id"]), row["id"])
                if key not in groups or (row["active"], row["id"]) > (groups[key]["active"], groups[key]["id"]):
                    groups[key] = row
            return [groups[key] for key in sorted(groups, key=first.__getitem__)]
        self.database._fetch_conversation_rows.side_effect = fetch
        self.database._dedupe_display_generations.side_effect = dedupe
        self.database._row_to_message_dict.side_effect = lambda row, **_kwargs: dict(row)
        display = types.SimpleNamespace(project_compaction_message_for_display=lambda row: None if row.get("_compressed_summary") else row)
        self.display_patch = patch.dict(sys.modules, {"agent.compaction_display": display})
        self.display_patch.start()
        self.addCleanup(self.display_patch.stop)
        @contextlib.contextmanager
        def database(_home):
            yield self.database
        self.db_patch = patch.object(module, "_session_db", database)
        self.db_patch.start()
        self.addCleanup(self.db_patch.stop)
        self.jobs = types.SimpleNamespace(get_job=Mock(return_value={"id": "job", "name": "Daily Email"}))
        self.executions = types.SimpleNamespace(get_execution=Mock(return_value={"job_id": "job", "status": "running",
                                                                                "claimed_at": "2026-09-09T01:00:00Z"}))
        self.modules_patch = patch.dict(sys.modules, {"cron.jobs": self.jobs, "cron.executions": self.executions})
        self.modules_patch.start()
        self.addCleanup(self.modules_patch.stop)
        self.source = HermesSources("/unused")

    def verify(self):
        return self.source.verify("cron:job:run", "stored", "call-42", ARGS)

    def test_trusted_attribution_and_durable_tool_only_anchor(self):
        source = self.verify()
        self.assertEqual((source["task_id"], source["run_id"], source["session_id"], source["message_id"]),
                         ("job", "run", "stored", 42))
        notification = {**source, **ARGS, "id": "n", "version": 1}
        opened = self.source.open(notification)
        self.assertEqual(opened["source_session_id"], "stored")
        self.assertEqual(opened["continuation_session_id"], "continuation")
        self.assertEqual(opened["messages"][0]["content"], "")
        self.assertEqual(opened["messages"][0]["source_message_id"], 42)
        self.assertEqual(opened["messages"][0]["notification"]["tool_call_id"], "call-42")

    def test_multiple_calls_project_separate_cards_with_prose_once(self):
        self.row["content"] = "Two findings."
        self.row["tool_calls"].append({"id": "call-43", "function": {"name": module.TOOL, "arguments": json.dumps(ARGS)}})
        note = {**self.verify(), **ARGS, "id": "a", "version": 1}
        other = {**note, "id": "b", "tool_call_id": "call-43"}
        messages = self.source.open(note, [other])["messages"]
        self.assertEqual([message["content"] for message in messages], ["Two findings.", ""])
        self.assertEqual([message["notification"]["id"] for message in messages], ["a", "b"])

    def test_missing_or_mismatched_source_is_rejected(self):
        self.executions.get_execution.return_value["job_id"] = "other"
        with self.assertRaisesRegex(ValueError, "does not belong"):
            self.verify()
        self.executions.get_execution.return_value["job_id"] = "job"
        self.row["tool_calls"][0]["function"]["arguments"] = json.dumps({**ARGS, "title": "Not the call"})
        with self.assertRaisesRegex(ValueError, "does not match"):
            self.verify()
        self.database.get_messages.return_value = []
        with self.assertRaisesRegex(ValueError, "has not been persisted"):
            self.verify()

    def test_bridge_call_uses_same_canonical_source(self):
        self.row["tool_calls"][0]["function"] = {"name": "tool_call", "arguments": json.dumps({"name": module.TOOL, "arguments": ARGS})}
        bridge = types.SimpleNamespace(resolve_underlying_call=Mock(return_value=(module.TOOL, ARGS, None)))
        with patch.dict(sys.modules, {"tools.tool_search": bridge}):
            self.assertEqual(self.verify()["message_id"], 42)

    def test_large_history_is_complete_from_one_finite_snapshot(self):
        note = {**self.verify(), **ARGS, "id": "a", "version": 1}
        stored = [{"id": number, "role": "user", "content": f"Message {number}"}
                  for number in range(1, 2502)]
        stored[41] = self.row
        self.database.get_messages.return_value = stored
        opened = self.source.open(note)
        self.assertEqual(len(opened["messages"]), 2501)
        self.assertEqual(opened["messages"][0]["source_message_id"], 1)
        self.assertEqual(opened["messages"][-1]["source_message_id"], 2501)
        self.assertEqual(opened["messages"][41]["notification"]["tool_call_id"], "call-42")
        self.assertNotIn("history_truncated", opened)
        self.database._fetch_conversation_rows.assert_called_once_with(["stored", "continuation"], "", with_session_id=True)
        self.database.get_messages_around.assert_not_called()

    def test_compression_lineage_preserves_original_anchor_and_completed_followups(self):
        note = {**self.verify(), **ARGS, "id": "a", "version": 1}
        other = {**note, "id": "b", "session_id": "continuation", "message_id": 46, "tool_call_id": "descendant-call"}
        other_call = [{"id": "descendant-call"}]
        self.database.resolve_resume_session_id.return_value = "continuation-2"
        self.database._resume_lineage_ids.return_value = ["stored", "continuation", "continuation-2"]
        self.database.get_session.side_effect = lambda sid: {"id": sid, "title": "Run", "model": sid,
                                                             "started_at": 90, "last_active": 300 if sid == "continuation-2" else 100}
        self.database.get_messages.return_value = [
            {**self.row, "active": 0, "compacted": 1},
            {"id": 43, "session_id": "continuation", "role": "user", "content": "handoff", "_compressed_summary": True},
            {**self.row, "id": 44, "session_id": "continuation"},
            {"id": 45, "session_id": "continuation", "role": "user", "content": "Again", "timestamp": 200},
            {"id": 46, "session_id": "continuation", "role": "assistant", "content": "First follow-up", "timestamp": 201, "tool_calls": other_call},
            {"id": 47, "session_id": "continuation-2", "role": "user", "content": "handoff", "_compressed_summary": True},
            {**self.row, "id": 48, "session_id": "continuation-2"},
            {"id": 49, "session_id": "continuation-2", "role": "user", "content": "Again", "timestamp": 200},
            {"id": 50, "session_id": "continuation-2", "role": "assistant", "content": "First follow-up", "timestamp": 201, "tool_calls": other_call},
            {"id": 51, "session_id": "continuation-2", "role": "user", "content": "Again", "timestamp": 250},
            {"id": 52, "session_id": "continuation-2", "role": "assistant", "content": "Second follow-up", "timestamp": 251},
        ]
        related = Mock(return_value=[other])
        opened = self.source.open(note, related)
        related.assert_called_once_with(["stored", "continuation", "continuation-2"])
        self.assertEqual(opened["source_session_id"], "stored")
        self.assertEqual(opened["session"]["id"], "stored")
        self.assertEqual(opened["continuation_session_id"], "continuation-2")
        self.assertEqual(opened["model"], "continuation-2")
        self.assertEqual(opened["session"]["updated_at"], module._date(300))
        self.assertEqual([message["content"] for message in opened["messages"]],
                         ["", "Again", "First follow-up", "Again", "Second follow-up"])
        self.assertEqual(opened["messages"][0]["source_message_id"], 42)
        self.assertEqual(opened["messages"][0]["notification"]["tool_call_id"], "call-42")
        self.assertEqual(opened["messages"][2]["source_message_id"], 46)
        self.assertEqual(opened["messages"][2]["notification"]["tool_call_id"], "descendant-call")

    def test_unrelated_branch_cannot_replace_source_lineage(self):
        note = {**self.verify(), **ARGS, "id": "a", "version": 1}
        self.database._resume_lineage_ids.return_value = ["unrelated-branch"]
        with self.assertRaisesRegex(ValueError, "conversation lineage"):
            self.source.open(note)

    def test_other_notifications_in_original_session_remain_visible(self):
        source = self.verify()
        note = {**source, **ARGS, "id": "a", "version": 1}
        previous = {**note, "id": "previous", "message_id": 10, "tool_call_id": "earlier-call"}
        earlier_row = {"id": 10, "role": "assistant", "content": "", "tool_calls": [{"id": "earlier-call"}]}
        self.database.get_messages.return_value = [earlier_row, self.row]
        opened = self.source.open(note, [previous])
        self.assertEqual([message["notification"]["id"] for message in opened["messages"]], ["previous", "a"])

    def test_dispatch_context_cannot_be_supplied_by_the_model(self):
        session = contextvars.ContextVar("session", default="")
        call = contextvars.ContextVar("call", default="")
        context = types.SimpleNamespace(_approval_session_id=session, _approval_tool_call_id=call)
        constants = types.SimpleNamespace(get_hermes_home=lambda: Path("/unused"))
        with patch.dict(sys.modules, {"tools.approval_context": context, "hermes_constants": constants}), \
                patch.object(module, "Notifications") as service:
            service.return_value.create.return_value = {"status": "created"}
            with self.assertRaisesRegex(ValueError, "trusted notification session"):
                module.create_notification(ARGS, task_id="cron:job:run", session_id="stored")
            session.set("stored")
            with self.assertRaisesRegex(ValueError, "trusted notification tool call"):
                module.create_notification(ARGS, task_id="cron:job:run", session_id="stored")
            call.set("call-42")
            module.create_notification(ARGS, task_id="cron:job:run", session_id="stored")
            service.return_value.create.assert_called_once_with(ARGS, task_id="cron:job:run", session_id="stored", tool_call_id="call-42")


class NotificationTransportTests(unittest.TestCase):
    def test_failed_setup_keeps_saved_scheduler_gated(self):
        with tempfile.TemporaryDirectory() as home:
            service = Notifications(home)
            with patch.object(module, "setup", side_effect=RuntimeError("unsupported Hermes")):
                with self.assertRaisesRegex(RuntimeError, "unsupported Hermes"):
                    service.prepare("Native description")
                self.assertFalse(service.ready.is_set())
            with patch.object(module, "setup"):
                service.prepare("Native description")
                self.assertTrue(service.ready.is_set())

    def test_worker_uses_only_tui_rpc_and_reports_unavailable_method(self):
        output = io.BytesIO()
        with patch.object(worker, "tui_gateway") as gateway:
            gateway.return_value.call.return_value = {"notifications": [], "cursor": 0}
            request = {"operation": "hermes_notifications", "request_id": "r", "params": {"action": "sync", "cursor": 0}}
            worker.handle_request(request, output)
            gateway.return_value.call.assert_called_once_with("talaria.notifications.sync", {"cursor": 0})
            self.assertEqual(json.loads(output.getvalue().splitlines()[-1])["type"], "complete")
            gateway.return_value.call.side_effect = RuntimeError("method unavailable")
            output = io.BytesIO()
            worker.handle_request(request, output)
            self.assertIn("method unavailable", json.loads(output.getvalue())["message"])

    def test_rpc_registers_async_without_initializing_profile(self):
        methods = {}
        server = types.SimpleNamespace(_LONG_HANDLERS=frozenset(),
            method=lambda name: lambda fn: methods.setdefault(name, fn),
            _ok=lambda rid, result: {"result": result}, _err=lambda rid, code, error: {"error": error})
        with tempfile.TemporaryDirectory() as home:
            module.register_rpc(server, home)
            self.assertEqual(list(Path(home).iterdir()), [])
            self.assertEqual(set(methods), {"talaria.notifications.sync", "talaria.notifications.set_read", "talaria.notifications.open_source"})
            self.assertEqual(server._LONG_HANDLERS, set(methods))
            with patch.object(module, "setup") as setup:
                result = methods["talaria.notifications.sync"]("r", {"notification_tool_description": "Native prompt"})
                setup.assert_called_once_with(Path(home), "Native prompt")
                self.assertEqual(result["result"]["notifications"], [])
            note = {"id": "n", "version": 1, "is_read": True}
            with patch.object(Notifications, "set_read", return_value=note):
                methods.clear()
                module.register_rpc(server, home)
                self.assertEqual(methods["talaria.notifications.set_read"]("r", {})["result"], {"notification": note})


if __name__ == "__main__":
    unittest.main()
