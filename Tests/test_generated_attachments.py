import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "AgentRuntime"))
from hermes_attachments import export_response, MAX_BYTES


class GeneratedAttachmentsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.file = self.root / "Report with spaces.pdf"
        self.file.write_bytes(b"%PDF-1.7\nexample")

    def test_snapshot_survives_source_removal_and_history_reload(self):
        text = f"Here is your report.\nTALARIA_ATTACHMENT: {self.file}"
        content, rows = export_response(text, "chat-1", self.root)
        self.assertEqual(content, "Here is your report.")
        self.assertEqual(Path(rows[0]["guestPath"]).read_bytes(), self.file.read_bytes())
        self.file.unlink()
        self.assertEqual(export_response(text, "chat-1", self.root), (content, rows))

    def test_private_delivery_contains_bytes(self):
        import base64
        _, rows = export_response(f"TALARIA_ATTACHMENT: {self.file}", "chat", self.root, private=True)
        self.assertEqual(base64.b64decode(rows[0]["data"]), self.file.read_bytes())

    def test_reference_links_and_examples_are_not_attachments(self):
        text = f"[report]({self.file})\n```text\nTALARIA_ATTACHMENT: {self.file}\n```"
        self.assertEqual(export_response(text, "chat", self.root), (text, []))

    def test_missing_directory_symlink_and_size_errors_are_visible(self):
        link = self.root / "link.pdf"
        link.symlink_to(self.file)
        large = self.root / "large.pdf"
        with large.open("wb") as handle:
            handle.truncate(MAX_BYTES + 1)
        for source in (self.root / "missing.pdf", self.root, link, large):
            with self.subTest(source=source):
                content, rows = export_response(f"TALARIA_ATTACHMENT: {source}", "chat", self.root)
                self.assertEqual(rows, [])
                self.assertIn("Could not attach", content)

    def test_destination_cannot_redirect_exports(self):
        (self.root / "attachments").symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            export_response(f"TALARIA_ATTACHMENT: {self.file}", "chat", self.root)

    def test_duplicate_markers_make_one_card_and_sessions_are_isolated(self):
        marker = f"TALARIA_ATTACHMENT: {self.file}"
        _, first = export_response(marker + "\n" + marker, "first", self.root)
        _, second = export_response(marker, "second", self.root)
        self.assertEqual(len(first), 1)
        self.assertNotEqual(first[0]["guestPath"], second[0]["guestPath"])


if __name__ == "__main__":
    unittest.main()
