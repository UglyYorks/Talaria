import io
import json
import sys
import tempfile
import threading
import types
import unittest
from pathlib import Path
from unittest.mock import Mock, patch, call

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'AgentRuntime'))
import hermes_providers as providers
import talaria_agent as worker
from hermes_gateway import HermesGateway, model_identity


class ProviderTests(unittest.TestCase):
    def gateway(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.call = Mock()
        gateway.listeners = {}
        gateway.lock = threading.RLock()
        gateway.session_locks = {}
        gateway.sessions = {}
        return gateway

    def test_legacy_and_qualified_models_are_unambiguous(self):
        self.assertEqual(model_identity('anthropic/claude'), ('openrouter', 'anthropic/claude'))
        self.assertEqual(model_identity('openai-codex::gpt-example'), ('openai-codex', 'gpt-example'))
        for selection in ('::model', 'provider::', 'provider::--session', 'bad provider::model', 'provider::model --provider x'):
            with self.assertRaises(ValueError):
                model_identity(selection)

    def test_catalog_joins_every_installed_provider_and_retains_named_endpoints(self):
        gateway = self.gateway()
        gateway.call.side_effect = [
            {'providers': [{'slug': 'openrouter', 'models': ['same']}, {'slug': 'my-local', 'models': ['same']}]},
            {'providers': [{'slug': 'openrouter', 'label': 'OpenRouter'}, {'slug': 'openai-codex', 'label': 'OpenAI login'}]}]
        rows = gateway.providers({'action': 'list'})['providers']
        self.assertEqual({r['slug'] for r in rows}, {'openrouter', 'openai-codex', 'my-local'})
        self.assertEqual(rows[0]['models'], ['same'])
        gateway.call.assert_any_call('model.options', {'include_unconfigured': True, 'refresh': True})

    def test_credential_changes_wait_for_active_turns_and_rebuild_idle_clients(self):
        gateway = self.gateway()
        gateway.listeners = {"active": object()}
        with self.assertRaises(RuntimeError):
            gateway.providers({"action": "configure", "slug": "example", "values": {"KEY": "value"}})
        gateway.call.assert_not_called()
        gateway.listeners.clear()
        gateway.sessions = {"chat": {"id": "idle", "model": "example::model"}}
        gateway.call.return_value = {"ok": True}
        gateway.providers({"action": "configure", "slug": "example", "values": {"KEY": "value"}})
        self.assertEqual(gateway._stale_sessions, {"chat"})
        self.assertIn("chat", gateway.sessions)

    def test_model_stage_only_returns_selected_provider(self):
        gateway = self.gateway()
        gateway.call.return_value = {'providers': [{'slug': 'a', 'models': ['same']}, {'slug': 'b', 'models': ['same']}]}
        self.assertEqual(gateway.providers({'action': 'models', 'slug': 'b'}), {'providers': [{'slug': 'b', 'models': ['same']}]})

    def test_select_checks_credentials_before_persisting_model_and_preserves_confirmation(self):
        gateway = self.gateway()
        gateway.call.return_value = {'ok': False}
        with self.assertRaises(RuntimeError):
            gateway.providers({'action': 'select', 'selection': 'openai-codex::gpt-example'})
        gateway.call.assert_called_once_with('setup.runtime_check', {'provider': 'openai-codex'})
        gateway.call.reset_mock()
        gateway.call.side_effect = [{'ok': True}, {'confirm_required': True, 'confirm_message': 'Review cost'}]
        self.assertTrue(gateway.providers({'action': 'select', 'selection': 'openai-codex::gpt-example'})['confirm_required'])
        gateway.call.assert_called_with('config.set', {'key': 'model', 'value': 'gpt-example --provider openai-codex', 'confirm_expensive_model': False})

    def test_session_switch_waits_then_verifies_provider_not_just_model_name(self):
        gateway = self.gateway()
        with tempfile.TemporaryDirectory() as directory:
            gateway.home = Path(directory)
            gateway.call.side_effect = [{'ready': True}, {'value': 'same'}, {'verified': True}]
            gateway._apply_session_model('runtime', 'openai-codex::same')
            self.assertEqual(gateway.call.call_args_list[:2], [
                call('talaria.session.ready', {'session_id': 'runtime'}),
                call('config.set', {'session_id': 'runtime', 'key': 'model', 'value': 'same --session --provider openai-codex'})])
            gateway.call.side_effect = [{'ready': True}, {'value': 'same'}, {'verified': False}]
            with self.assertRaises(RuntimeError):
                gateway._apply_session_model('runtime', 'openai-codex::same')

    def test_supporting_model_uses_its_own_provider_and_closes_private_session(self):
        gateway = self.gateway()
        with tempfile.TemporaryDirectory() as directory:
            gateway.home = Path(directory)
            gateway.call.side_effect = [{'session_id': 'private'}, {'ready': True}, {'value': 'small'},
                {'verified': True}, {'text': 'Icon'}, {}]
            self.assertEqual(gateway.generate_text('anthropic::small', 'Instructions', 'Input'), 'Icon')
            gateway.call.assert_any_call('session.create', {'model': 'small', 'provider': 'anthropic', 'source': 'talaria', 'hidden': True})
            gateway.call.assert_called_with('session.close', {'session_id': 'private'})
            self.assertNotIn('prompt.submit', [c.args[0] for c in gateway.call.call_args_list])

    def test_worker_accepts_hermes_stored_credentials_without_openrouter_token(self):
        gateway = Mock()
        with patch.object(worker, 'tui_gateway', return_value=gateway):
            output = io.BytesIO()
            worker.stream_hermes_session({'request_id': 'r', 'session_id': 'chat', 'model': 'openai-codex::example', 'prompt': 'Hi'}, output)
            self.assertEqual(json.loads(output.getvalue())['type'], 'complete')
            gateway.run.assert_called_once()

    def test_configured_agent_does_not_receive_legacy_global_key_or_model_override(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(worker, 'HERMES_HOME', Path(directory)):
            self.assertEqual(worker.hermes_environment('legacy')['OPENROUTER_API_KEY'], 'legacy')
            (Path(directory) / 'talaria-provider-configured').touch()
            with patch.dict(worker.os.environ, {}, clear=True):
                environment = worker.hermes_environment('legacy', 'openai-codex::example')
                self.assertNotIn('OPENROUTER_API_KEY', environment)
                self.assertNotIn('HERMES_INFERENCE_PROVIDER', environment)
                self.assertNotIn('HERMES_INFERENCE_MODEL', environment)

    def test_credentials_validate_all_fields_before_any_write_and_use_hermes_store(self):
        config = types.ModuleType('hermes_cli.config')
        config.is_managed = lambda: False
        config.validate_env_var_name_for_write = Mock()
        managed = types.ModuleType('hermes_cli.managed_scope')
        managed.is_env_managed = lambda key: key == 'LOCKED_KEY'
        lifecycle = types.ModuleType('hermes_cli.credential_lifecycle')
        lifecycle.save_provider_env_credential = Mock()
        package = types.ModuleType('hermes_cli')
        package.config = config
        package.managed_scope = managed
        descriptor = {'slug': 'example', 'api_key_env_vars': ['API_KEY', 'LOCKED_KEY'], 'base_url_env_var': 'BASE_URL'}
        modules = {'hermes_cli': package, 'hermes_cli.config': config, 'hermes_cli.managed_scope': managed,
                   'hermes_cli.credential_lifecycle': lifecycle}
        with patch.dict(sys.modules, modules), patch.object(providers, 'descriptors', return_value=[descriptor]), patch.dict(providers.os.environ, {}, clear=True):
            for values in ({'OTHER': 'secret'}, {'API_KEY': 'secret', 'LOCKED_KEY': 'value'}, {'API_KEY': 'secret\nother'}):
                with self.assertRaises(ValueError):
                    providers.provider_action({'action': 'configure', 'slug': 'example', 'values': values})
                lifecycle.save_provider_env_credential.assert_not_called()
            result = providers.provider_action({'action': 'configure', 'slug': 'example', 'values': {'API_KEY': 'secret'}})
            lifecycle.save_provider_env_credential.assert_called_once_with('API_KEY', 'secret')
            self.assertNotIn('secret', str(result))

    def test_device_cancel_marks_upstream_worker_cancelled_and_scopes_provider(self):
        state = {'provider': 'openai-codex', 'status': 'pending'}
        auth = types.SimpleNamespace(_build_oauth_catalog=lambda: [], _oauth_sessions={'login': state}, _oauth_sessions_lock=threading.RLock())
        with patch.object(providers, 'auth_helpers', return_value=auth), patch.dict(providers._logins, {'login': {'slug': 'openai-codex', 'device': True}}, clear=True):
            with self.assertRaises(ValueError):
                providers.login_action('login.cancel', 'another', {'session_id': 'login'})
            providers.login_action('login.cancel', 'openai-codex', {'session_id': 'login'})
            self.assertTrue(state['cancelled'])
            self.assertFalse(auth._oauth_sessions)
            self.assertFalse(providers._logins)

    def test_provider_errors_do_not_echo_secrets(self):
        gateway = Mock()
        gateway.providers.side_effect = RuntimeError('secret-key')
        with patch.object(worker, 'tui_gateway', return_value=gateway):
            output = io.BytesIO()
            worker.hermes_providers({'request_id': 'r', 'params': {'action': 'configure'}}, output)
            self.assertNotIn(b'secret-key', output.getvalue())
            self.assertEqual(json.loads(output.getvalue())['type'], 'error')

    def test_custom_endpoint_verification_compares_identity_not_billing_class(self):
        handlers = {}
        server = types.SimpleNamespace(method=lambda name: lambda fn: handlers.setdefault(name, fn),
            _ok=lambda rid, payload: payload, _err=lambda rid, code, message: {'error': message},
            _sessions={'s': {'agent': object()}}, _runtime_model_config=lambda agent: {'model': 'same', 'provider': 'custom:gpu-a'})
        providers.register(server)
        runtime = types.ModuleType('hermes_cli.runtime_provider')
        runtime.canonical_custom_identity = lambda config_provider: 'custom:' + config_provider
        with patch.dict(sys.modules, {'hermes_cli': types.ModuleType('hermes_cli'), 'hermes_cli.runtime_provider': runtime}):
            verify = handlers['talaria.session.verify_model']
            self.assertTrue(verify('r', {'session_id': 's', 'model': 'same', 'provider': 'gpu-a'})['verified'])
            self.assertFalse(verify('r', {'session_id': 's', 'model': 'same', 'provider': 'gpu-b'})['verified'])
