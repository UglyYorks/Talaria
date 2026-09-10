import copy
import io
import json
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'AgentRuntime'))
from hermes_plugins import Plugins, register_rpc
import talaria_agent as worker


class PluginTests(unittest.TestCase):
    def setUp(self):
        self.raw = {'plugins': {'enabled': ['alpha', 'unknown'], 'disabled': ['beta'],
                    'entries': {'alpha': {'granted_capabilities': ['tools.override']}}},
                    'platform_toolsets': {'cli': ['terminal']}}
        self.config = Mock()
        self.config.load_config_readonly.side_effect = lambda: copy.deepcopy(self.raw)
        self.config.read_raw_config.side_effect = lambda: copy.deepcopy(self.raw)
        self.config.is_managed.return_value = False
        self.config.save_config.side_effect = lambda changes, **kw: self.raw.update(copy.deepcopy(changes))
        self.managed = Mock(); self.managed.is_key_managed.return_value = False
        self.commands = Mock()
        self.commands._discover_all_plugins.return_value = [
            ('alpha', '1', 'Alpha description', 'user', '/a', 'alpha'),
            ('beta', '2', 'Beta description', 'user', '/b', 'beta'),
            ('backend', '3', 'Built-in backend', 'bundled', '/c', 'backend')]
        self.commands._bundled_default_on.return_value = True
        manager = Mock(); manager.list_plugins.return_value = [{'key': 'alpha', 'enabled': True}]
        modules = {'hermes_cli': types.SimpleNamespace(config=self.config, managed_scope=self.managed, plugins_cmd=self.commands),
                   'hermes_cli.plugins': types.SimpleNamespace(get_plugin_manager=lambda: manager, discover_plugins=Mock())}
        patcher = patch.dict(sys.modules, modules); patcher.start(); self.addCleanup(patcher.stop)
        self.service = Plugins()

    def test_metadata_and_bundled_defaults_without_loading_plugins(self):
        result = self.service.handle({'action': 'list'})
        self.assertEqual([(p['id'], p['enabled']) for p in result['plugins']], [('alpha', True), ('beta', False), ('backend', True)])
        self.assertFalse(result['restart_required'])
        self.config.save_config.assert_not_called()

    def test_disable_enable_and_revert_preserve_settings(self):
        before = copy.deepcopy(self.raw)
        result = self.service.handle({'action': 'set_enabled', 'id': 'alpha', 'enabled': False})
        self.assertFalse(result['plugins'][0]['enabled']); self.assertTrue(result['restart_required'])
        self.assertEqual(self.raw['plugins']['entries'], before['plugins']['entries'])
        self.assertEqual(self.raw['platform_toolsets'], before['platform_toolsets'])
        self.assertIn('unknown', self.raw['plugins']['enabled'])
        result = self.service.handle({'action': 'set_enabled', 'id': 'alpha', 'enabled': True})
        self.assertFalse(result['restart_required'])
        self.assertTrue(Plugins().handle({'action': 'list'})['plugins'][0]['enabled'])

    def test_legacy_names_normalize_without_affecting_sibling_plugin(self):
        self.commands._discover_all_plugins.return_value = [
            ('same', '1', '', 'user', '/a', 'a/same'), ('same', '1', '', 'user', '/b', 'b/same')]
        self.raw['plugins'].update(enabled=['same'], disabled=[])
        result = self.service.handle({'action': 'set_enabled', 'id': 'a/same', 'enabled': False})
        self.assertEqual([(p['id'], p['enabled']) for p in result['plugins']], [('a/same', False), ('b/same', True)])

    def test_canonical_enable_clears_legacy_disable(self):
        self.commands._discover_all_plugins.return_value = [('leaf', '1', '', 'user', '/a', 'category/leaf')]
        self.raw['plugins'].update(enabled=[], disabled=['leaf'])
        self.assertTrue(self.service.handle({'action': 'set_enabled', 'id': 'category/leaf', 'enabled': True})['plugins'][0]['enabled'])

    def test_managed_can_list_but_cannot_mutate(self):
        self.managed.is_key_managed.side_effect = lambda key: key == 'plugins.enabled'
        self.assertTrue(self.service.handle({'action': 'list'})['managed'])
        with self.assertRaisesRegex(ValueError, 'managed'):
            self.service.handle({'action': 'set_enabled', 'id': 'alpha', 'enabled': False})
        self.config.save_config.assert_not_called()

    def test_invalid_and_unknown_requests_do_not_write(self):
        for params in (None, {'action': 'install'}, {'action': 'set_enabled', 'id': '../alpha', 'enabled': True},
                       {'action': 'set_enabled', 'id': 'alpha', 'enabled': 'false'}):
            with self.subTest(params=params), self.assertRaises(ValueError): self.service.handle(params)
        self.config.save_config.assert_not_called()

    def test_failed_save_is_reported_and_not_assumed_successful(self):
        self.config.save_config.side_effect = OSError('read-only profile')
        with self.assertRaisesRegex(OSError, 'read-only'):
            self.service.handle({'action': 'set_enabled', 'id': 'alpha', 'enabled': False})
        self.assertTrue(self.service.handle({'action': 'list'})['plugins'][0]['enabled'])

    def test_rpc_and_worker_use_tui_only(self):
        methods = {}
        server = types.SimpleNamespace(_LONG_HANDLERS=frozenset(),
            method=lambda name: lambda fn: methods.setdefault(name, fn),
            _ok=lambda rid, result: result, _err=lambda rid, code, error: {'error': error})
        register_rpc(server)
        self.assertIn('talaria.plugins', server._LONG_HANDLERS)
        self.assertEqual(len(methods['talaria.plugins']('r', {'action': 'list'})['plugins']), 3)
        output = io.BytesIO()
        with patch.object(worker, 'tui_gateway') as gateway:
            gateway.return_value.call.return_value = {'plugins': []}
            worker.handle_request({'operation': 'hermes_plugins', 'request_id': 'r', 'params': {'action': 'list'}}, output)
            gateway.return_value.call.assert_called_once_with('talaria.plugins', {'action': 'list'})
            self.assertEqual(json.loads(output.getvalue().splitlines()[0]), {'type': 'result', 'request_id': 'r', 'result': {'plugins': []}})
            self.assertEqual(json.loads(output.getvalue().splitlines()[-1])['type'], 'complete')


if __name__ == '__main__': unittest.main()
