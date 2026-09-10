"""Private runtime isolation and request-routing regression tests (no inference)."""
import base64
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "AgentRuntime"))
import incognito_runtime as privacy
from incognito_entry import private_config
from incognito_policy import before_tool
import talaria_agent


class IncognitoTests(unittest.TestCase):
    def test_read_memory_without_external_ingestion_or_background_review(self):
        cfg = private_config({"memory": {"provider": "honcho", "memory_char_limit": 1234},
                              "auxiliary": {"title": {"model": "keep"}},
                              "plugins": {"enabled": ["recorder"]}, "mcp_servers": {"recorder": {}},
                              "model": "keep-model"})
        self.assertTrue(cfg["memory"]["memory_enabled"])
        self.assertTrue(cfg["memory"]["user_profile_enabled"])
        self.assertEqual(cfg["memory"]["provider"], "")
        self.assertEqual(cfg["memory"]["memory_char_limit"], 1234)
        self.assertFalse(cfg["auxiliary"]["background_review"]["enabled"])
        self.assertEqual(cfg["auxiliary"]["title"]["model"], "keep")
        self.assertEqual(cfg["mcp_servers"], {})
        self.assertEqual(cfg["plugins"]["enabled"], [])
        self.assertEqual(cfg["model"], "keep-model")
        self.assertEqual(before_tool("memory", args={"action": "add"})["action"], "block")
        self.assertIsNone(before_tool("web_search"))

    def test_cannot_use_disk_backed_temp_or_swap(self):
        for mounts, swaps in [("1 1 0:0 / / rw - ext4 disk rw", "Filename\n"),
                               ("1 1 0:0 / /tmp rw - tmpfs tmpfs rw", "Filename\nswapfile file 1 0 -1\n")]:
            with patch.object(Path, "read_text", side_effect=[mounts, swaps]):
                with self.assertRaises(RuntimeError): privacy.require_ram_storage()

    def test_private_requests_never_fall_back_to_shared_gateway(self):
        output = io.BytesIO()
        with patch.object(privacy, "get_gateway", side_effect=RuntimeError("isolation unavailable")), \
             patch.object(talaria_agent, "hermes_executable", return_value="/fixture/bin/hermes"), \
             patch.object(talaria_agent, "HermesGateway") as shared:
            talaria_agent.handle_request({"incognito_id": "private-window-1234", "operation": "incognito_request", "incognito_operation": "models"}, output)
            shared.assert_not_called()
        self.assertIn("isolation unavailable", output.getvalue().decode())
        self.assertEqual(privacy.scope.get(), "")

    def test_private_scope_restored_after_error_and_mutations_refused(self):
        for operation in ("shell_command", "hermes_credentials", "hermes_plugins", "install_hermes"):
            output = io.BytesIO()
            with patch.object(talaria_agent, "_handle_request") as dispatch:
                talaria_agent.handle_request({"incognito_id": "private-window-1234", "operation": "incognito_request", "incognito_operation": operation}, output)
                dispatch.assert_not_called()
            self.assertEqual(json.loads(output.getvalue())["type"], "error")
            self.assertEqual(privacy.scope.get(), "")

    def test_private_flag_without_versioned_operation_is_rejected(self):
        with patch.object(talaria_agent, "_handle_request") as dispatch:
            output = io.BytesIO()
            talaria_agent.handle_request({"operation": "hermes_session_chat", "incognito_id": "private-window-1234"}, output)
            dispatch.assert_not_called()
            self.assertEqual(json.loads(output.getvalue())["type"], "error")

    def test_closed_window_cannot_resurrect_on_late_request(self):
        identity = "closed-private-window-1234"
        privacy.close(identity)
        with patch.object(privacy, "require_ram_storage") as storage:
            with self.assertRaises(RuntimeError):
                privacy.get_gateway(identity, None, {}, Path("/fixture"), Mock())
            storage.assert_not_called()

    def test_abandoned_window_expires_but_live_window_remains(self):
        stale, live = "abandoned-window-1234", "active-window-123456"
        expired = {"touched": 0}
        current = {"touched": 95}
        with patch.dict(privacy._runtimes, {stale: expired, live: current}, clear=True), \
             patch.object(privacy, "_destroy") as destroy:
            privacy.reap_expired(now=100)
            self.assertNotIn(stale, privacy._runtimes)
            self.assertIn(live, privacy._runtimes)
            destroy.assert_called_once_with(expired)
        self.assertIn(stale, privacy._closed)

    def test_attachments_stay_beneath_private_root(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder) / ".hermes"
            home.mkdir()
            gateway = Mock(home=home)
            rows = privacy.upload(gateway, [{"name": "note.txt", "data": base64.b64encode(b"private").decode()}])
            path = Path(rows[0]["guestPath"])
            self.assertTrue(path.is_relative_to(Path(folder)))
            self.assertEqual(path.read_bytes(), b"private")
            with self.assertRaises(ValueError):
                privacy.upload(gateway, [{"name": "../escape", "data": ""}])


if __name__ == "__main__":
    unittest.main()
