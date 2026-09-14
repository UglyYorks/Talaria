import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "AgentRuntime"))
from hermes_notes import Notes, Memories, MAX_BYTES, register
import fcntl
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


class MemoriesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / ".hermes"
        self.home.mkdir()
        self.memories = Memories(self.home)

    def read(self, identity="MEMORY.md"):
        return self.memories.request({"action": "read", "id": identity})["note"]

    def save(self, note, content):
        return self.memories.request({"action": "save", "id": note["id"], "revision": note["revision"], "content": content})

    def test_empty_files_are_editable_without_creating_them_until_save(self):
        listed = self.memories.request({"action": "list"})["notes"]
        self.assertEqual([n["title"] for n in listed], ["Learned facts", "About you"])
        self.assertFalse(list(self.memories.root.glob("*.md")))
        memory = self.save(self.read(), "Prefers short answers.\n§\nUses Python. 🌱")["note"]
        profile = self.save(self.read("USER.md"), "Lives in Brisbane.")["note"]
        self.memories = Memories(self.home)
        self.assertEqual(self.read()["content"], memory["content"])
        self.assertEqual(self.read("USER.md")["content"], profile["content"])
        self.assertEqual(self.memories.request({"action": "list", "query": "BRISBANE"})["notes"][0]["id"], "USER.md")
        cleared = self.save(memory, "")["note"]
        self.assertEqual(cleared["content"], "")
        self.assertNotEqual(cleared["revision"], Memories.MISSING_REVISION)
        self.assertEqual(self.read("USER.md")["content"], profile["content"])
        self.assertEqual(Notes(self.home.parent).request({"action": "list"})["notes"], [])

    def test_agent_creating_editing_or_removing_memory_conflicts_with_draft(self):
        draft = self.read()
        path = self.memories.root / "MEMORY.md"
        path.write_text("Agent learned this.")
        self.assertTrue(self.save(draft, "User draft")["conflict"])
        self.assertEqual(path.read_text(), "Agent learned this.")
        draft = self.read()
        path.write_text("New learning.")
        self.assertTrue(self.save(draft, "User draft")["conflict"])
        draft = self.read()
        path.unlink()
        self.assertTrue(self.save(draft, "User draft")["conflict"])
        self.assertFalse(path.exists())

    def test_memory_edits_hold_hermes_per_file_locks(self):
        draft = self.read()
        original_read = self.memories.read
        def checked_read(directory, identity):
            for name in ("MEMORY.md.lock", "USER.md.lock"):
                with (self.memories.root / name).open("a+") as lock:
                    with self.assertRaises(BlockingIOError):
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return original_read(directory, identity)
        with patch.object(self.memories, "read", side_effect=checked_read):
            self.assertEqual(self.save(draft, "New learning")["note"]["content"], "New learning")
        for name in ("MEMORY.md.lock", "USER.md.lock"):
            with (self.memories.root / name).open("a+") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_only_builtin_files_are_accessible_and_invalid_files_are_not_empty(self):
        self.read()
        for identity in ("SOUL.md", "../USER.md", "notes.md", [], None):
            with self.subTest(identity=identity), self.assertRaises(ValueError):
                self.memories.request({"action": "save", "id": identity, "content": "text", "revision": "0" * 64})
        for action in ("create", "delete"):
            with self.assertRaises(ValueError):
                self.memories.request({"action": action, "id": "MEMORY.md", "content": "text"})
        outside = self.home / "outside.md"
        outside.write_text("untouched")
        path = self.memories.root / "MEMORY.md"
        path.symlink_to(outside)
        with self.assertRaises(OSError):
            self.read()
        self.assertEqual(self.memories.request({"action": "list"})["skipped"], ["MEMORY.md"])
        path.unlink()
        path.write_bytes(b"\xff")
        with self.assertRaises(UnicodeError):
            self.read()
        self.assertEqual(outside.read_text(), "untouched")

    def test_failed_atomic_save_and_symlinked_lock_preserve_memory(self):
        note = self.save(self.read(), "Keep this.")["note"]
        with patch("hermes_notes.os.replace", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                self.save(note, "replacement")
        self.assertEqual(self.read()["content"], "Keep this.")
        self.assertFalse(list(self.memories.root.glob(".save-*")))
        lock = self.memories.root / "MEMORY.md.lock"
        lock.unlink()
        lock.symlink_to(self.memories.root / "MEMORY.md")
        with self.assertRaises(OSError):
            self.save(note, "replacement")

    def test_gateway_routes_memory_to_selected_agent_home(self):
        methods = {}
        server = Mock()
        server.method.side_effect = lambda name: lambda fn: methods.setdefault(name, fn)
        server._ok.side_effect = lambda rid, result: result
        server._err.side_effect = lambda rid, code, message: {"error": message}
        register(server, self.home)
        rpc = methods["talaria.notes"]
        params = {"collection": "memory", "action": "read", "id": "USER.md"}
        note = rpc("id", params)["note"]
        params.update(action="save", revision=note["revision"], content="User edited this.")
        self.assertEqual(rpc("id", params)["note"]["content"], "User edited this.")
        self.assertEqual((self.home / "memories/USER.md").read_text(), "User edited this.")
        self.assertEqual(rpc("id", {"action": "list"})["notes"], [])
        self.assertIn("error", rpc("id", {"collection": "unknown", "action": "list"}))
        output = io.BytesIO()
        with patch.object(worker, "tui_gateway") as gateway:
            gateway.return_value.call.return_value = {"note": note}
            worker.handle_request({"operation": "hermes_notes", "params": params, "request_id": "req"}, output)
            gateway.return_value.call.assert_called_once_with("talaria.notes", params)


if __name__ == "__main__":
    unittest.main()
