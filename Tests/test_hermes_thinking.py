"""Thinking discovery and session configuration, without provider traffic."""
import io
import json
from pathlib import Path
import sys
import threading
import types
import unittest
from unittest.mock import Mock, patch, call

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'AgentRuntime'))
from hermes_thinking import model_thinking, describe_thinking, register
from hermes_gateway import HermesGateway, RPCError
import talaria_agent as worker


class ThinkingTests(unittest.TestCase):
    def setUp(self):
        self.profile = Mock()
        self.profile.supported_reasoning_efforts.return_value = None
        self.reader = Mock(return_value=None)
        self.modules = patch.dict(sys.modules, {
            'hermes_constants': types.SimpleNamespace(VALID_REASONING_EFFORTS=('low', 'medium', 'high', 'xhigh', 'max'),
                resolve_reasoning_config=lambda cfg, model: {'effort': 'medium'}),
            'providers': types.SimpleNamespace(get_provider_profile=lambda provider: self.profile),
            'hermes_cli.config': types.SimpleNamespace(load_config=lambda: {}),
            'agent.reasoning_effort': types.SimpleNamespace(clamp_effort=lambda value, levels: value if value in levels else levels[0],
                                                          codex_supported_efforts=lambda model: ('low', 'medium', 'high')),
            'hermes_cli.models_reasoning_caps': types.SimpleNamespace(openrouter_model_reasoning_capabilities=self.reader,
                                                                    nous_model_reasoning_capabilities=self.reader),
        })
        self.modules.start()
        self.addCleanup(self.modules.stop)

    def test_unknown_is_not_a_generic_ladder(self):
        self.assertEqual(model_thinking('private', 'new-model', {})['levels'], [])
        self.assertIn('published', model_thinking('private', 'new-model', {})['error'])

    def test_no_reasoning_is_one_disabled_value(self):
        self.assertEqual(model_thinking('private', 'plain', {'reasoning': False}), {'levels': ['none'], 'default': 'none'})
        self.profile.supported_reasoning_efforts.return_value = ()
        self.assertEqual(model_thinking('private', 'plain', {})['levels'], ['none'])

    def test_profile_capabilities_are_sorted_and_deduplicated(self):
        self.profile.supported_reasoning_efforts.return_value = ('high', 'low', 'high', 'medium')
        self.assertEqual(model_thinking('private', 'model', {}), {'levels': ['low', 'medium', 'high'], 'default': 'medium'})
        self.profile.supported_reasoning_efforts.assert_called_with('model')

    def test_catalogue_keeps_exact_levels_and_mandatory_thinking(self):
        self.reader.return_value = {'supports_reasoning': True, 'supported_efforts': ['low', 'medium', 'high'], 'mandatory': True}
        self.assertEqual(model_thinking('openrouter', 'model', {})['levels'], ['low', 'medium', 'high'])
        self.reader.assert_called_with('model', allow_fetch=True)
        self.reader.return_value['mandatory'] = False
        self.assertEqual(model_thinking('nous', 'model', {})['levels'], ['none', 'low', 'medium', 'high'])

    def test_provider_identity_and_failure_are_per_model(self):
        rows = [{'slug': 'private', 'models': ['first', 'second'], 'capabilities': {'first': {'reasoning': False}}}]
        self.profile.supported_reasoning_efforts.side_effect = RuntimeError('private detail')
        result = describe_thinking(rows)['models']
        self.assertEqual(result['private::first']['levels'], ['none'])
        self.assertEqual(result['private::second']['levels'], [])
        self.assertNotIn('private detail', json.dumps(result))

    def test_unrestricted_catalogue_uses_hermes_effort_vocabulary(self):
        self.reader.return_value = {'supports_reasoning': True, 'supported_efforts': None, 'mandatory': False}
        self.assertEqual(model_thinking('openrouter', 'model', {})['levels'],
                         ['none', 'low', 'medium', 'high', 'xhigh', 'max'])
        self.reader.return_value['mandatory'] = True
        self.assertNotIn('none', model_thinking('openrouter', 'model', {})['levels'])

    def test_older_hermes_capability_module(self):
        self.reader.return_value = {'supports_reasoning': True, 'supported_efforts': ['medium'], 'mandatory': True}
        with patch.dict(sys.modules, {'hermes_cli.models_reasoning_caps': None,
                'hermes_cli.models': types.SimpleNamespace(openrouter_model_reasoning_capabilities=self.reader,
                                                          nous_model_reasoning_capabilities=self.reader)}):
            self.assertEqual(model_thinking('openrouter', 'model', {})['levels'], ['medium'])

    def test_codex_uses_installed_hermes_vocabulary(self):
        self.assertEqual(model_thinking('openai-codex', 'a-model', {})['levels'], ['low', 'medium', 'high'])

    def test_missing_thinking_rpc_is_an_error(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.call = Mock(side_effect=[{'providers': []}, RPCError({'code': -32601, 'message': 'Update Hermes'})])
        with self.assertRaisesRegex(RPCError, 'Update Hermes'):
            gateway.model_options()

    def test_apply_thinking_is_session_scoped_and_verified(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.call = Mock(return_value={'value': 'high'})
        gateway._apply_session_thinking('chat-a', 'high')
        self.assertEqual(gateway.call.call_args_list, [
            call('config.set', {'session_id': 'chat-a', 'key': 'reasoning', 'value': 'high'}),
            call('config.get', {'session_id': 'chat-a', 'key': 'reasoning'})])
        gateway.call.side_effect = [{'value': 'high'}, {'value': 'low'}]
        with self.assertRaisesRegex(RuntimeError, 'retain'):
            gateway._apply_session_thinking('chat-a', 'high')

    def test_thinking_failure_prevents_prompt_submission(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.lock = threading.RLock()
        gateway.sessions = {'chat': {'id': 'runtime', 'model': 'model'}}
        gateway.session_locks = {}
        gateway.mappings = {}
        gateway.waiting = {}
        gateway.call = Mock(side_effect=RPCError({'code': 4002, 'message': 'Unsupported thinking level'}))
        with self.assertRaisesRegex(RPCError, 'Unsupported thinking'):
            gateway.run('chat', 'model', 'Hello', Mock(), reasoning_effort='high')
        self.assertEqual(gateway.call.call_args_list, [call('config.set', {'session_id': 'runtime', 'key': 'reasoning', 'value': 'high'})])

    def test_cached_native_effort_does_not_overwrite_session_commands(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.lock = threading.RLock()
        gateway.sessions = {'chat': {'id': 'runtime', 'model': 'model', 'reasoning_effort': 'high'}}
        gateway.session_locks = {}
        gateway.mappings = {}
        gateway.waiting = {}
        gateway.listeners = {}
        gateway.call = Mock(side_effect=RuntimeError('stop before inference'))
        with self.assertRaisesRegex(RuntimeError, 'stop before inference'):
            gateway.run('chat', 'model', 'Hello', Mock(), reasoning_effort='high')
        self.assertNotIn('config.set', [item.args[0] for item in gateway.call.call_args_list])

    def test_worker_forwards_effort_for_the_same_session(self):
        with patch.object(worker, 'tui_gateway') as get, patch.object(worker, 'save_agent_soul'):
            output = io.BytesIO()
            worker.stream_hermes_session({'session_id': 'chat', 'request_id': 'r', 'model': 'model',
                                         'prompt': 'hello', 'reasoning_effort': 'high'}, output)
            args, kwargs = get.return_value.run.call_args
            self.assertEqual(args[:3], ('chat', 'model', 'hello'))
            self.assertEqual(kwargs['reasoning_effort'], 'high')
            worker.select_hermes_model({'session_id': 'chat', 'model': 'model', 'reasoning_effort': 'low'}, output)
            get.return_value.select_model.assert_called_with('chat', 'model', 'low')

    def test_discovery_runs_off_gateway_dispatch_thread(self):
        server = Mock(_LONG_HANDLERS=frozenset())
        register(server)
        self.assertIn('talaria.models.thinking', server._LONG_HANDLERS)


if __name__ == '__main__':
    unittest.main()
