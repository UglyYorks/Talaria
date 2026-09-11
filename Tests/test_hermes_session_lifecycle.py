"""Deterministic lifecycle races using fake RPC; no live Hermes or network."""
import sys
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import Mock
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'AgentRuntime'))
from hermes_gateway import HermesGateway


class SessionLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        gateway = self.gateway = HermesGateway.__new__(HermesGateway)
        gateway.lock = threading.RLock()
        gateway.home = Path(self.directory.name)
        gateway.mapping_path = gateway.home / 'sessions.json'
        gateway.mappings = {'chat': 'stored', 'alias': 'stored'}
        gateway.sessions = {'chat': {'id': 'live', 'model': 'old'}}
        gateway.listeners = {}
        gateway.call = Mock()

    def test_delete_and_history_open_cannot_overlap_model_switch(self):
        entered, release = threading.Event(), threading.Event()
        errors = []
        def rpc(method, params):
            if method == 'config.set':
                entered.set()
                if not release.wait(5): raise TimeoutError('test barrier')
                return {'value': 'new'}
            if method == 'session.status': return {'output': 'Model: new (openrouter)'}
            self.fail('Unexpected RPC ' + method)
        self.gateway.call.side_effect = rpc
        def switch():
            try: self.gateway.select_model('chat', 'new')
            except Exception as error: errors.append(error)
        thread = threading.Thread(target=switch)
        thread.start()
        try:
            self.assertTrue(entered.wait(5))
            for operation in (self.gateway.delete_history_session, self.gateway.history_session):
                with self.assertRaisesRegex(RuntimeError, 'finish'): operation('stored')
            with self.assertRaisesRegex(RuntimeError, 'finish'):
                self.gateway.select_model('alias', 'new')
        finally:
            release.set()
            thread.join(5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        self.assertEqual(self.gateway.sessions['chat']['model'], 'new')
        self.assertEqual([c.args[0] for c in self.gateway.call.call_args_list], ['config.set', 'session.status'])

    def test_provider_mutation_excludes_supporting_model_request(self):
        def rpc(method, params):
            if method == 'session.create':
                with self.assertRaisesRegex(RuntimeError, 'active response'):
                    self.gateway.providers({'action': 'configure'})
                return {'session_id': 'private'}
            if method == 'config.set': return {'value': 'model'}
            if method == 'llm.oneshot': return {'text': 'result'}
            return {}
        self.gateway.call.side_effect = rpc
        self.assertEqual(self.gateway.generate_text('model', 'instructions', 'input'), 'result')
        self.assertEqual(self.gateway._support_requests, 0)

    def test_aliases_keep_one_gate_after_identity_is_persisted(self):
        registry = self.gateway.registry
        gate = registry.gate('chat')
        self.assertIs(gate, registry.gate('alias'))
        self.assertIs(gate, registry.gate('stored'))
        registry.remember_mapping('chat', 'new-stored')
        self.assertIs(gate, registry.gate('new-stored'))

if __name__ == '__main__': unittest.main()

class AliasOwnershipTests(unittest.TestCase):
    setUp = SessionLifecycleTests.setUp

    def test_alias_reuses_live_session(self):
        self.assertEqual(self.gateway.session('alias', 'old'), 'live')
        self.gateway.call.assert_not_called()
        self.assertEqual(set(self.gateway.sessions), {'chat'})

    def test_pending_approval_blocks_model_change(self):
        self.gateway.listeners['live'] = Mock()
        with self.assertRaisesRegex(RuntimeError, 'pending Hermes interaction'):
            self.gateway.select_model('alias', 'new')
        self.gateway.call.assert_not_called()

    def test_busy_alias_can_still_interrupt_origin(self):
        gate = self.gateway._session_registry().gate('chat')
        gate.acquire()
        self.addCleanup(gate.release)
        self.gateway.command = Mock(return_value={'output': 'Stopped'})
        self.gateway.run('alias', 'old', '/stop', Mock())
        self.gateway.command.assert_called_once_with('chat', 'live', '/stop', 'old')

    def test_mapping_conflict_does_not_replace_live_state(self):
        other = self.gateway._session_registry().gate('another-stored')
        other.acquire()
        self.addCleanup(other.release)
        with self.assertRaises(RuntimeError):
            self.gateway._remember('chat', {'session_id': 'new-live', 'stored_session_id': 'another-stored'}, 'new')
        self.assertEqual(self.gateway.sessions['chat']['id'], 'live')
        self.assertEqual(self.gateway.mappings['chat'], 'stored')
