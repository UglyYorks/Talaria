import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "AgentRuntime"))
from hermes_notes import Notes, MAX_BYTES, register
import talaria_agent as worker


class NotesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)
        self.notes = Notes(self.workspace)

    def create(self, content="# Ideas\n\nA thought 🌱", identity="ideas.md"):
        return self.notes.request({"action": "create", "id": identity, "content": content})["note"]

    def test_markdown_round_trip_restart_and_external_edits(self):
        note = self.create()
        file = self.workspace / "notes/ideas.md"
        self.assertEqual(file.read_text(), note["content"])
        self.assertEqual(note["title"], "Ideas")
        self.assertEqual(note["preview"], "A thought 🌱")
        self.notes = Notes(self.workspace)
        read = self.notes.request({"action": "read", "id": note["id"]})["note"]
        self.assertEqual(read, note)
        file.write_text("# Edited by the agent\n\nKeep this.")
        listing = self.notes.request({"action": "list"})["notes"]
        self.assertEqual(listing[0]["title"], "Edited by the agent")
        self.assertNotEqual(listing[0]["revision"], note["revision"])
        self.assertNotIn("content", listing[0])
        external = self.workspace / "notes/agent-created.md"
        external.write_text("# Agent note\n\n" + "x" * 500 + " Full text needle")
        self.assertEqual(self.notes.request({"action": "list", "query": "NEEDLE"})["notes"][0]["id"], external.name)

    def test_stale_save_and_delete_keep_both_draft_and_agent_file(self):
        note = self.create()
        file = self.workspace / "notes/ideas.md"
        file.write_text("# Agent version")
        for action in ("save", "delete"):
            result = self.notes.request({"action": action, "id": note["id"],
                                         "revision": note["revision"], "content": "# User draft"})
            self.assertTrue(result["conflict"])
            self.assertEqual(result["note"]["content"], "# Agent version")
            self.assertEqual(file.read_text(), "# Agent version")
        file.unlink()
        result = self.notes.request({"action": "save", "id": note["id"], "revision": note["revision"], "content": "draft"})
        self.assertTrue(result["conflict"])
        self.assertIsNone(result["note"])
        self.assertFalse(file.exists())

    def test_create_retry_save_and_recoverable_delete(self):
        note = self.create()
        self.assertEqual(self.create(), note)
        self.assertTrue(self.notes.request({"action": "create", "id": note["id"], "content": "different"})["conflict"])
        updated = self.notes.request({"action": "save", "id": note["id"], "revision": note["revision"],
                                      "content": "# Renamed title\n\nNew body"})["note"]
        self.assertEqual(updated["id"], note["id"])
        self.assertEqual(updated["title"], "Renamed title")
        result = self.notes.request({"action": "delete", "id": updated["id"], "revision": updated["revision"]})
        self.assertEqual(Path(result["trash_path"]).read_text(), updated["content"])
        self.assertEqual(self.notes.request({"action": "list"})["notes"], [])
        self.assertFalse(list(self.notes.root.glob(".save-*")))

    def test_invalid_filenames_and_links_cannot_escape_notes(self):
        self.notes.request({"action": "list"})
        for identity in ("../outside.md", "/tmp/escape.md", ".hidden.md", "x/y.md", "x\\y.md", "x\x00.md", "x.txt", "x\n.md", None):
            with self.subTest(identity=identity), self.assertRaises((ValueError, OSError)):
                self.create(identity=identity)
        outside = self.workspace / "outside.md"
        outside.write_text("leave alone")
        (self.notes.root / "link.md").symlink_to(outside)
        with self.assertRaises(OSError):
            self.notes.request({"action": "read", "id": "link.md"})
        self.assertIn("link.md", self.notes.request({"action": "list"})["skipped"])
        note = self.create()
        (self.notes.root / ".trash").symlink_to(self.workspace, target_is_directory=True)
        with self.assertRaises(OSError):
            self.notes.request({"action": "delete", "id": note["id"], "revision": note["revision"]})
        self.assertEqual(outside.read_text(), "leave alone")
        self.assertTrue((self.notes.root / note["id"]).is_file())

    def test_invalid_file_does_not_hide_other_notes(self):
        self.create()
        (self.notes.root / "binary.md").write_bytes(b"\xff\x00")
        (self.notes.root / "big.md").write_bytes(b"a" * (MAX_BYTES + 1))
        (self.notes.root / "directory.md").mkdir()
        os.mkfifo(self.notes.root / "pipe.md")
        result = self.notes.request({"action": "list"})
        self.assertEqual([n["id"] for n in result["notes"]], ["ideas.md"])
        self.assertEqual(set(result["skipped"]), {"binary.md", "big.md", "directory.md", "pipe.md"})
        for content in (None, 123, "\x00", "é" * MAX_BYTES):
            with self.assertRaises(ValueError):
                self.create(content=content)

    def test_atomic_save_failure_preserves_original(self):
        note = self.create()
        with patch("hermes_notes.os.replace", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                self.notes.request({"action": "save", "id": note["id"], "revision": note["revision"], "content": "draft"})
        self.assertEqual((self.notes.root / note["id"]).read_text(), note["content"])
        self.assertFalse(list(self.notes.root.glob(".save-*")))

    def test_agent_edit_while_preparing_atomic_save_is_detected(self):
        note = self.create()
        original_read = self.notes.read
        def read(directory, identity):
            result = original_read(directory, identity)
            (self.notes.root / identity).write_text("# Agent changed it")
            return result
        with patch.object(self.notes, "read", side_effect=read):
            result = self.notes.request({"action": "save", "id": note["id"], "revision": note["revision"], "content": "draft"})
        self.assertTrue(result["conflict"])
        self.assertEqual((self.notes.root / note["id"]).read_text(), "# Agent changed it")

    def test_agents_have_separate_notebooks_and_root_symlinks_are_rejected(self):
        self.create()
        other = self.workspace / "other"
        other.mkdir()
        self.assertEqual(Notes(other).request({"action": "list"})["notes"], [])
        (other / "notes/.lock").unlink()
        (other / "notes").rmdir()
        (other / "notes").symlink_to(self.notes.root, target_is_directory=True)
        with self.assertRaises(OSError):
            Notes(other).request({"action": "list"})

    def test_worker_uses_gateway_and_propagates_unavailable_method(self):
        output = io.BytesIO()
        with patch.object(worker, "tui_gateway") as gateway:
            gateway.return_value.call.return_value = {"notes": []}
            worker.handle_request({"operation": "hermes_notes", "params": {"action": "list"}, "request_id": "req"}, output)
            gateway.return_value.call.assert_called_once_with("talaria.notes", {"action": "list"})
            self.assertEqual([json.loads(line)["type"] for line in output.getvalue().splitlines()], ["result", "complete"])
            output = io.BytesIO()
            gateway.return_value.call.side_effect = RuntimeError("method unavailable")
            worker.handle_request({"operation": "hermes_notes", "params": {"action": "list"}, "request_id": "req"}, output)
            events = [json.loads(line) for line in output.getvalue().splitlines()]
            self.assertEqual([e["type"] for e in events], ["error"])
            self.assertIn("method unavailable", events[0]["message"])

    def test_rpc_registration_uses_profile_workspace(self):
        methods = {}
        server = Mock()
        server.method.side_effect = lambda name: lambda fn: methods.setdefault(name, fn)
        server._ok.side_effect = lambda rid, result: result
        server._err.side_effect = lambda rid, code, message: {"error": message}
        register(server, self.workspace / ".hermes")
        self.assertEqual(methods["talaria.notes"]("id", {"action": "list"})["directory"], str(self.workspace / "notes"))
        self.assertIn("error", methods["talaria.notes"]("id", {"action": "unknown"}))


if __name__ == "__main__":
    unittest.main()
