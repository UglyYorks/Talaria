import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from typing import Optional, List
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "AgentRuntime"))
from hermes_automations import Automations, register, METHOD
import talaria_agent as worker


class AutomationsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.service = Automations(self.home)
        self.calls = []
        def cronjob(action: str, job_id: Optional[str] = None, name: Optional[str] = None,
                    prompt: Optional[str] = None, schedule: Optional[str] = None,
                    repeat: Optional[int] = None, skills: Optional[List[str]] = None,
                    continuity: Optional[bool] = None, model: Optional[str] = None,
                    include_disabled: bool = False):
            self.calls.append(dict(locals()))
            return json.dumps({"success": True, "job_id": "a"})
        self.tools = types.SimpleNamespace(cronjob=cronjob, CRONJOB_SCHEMA={"parameters": {"properties": {
            "prompt": {"type": "string", "description": "Instructions"}}}},
            _format_job=lambda job: {"job_id": job["id"], "name": job["name"], "schedule": "display only", "prompt_preview": "truncated"})
        self.jobs = types.SimpleNamespace(
            list_jobs=Mock(return_value=[]), get_job=Mock(return_value={"id": "a"}),
            get_cron_output_dir=lambda: self.home / "cron/output")
        self.patch = patch.dict(sys.modules, {"tools.cronjob_tools": self.tools, "cron.jobs": self.jobs})
        self.patch.start(); self.addCleanup(self.patch.stop)

    def test_capabilities_include_user_owned_fields_and_types(self):
        fields = {row["key"]: row for row in self.service.fields()}
        self.assertEqual(fields["model"]["type"], "string")
        self.assertEqual(fields["repeat"]["type"], "integer")
        self.assertEqual(fields["skills"]["type"], "array")
        self.assertEqual(fields["continuity"]["type"], "boolean")
        self.assertNotIn("include_disabled", fields)
        self.assertEqual(fields["prompt"]["description"], "Instructions")

    def test_full_prompt_and_schedule_round_trip_without_truncation(self):
        for schedule, expected in [({"kind": "cron", "expr": "0 9 * * 1-5"}, "0 9 * * 1-5"),
                                   ({"kind": "interval", "minutes": 90}, "every 90m"),
                                   ({"kind": "once", "run_at": "2030-01-01T12:00:00+10:00"}, "2030-01-01T12:00:00+10:00")]:
            self.jobs.list_jobs.return_value = [{"id": "a", "name": "job", "prompt": "x" * 300,
                "schedule": schedule, "repeat": {"times": 4, "completed": 2}}]
            row = self.service.jobs()[0]
            self.assertEqual(row["values"]["schedule"], expected)
            self.assertEqual(row["values"]["prompt"], "x" * 300)
            self.assertEqual(row["values"]["repeat"], 4)
            self.jobs.list_jobs.assert_called_with(include_disabled=True)

    def test_update_preserves_omitted_fields_and_explicit_clears(self):
        self.service.handle({"action": "update", "job_id": "a", "values": {"skills": [], "continuity": False}})
        self.assertEqual(self.calls[-1]["skills"], [])
        self.assertIs(self.calls[-1]["continuity"], False)
        self.assertIsNone(self.calls[-1]["prompt"])
        self.assertIsNone(self.calls[-1]["schedule"])

    def test_unsupported_fields_and_missing_jobs_fail_before_mutation(self):
        with self.assertRaisesRegex(ValueError, "does not support"):
            self.service.handle({"action": "create", "values": {"unavailable": True}})
        self.jobs.get_job.return_value = None
        with self.assertRaisesRegex(ValueError, "no longer exists"):
            self.service.handle({"action": "remove", "job_id": "missing"})
        self.assertFalse(self.calls)

    def test_nested_hermes_errors_are_not_success(self):
        self.tools.cronjob = lambda action, job_id: json.dumps({"success": False, "error": "invalid cron"})
        with self.assertRaisesRegex(ValueError, "invalid cron"):
            self.service.handle({"action": "pause", "job_id": "a"})

    def test_output_is_confined_and_bounded(self):
        directory = self.home / "cron/output/a"; directory.mkdir(parents=True)
        (directory / "run.md").write_text("# Complete output\nHello")
        self.assertEqual(self.service.handle({"action": "output", "job_id": "a", "name": "run.md"})["text"], "# Complete output\nHello")
        for name in ["../../secrets.md", "/etc/passwd", "run.txt"]:
            with self.assertRaises(ValueError): self.service.handle({"action": "output", "job_id": "a", "name": name})
        (self.home / "outside.md").write_text("private")
        (directory / "link.md").symlink_to(self.home / "outside.md")
        with self.assertRaises(ValueError): self.service.handle({"action": "output", "job_id": "a", "name": "link.md"})

    def test_gateway_registration_is_async_and_reports_errors(self):
        methods = {}
        server = types.SimpleNamespace(_LONG_HANDLERS=frozenset(),
            method=lambda name: lambda fn: methods.setdefault(name, fn),
            _ok=lambda rid, result: {"id": rid, "result": result},
            _err=lambda rid, code, error: {"id": rid, "error": error})
        register(server, self.home)
        self.assertIn(METHOD, server._LONG_HANDLERS)
        self.assertIn("error", methods[METHOD]("request", {"action": "unknown"}))

    def test_worker_uses_only_tui_rpc_and_surfaces_unavailable_method(self):
        with patch.object(worker, "tui_gateway") as gateway:
            gateway.return_value.call.return_value = {"jobs": []}
            output = io.BytesIO()
            worker.handle_request({"operation": "hermes_automations", "params": {"action": "list"}, "request_id": "r"}, output)
            gateway.return_value.call.assert_called_once_with(METHOD, {"action": "list"}, timeout=600)
            self.assertEqual(json.loads(output.getvalue().splitlines()[-1])["type"], "complete")
            gateway.return_value.call.side_effect = RuntimeError("method unavailable")
            output = io.BytesIO()
            worker.handle_request({"operation": "hermes_automations", "params": {"action": "list"}, "request_id": "r"}, output)
            self.assertIn("method unavailable", json.loads(output.getvalue())["message"])


if __name__ == "__main__": unittest.main()
