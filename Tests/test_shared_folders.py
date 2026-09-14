"""Shared folders are always-loaded plugin context, never user-message prefixes."""
import copy
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import types
import unittest
from unittest.mock import Mock, patch, call

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "AgentRuntime"))
from hermes_shared_folders import PLUGIN, CONTEXT_FILE, SharedFolders, install, register, register_rpc
from hermes_gateway import HermesGateway
from hermes_plugins import Plugins
import talaria_agent as worker


class SharedFolderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.agent = types.SimpleNamespace(_cached_system_prompt="old saved prompt")
        self.server = Mock(_LONG_HANDLERS=frozenset())
        self.server._sessions = {"s": {"agent": self.agent}}
        self.server._wait_agent.return_value = None
        self.server._ok.side_effect = lambda rid, result: result
        self.service = SharedFolders(self.server, self.home)
        self.context = 'Native instructions\n{"/Mac/work":"/mnt/mac/work"}'
        self.summary = "Read the native mapping file."

    def configure(self, context=None):
        return self.service.configure({"context": self.context if context is None else context, "summary": self.summary})

    def test_plugin_uses_system_section_and_keeps_full_large_mapping(self):
        ctx = Mock()
        with patch.dict(os.environ, HERMES_HOME=str(self.home)):
            register(ctx)
        identity, render = ctx.register_system_prompt_section.call_args.args
        self.assertEqual(identity, PLUGIN)
        ctx.register_hook.assert_not_called()
        self.assertEqual(render({}), "")
        self.configure()
        self.assertEqual(render({"session_id": "child"}), self.context)
        self.configure("x" * 5000)
        self.assertEqual(render({}), self.summary)
        self.assertEqual((self.home / CONTEXT_FILE).read_text(), "x" * 5000)
        self.configure("")
        self.assertEqual(render({}), "")

    def test_install_is_required_idempotent_and_preserves_other_plugins(self):
        raw = {"plugins": {"enabled": ["existing"], "disabled": [PLUGIN, "blocked"], "entries": {"existing": {"keep": True}}}}
        cfg = Mock()
        cfg.read_raw_config.side_effect = lambda: copy.deepcopy(raw)
        cfg.load_config_readonly.side_effect = lambda: copy.deepcopy(raw)
        cfg.save_config.side_effect = lambda values, **kw: raw.update(copy.deepcopy(values))
        modules = {"hermes_cli": types.SimpleNamespace(config=cfg),
                   "hermes_cli.plugins": types.SimpleNamespace(PluginContext=types.SimpleNamespace(register_system_prompt_section=True))}
        with patch.dict(sys.modules, modules):
            install(self.home); install(self.home)
        self.assertEqual(raw["plugins"]["enabled"], ["existing", PLUGIN])
        self.assertEqual(raw["plugins"]["disabled"], ["blocked"])
        self.assertEqual(raw["plugins"]["entries"], {"existing": {"keep": True}})
        self.assertEqual(cfg.save_config.call_count, 1)
        self.assertTrue((self.home / "plugins" / PLUGIN / "plugin.yaml").exists())

    def test_resume_refreshes_once_and_mount_removal_refreshes_again(self):
        self.configure()
        invalidate = Mock()
        with patch.dict(sys.modules, {"agent.system_prompt": types.SimpleNamespace(invalidate_system_prompt=invalidate)}):
            self.service.attach("r", {"session_id": "s"})
            self.service.attach("r", {"session_id": "s"})
            self.assertEqual(invalidate.call_count, 1)
            self.configure("")
            self.service.attach("r", {"session_id": "s"})
            self.assertEqual(invalidate.call_count, 2)
        self.server._start_agent_build.assert_called_with("s", self.server._sessions["s"])

    def test_private_profile_context_does_not_replace_normal_profile(self):
        self.configure()
        private = self.home / "private"
        other = SharedFolders(self.server, private)
        other.configure({"context": "Read-only private mounts", "summary": self.summary})
        self.assertEqual((self.home / CONTEXT_FILE).read_text(), self.context)
        self.assertEqual((private / CONTEXT_FILE).read_text(), "Read-only private mounts")

    def test_active_turn_is_not_invalidated_and_errors_are_reported(self):
        self.configure()
        self.server._sessions["s"]["running"] = True
        with self.assertRaisesRegex(ValueError, "current turn"):
            self.service.attach("r", {"session_id": "s"})
        for params in ({}, {"context": []}, {"context": "x" * 200001, "summary": self.summary}):
            with self.assertRaises(ValueError): self.service.configure(params)
        handlers = {}
        self.server.method.side_effect = lambda name: lambda fn: handlers.update({name: fn})
        register_rpc(self.server, self.home)
        handlers["talaria.shared_folders.attach"]("r", {"session_id": "absent"})
        self.server._err.assert_called()

    def test_worker_passes_folder_context_separately_from_user_prompt(self):
        gateway = Mock()
        with patch.object(worker, "tui_gateway", return_value=gateway), patch.object(worker, "save_agent_soul"):
            worker.stream_hermes_session({"request_id": "r", "session_id": "s", "model": "m", "prompt": "Only my words",
                "shared_folder_context": self.context, "shared_folder_summary": self.summary}, io.BytesIO())
        gateway.call.assert_called_once_with("talaria.shared_folders.configure", {"context": self.context, "summary": self.summary})
        self.assertEqual(gateway.run.call_args.args[2], "Only my words")
        self.assertTrue(gateway.run.call_args.kwargs["shared_folders"])

    def test_gateway_attaches_context_before_submitting_unchanged_prompt(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.lock = threading.RLock()
        gateway.sessions = {"chat": {"id": "s", "model": "m"}}
        gateway.session = Mock(return_value="s")
        gateway.listeners = {}
        def rpc(method, params):
            if method == "prompt.submit":
                gateway.listeners["s"].put({"type": "message.complete", "payload": {"text": "done"}})
            return {}
        gateway.call = Mock(side_effect=rpc)
        gateway.run("chat", "m", "Only my words", Mock(), shared_folders=True)
        self.assertEqual(gateway.call.call_args_list, [call("talaria.shared_folders.attach", {"session_id": "s"}),
            call("prompt.submit", {"session_id": "s", "text": "Only my words"})])

    def test_required_plugin_cannot_be_disabled(self):
        for desired in (True, False):
            with patch.dict(sys.modules, {"hermes_cli": types.SimpleNamespace(config=Mock(), managed_scope=Mock(), plugins_cmd=Mock()),
                "hermes_cli.plugins": types.SimpleNamespace(discover_plugins=Mock(), get_plugin_manager=Mock())}):
                with self.assertRaisesRegex(ValueError, "always included"):
                    Plugins().handle({"action": "set_enabled", "id": PLUGIN, "enabled": desired})


if __name__ == "__main__": unittest.main()
