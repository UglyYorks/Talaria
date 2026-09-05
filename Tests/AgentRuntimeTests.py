import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("agent_runtime", Path(__file__).parents[1] / "AgentRuntime/openrouter_agent.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


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
