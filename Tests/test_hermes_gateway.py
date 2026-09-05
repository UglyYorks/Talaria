"""Contract tests for the Hermes JSON-RPC bridge; no network or paid inference."""
import io
import json
import os
from pathlib import Path
import queue
import sys
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'AgentRuntime'))
from hermes_gateway import HermesGateway, RPCError
import talaria_agent as worker


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.gateway = HermesGateway.__new__(HermesGateway)
        self.gateway.lock = threading.RLock()
        self.gateway.sessions = {}
        self.gateway.waiting = {}
        self.gateway.session_locks = {}
        self.gateway.listeners = {}
        self.gateway.pending = {}
        self.gateway.mappings = {}
        self.gateway.mapping_path = Path(self.temp.name) / 'sessions.json'
        self.gateway.call = Mock()

    def catalogue(self, names, aliases=None):
        return {'pairs': [[name, name + ' description'] for name in names], 'canon': aliases or {}}

    def test_resume_preserves_existing_http_session_identity(self):
        self.gateway.call.return_value = {'session_id': 'runtime', 'resumed': 'talaria_1', 'session_key': 'talaria_1'}
        self.assertEqual(self.gateway.session('talaria_1', 'model'), 'runtime')
        self.gateway.call.assert_called_once_with('session.resume', {'session_id': 'talaria_1'})
        self.assertEqual(json.loads(self.gateway.mapping_path.read_text()), {'talaria_1': 'talaria_1'})

    def test_warm_session_skips_rpc_and_mapping_writes(self):
        self.gateway.call.return_value = {'session_id': 'runtime', 'stored_session_id': 'saved'}
        self.gateway.session('chat', 'model')
        self.gateway.call.reset_mock()
        with patch.object(Path, 'write_text') as write:
            for _ in range(3):
                self.assertEqual(self.gateway.session('chat', 'model'), 'runtime')
            write.assert_not_called()
        self.gateway.call.assert_not_called()

    def test_create_only_on_missing_session(self):
        self.gateway.call.side_effect = [RPCError({'code': 4007, 'message': 'session not found'}),
                                        {'session_id': 'runtime', 'stored_session_id': 'saved'}]
        self.assertEqual(self.gateway.session('talaria_1', 'model'), 'runtime')
        self.assertEqual(self.gateway.mappings['talaria_1'], 'saved')
        self.gateway.call.reset_mock(side_effect=True)
        self.gateway.call.side_effect = RPCError({'code': 5000, 'message': 'database unavailable'})
        with self.assertRaisesRegex(RPCError, 'database unavailable'):
            self.gateway.session('talaria_2', 'model')
        self.assertEqual(self.gateway.call.call_count, 1)

    def test_builtin_falls_back_only_on_dispatcher_miss(self):
        self.gateway.call.side_effect = [self.catalogue(['/status']),
            RPCError({'code': 4018, 'message': 'not a quick/plugin/bundle/skill command: status'}),
            {'output': 'Session information'}]
        result = self.gateway.command('chat', 'runtime', '/status', 'model')
        self.assertEqual(result['output'], 'Session information')
        self.gateway.call.assert_called_with('slash.exec', {'session_id': 'runtime', 'command': '/status'})

    def test_failed_custom_command_is_not_executed_twice(self):
        self.gateway.call.side_effect = [self.catalogue(['/deploy']), RPCError({'code': 4018, 'message': 'deploy failed'})]
        with self.assertRaisesRegex(RPCError, 'deploy failed'):
            self.gateway.command('chat', 'runtime', '/deploy', 'model')
        self.assertEqual(self.gateway.call.call_count, 2)

    def test_alias_preserves_arguments(self):
        self.gateway.call.side_effect = [self.catalogue(['/review', '/check']), {'type': 'alias', 'target': '/review'},
                                        self.catalogue(['/review', '/check']), {'type': 'exec', 'output': 'done'}]
        self.assertEqual(self.gateway.command('chat', 'runtime', '/check these files', 'model')['output'], 'done')
        self.gateway.call.assert_called_with('command.dispatch', {'session_id': 'runtime', 'name': 'review', 'arg': 'these files'})

    def test_alias_cycles_are_bounded(self):
        self.gateway.call.side_effect = lambda method, params=None: self.catalogue(['/a']) if method == 'commands.catalog' else {'type': 'alias', 'target': '/a'}
        with self.assertRaisesRegex(RuntimeError, 'alias cycle'):
            self.gateway.command('chat', 'runtime', '/a', 'model')

    def test_unknown_commands_do_not_become_model_prompts(self):
        self.gateway.call.return_value = self.catalogue(['/help'])
        with self.assertRaisesRegex(RuntimeError, 'Unknown Hermes command'):
            self.gateway.command('chat', 'runtime', '/missing', 'model')
        self.assertEqual(self.gateway.call.call_count, 1)

    def test_model_command_updates_live_session(self):
        self.gateway.sessions['chat'] = {'id': 'runtime', 'model': 'selected-model'}
        self.gateway.call.side_effect = [self.catalogue(['/model']), {'value': 'other-model'}]
        self.gateway.command('chat', 'runtime', '/model other-model', 'selected-model')
        self.gateway.call.assert_called_with('config.set', {'session_id': 'runtime', 'key': 'model', 'value': 'other-model'})
        self.gateway.call.reset_mock()
        self.assertEqual(self.gateway.session('chat', 'selected-model'), 'runtime')
        self.gateway.call.assert_not_called()  # Do not undo /model on the next prompt.

    def test_reset_alias_updates_durable_mapping(self):
        self.gateway.call.side_effect = [self.catalogue(['/new'], {'/reset': '/new'}),
                                        {'session_id': 'new-runtime', 'stored_session_id': 'new-stored'}]
        self.gateway.command('chat', 'old-runtime', '/reset topic', 'model')
        self.assertEqual(self.gateway.mappings['chat'], 'new-stored')

    def test_cancelling_one_concurrent_chat_does_not_interrupt_another(self):
        self.gateway.sessions = {'a': {'id': 'a', 'model': 'model'}, 'b': {'id': 'b', 'model': 'model'}}
        started = {sid: threading.Event() for sid in ('a', 'b')}
        cancelled = worker.StreamCancellation()
        output = {'a': [], 'b': []}
        def call(method, params):
            sid = params['session_id']
            if method == 'prompt.submit':
                started[sid].set()
            elif method == 'session.interrupt':
                self.assertEqual(sid, 'a')
                self.gateway.listeners[sid].put({'type': 'message.complete', 'payload': {}})
            return {}
        self.gateway.call.side_effect = call
        threads = [threading.Thread(target=self.gateway.run, args=(sid, 'model', 'hello',
            lambda kind, text, sid=sid: output[sid].append(text)),
            kwargs={'cancellation': cancelled if sid == 'a' else None}) for sid in ('a', 'b')]
        for thread in threads: thread.start()
        self.assertTrue(started['a'].wait(2) and started['b'].wait(2))
        cancelled.cancel()
        threads[0].join(2)
        self.assertFalse(threads[0].is_alive())
        self.assertTrue(threads[1].is_alive())
        self.gateway.listeners['b'].put({'type': 'message.delta', 'payload': {'text': 'B continues'}})
        self.gateway.listeners['b'].put({'type': 'message.complete', 'payload': {'text': 'B continues'}})
        threads[1].join(2)
        self.assertFalse(threads[1].is_alive())
        self.assertEqual(output, {'a': [], 'b': ['B continues', '']})

    def test_stream_filters_reasoning_and_avoids_duplicate_final(self):
        self.gateway.sessions['chat'] = {'id': 'runtime', 'model': 'model'}
        def call(method, params):
            events = self.gateway.listeners['runtime']
            for kind, payload in [('reasoning.delta', {'text': 'thinking'}), ('message.delta', {'text': 'Hello'}),
                                  ('message.complete', {'text': 'Hello world', 'status': 'complete'})]:
                events.put({'type': kind, 'payload': payload})
            return {'status': 'streaming'}
        self.gateway.call.side_effect = call
        chunks = []
        self.gateway.run('chat', 'model', 'hello', lambda kind, text: chunks.append((kind, text)))
        self.assertEqual(chunks, [('thinking', 'thinking'), ('content', 'Hello'), ('content', ' world')])
        self.assertEqual(self.gateway.listeners, {})

    def test_skill_result_is_submitted_through_live_session(self):
        self.gateway.sessions['chat'] = {'id': 'runtime', 'model': 'model'}
        self.gateway.command = Mock(return_value={'type': 'skill', 'message': 'Hermes skill expansion'})
        def call(method, params):
            self.assertEqual((method, params), ('prompt.submit', {'session_id': 'runtime', 'text': 'Hermes skill expansion'}))
            self.gateway.listeners['runtime'].put({'type': 'message.complete', 'payload': {'text': 'done'}})
            return {}
        self.gateway.call.side_effect = call
        output = []
        self.gateway.run('chat', 'model', '/my-skill', lambda kind, text: output.append(text))
        self.assertEqual(output, ['done'])

    def test_pending_approval_requires_explicit_response(self):
        self.gateway.sessions['chat'] = {'id': 'runtime', 'model': 'model'}
        def call(method, params):
            events = self.gateway.listeners['runtime']
            if method == 'prompt.submit':
                events.put({'type': 'approval.request', 'payload': {'request_id': 'approval', 'command': 'rm example', 'choices': ['once', 'deny']}})
            else:
                self.assertEqual((method, params), ('approval.respond', {'session_id': 'runtime', 'request_id': 'approval', 'choice': 'deny'}))
                events.put({'type': 'message.complete', 'payload': {'text': 'Denied'}})
            return {}
        self.gateway.call.side_effect = call
        output = []
        self.gateway.run('chat', 'model', 'do work', lambda kind, text: output.append(text))
        self.assertIn('Reply /approve or /deny.', output[0])
        with self.assertRaisesRegex(RuntimeError, 'Reply /approve or /deny'):
            self.gateway.run('chat', 'model', 'unrelated message', lambda *_: None)
        self.gateway.run('chat', 'model', '/deny', lambda kind, text: output.append(text))
        self.assertEqual(output[-1], 'Denied')
        self.assertEqual(self.gateway.waiting, {})
        self.assertEqual(self.gateway.listeners, {})

    def test_stop_does_not_wait_for_running_turn_lock(self):
        self.gateway.sessions['chat'] = {'id': 'runtime', 'model': 'model'}
        lock = threading.Lock()
        lock.acquire()
        self.gateway.session_locks['chat'] = lock
        self.gateway.command = Mock(return_value={'output': 'Stopped'})
        self.gateway.run('chat', 'model', '/stop', lambda *_: None)
        self.gateway.command.assert_called_once_with('chat', 'runtime', '/stop', 'model')
        self.assertTrue(lock.locked())
        lock.release()

    def test_worker_returns_catalogue_over_existing_transport(self):
        output = io.BytesIO()
        with patch.object(worker, 'tui_gateway') as get_gateway:
            get_gateway.return_value.catalog.return_value = self.catalogue(['/help', '/new-skill'])
            worker.handle_request({'operation': 'hermes_commands', 'request_id': 'req'}, output)
        events = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(json.loads(events[0]['text'])['pairs'][1][0], '/new-skill')
        self.assertEqual(events[-1]['type'], 'complete')

    def test_worker_command_failure_is_terminal_error(self):
        output = io.BytesIO()
        with patch.object(worker, 'tui_gateway') as get_gateway:
            get_gateway.return_value.run.side_effect = RuntimeError('Unsupported command')
            worker.handle_request({'operation': 'hermes_session_chat', 'request_id': 'req', 'session_id': 'chat',
                                   'token': 'test', 'model': 'test', 'prompt': '/bad'}, output)
        events = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]['type'], 'error')

    def test_catalogue_rejects_old_protocol(self):
        self.gateway.call.return_value = {}
        with self.assertRaisesRegex(RuntimeError, 'Update Hermes'):
            self.gateway.catalog()


class TransportTests(unittest.TestCase):
    def test_real_stdio_transport_routes_concurrent_rpc_replies(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / '.hermes'
            home.mkdir()
            module = root / 'tui_gateway'
            module.mkdir()
            (module / '__init__.py').write_text('')
            (module / 'entry.py').write_text("""
import json, sys
print('startup diagnostic', flush=True)
for line in sys.stdin:
    request = json.loads(line)
    if request['method'] == 'disconnect':
        break
    print(json.dumps({'jsonrpc': '2.0', 'method': 'event', 'params': {'session_id': 'live', 'type': 'message.delta', 'payload': {'text': 'event'}}}), flush=True)
    print(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'result': {'method': request['method']}}), flush=True)
""")
            gateway = HermesGateway(sys.executable, {**os.environ, 'PYTHONPATH': str(root)}, home)
            try:
                events = queue.Queue()
                gateway.listeners['live'] = events
                results = {}
                def call(name):
                    results[name] = gateway.call(name)
                threads = [threading.Thread(target=call, args=(name,)) for name in ('first', 'second')]
                for thread in threads: thread.start()
                for thread in threads: thread.join(timeout=5)
                self.assertEqual(results, {'first': {'method': 'first'}, 'second': {'method': 'second'}})
                self.assertEqual(events.get(timeout=1)['payload']['text'], 'event')
                with self.assertRaisesRegex(RPCError, 'disconnected'):
                    gateway.call('disconnect', timeout=5)
                self.assertFalse(gateway.pending)
            finally:
                gateway.process.stdin.close()
                gateway.process.wait(timeout=5)
                gateway.process.stdout.close()


class TUIOnlyTests(unittest.TestCase):
    def test_model_discovery_uses_tui_rpc(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.call = Mock(return_value={'providers': [{'slug': 'openrouter', 'models': ['test']}]})
        self.assertEqual(gateway.model_options()['providers'][0]['models'], ['test'])
        gateway.call.assert_called_once_with('model.options', {'explicit_only': True})

    def test_invalid_model_catalogue_reports_an_error(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.call = Mock(return_value={'models': []})
        with self.assertRaisesRegex(RuntimeError, 'invalid model catalogue'):
            gateway.model_options()

    def test_missing_helper_session_never_runs_inference(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.call = Mock(return_value={})
        with self.assertRaisesRegex(RuntimeError, 'did not create'):
            gateway.generate_text('support/model', 'instructions', 'input')
        self.assertEqual(gateway.call.call_count, 1)

    def test_auxiliary_request_uses_selected_model_without_chat_history(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.call = Mock(side_effect=[{'session_id': 'helper'}, {}, {'text': 'test response'}, {}])
        self.assertEqual(gateway.generate_text('support/model', 'Native instructions', 'Native input'), 'test response')
        from unittest.mock import call
        self.assertEqual(gateway.call.call_args_list, [
            call('session.create', {'model': 'support/model', 'provider': 'openrouter', 'source': 'talaria', 'hidden': True}),
            call('config.set', {'session_id': 'helper', 'key': 'model', 'value': 'support/model --session'}),
            call('llm.oneshot', {'session_id': 'helper', 'instructions': 'Native instructions', 'input': 'Native input', 'max_tokens': 1024}),
            call('session.close', {'session_id': 'helper'})])

    def test_auxiliary_failure_closes_runtime_without_http_fallback(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.call = Mock(side_effect=[{'session_id': 'helper'}, {}, RPCError({'code': -32601, 'message': 'method unavailable'}), {}])
        with self.assertRaisesRegex(RPCError, 'method unavailable'):
            gateway.generate_text('support/model', 'instructions', 'input')
        gateway.call.assert_called_with('session.close', {'session_id': 'helper'})

    def test_legacy_http_operation_is_rejected(self):
        output = io.BytesIO()
        with patch.object(worker.urllib.request, 'urlopen') as http:
            self.assertEqual(worker.handle_request({'operation': 'stream_chat'}, output), 1)
            http.assert_not_called()
        self.assertEqual(json.loads(output.getvalue())['type'], 'error')

    def test_worker_routes_models_and_supporting_tasks_through_tui(self):
        with patch.object(worker, 'tui_gateway') as gateway:
            gateway.return_value.model_options.return_value = {'providers': []}
            output = io.BytesIO()
            worker.handle_request({'operation': 'models', 'token': 'test'}, output)
            self.assertEqual(json.loads(output.getvalue())['response'], {'providers': []})
            gateway.return_value.generate_text.return_value = 'answer'
            output = io.BytesIO()
            worker.handle_request({'operation': 'hermes_generate_text', 'request_id': 'r', 'token': 'test', 'model': 'test',
                                   'instructions': 'native instructions', 'input': 'native input'}, output)
            gateway.return_value.generate_text.assert_called_once_with('test', 'native instructions', 'native input')
            self.assertEqual([json.loads(line)['type'] for line in output.getvalue().splitlines()], ['delta', 'complete'])

    def test_no_direct_ai_http_transport_in_application(self):
        root = Path(__file__).resolve().parents[1]
        # Downloads for installation are allowed; all provider/session traffic belongs
        # to Hermes. Check production code so stale fallbacks cannot silently return.
        forbidden = ('chat/completions', '/chat/stream', 'api/v1/models', 'hostNetworkClient',
                     'TLOpenRouterClient', 'streamChatWithAgent:', 'def stream_chat(')
        for directory in ('Source', 'AgentRuntime'):
            for path in (root / directory).rglob('*'):
                if path.suffix not in {'.h', '.m', '.mm', '.py'}:
                    continue
                source = path.read_text()
                for needle in forbidden:
                    self.assertNotIn(needle, source, f'{path.relative_to(root)} reintroduces {needle}')
        # Every Python URL-open must remain confined to bootstrap installation.
        import ast
        tree = ast.parse((root / 'AgentRuntime/talaria_agent.py').read_text())
        for function in tree.body:
            if not isinstance(function, (ast.FunctionDef, ast.AsyncFunctionDef)) or function.name == 'install_hermes':
                continue
            for node in ast.walk(function):
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
                    self.assertNotEqual(node.func.attr, 'urlopen', f'HTTP request in {function.name}')


if __name__ == '__main__':
    unittest.main()
