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
from unittest.mock import Mock, patch, call

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
        self.gateway.home = Path(self.temp.name)
        self.gateway.mapping_path = self.gateway.home / 'sessions.json'
        self.gateway.call = Mock()

    def test_history_expands_beyond_default_window_and_preserves_alias(self):
        rows = [{"id": f"session-{i}", "title": "", "preview": f"Topic {i}", "started_at": 1700000000}
                for i in range(250)]
        self.gateway.mappings = {"talaria-chat": "session-0", "session-0": "session-0"}
        self.gateway.call.side_effect = lambda method, params: {"sessions": rows[:params["limit"]]}
        result = self.gateway.history_sessions()["sessions"]
        self.assertEqual(len(result), 250)
        self.assertEqual(result[0]["hermes_session_id"], "talaria-chat")
        self.assertEqual(result[0]["title"], "Topic 0")
        self.assertEqual(result[0]["created_at"], "2023-11-14 22:13:20")
        self.assertEqual([c.args[1]["limit"] for c in self.gateway.call.call_args_list], [200, 400])

    def test_history_invalid_or_unavailable_list_is_not_empty_success(self):
        self.gateway.call.return_value = {}
        with self.assertRaisesRegex(RuntimeError, "invalid session list"):
            self.gateway.history_sessions()
        self.gateway.call.side_effect = RPCError({"code": -32601, "message": "method unavailable"})
        with self.assertRaisesRegex(RPCError, "method unavailable"):
            self.gateway.history_sessions()

    def test_history_resume_restores_original_alias_and_transcript(self):
        self.gateway.mappings = {"talaria-chat": "saved"}
        self.gateway.call.side_effect = [
            {"session_id": "runtime", "resumed": "saved", "info": {"model": "original-model"}},
            {"messages": [{"role": "user", "text": "Hello"}, {"role": "tool", "name": "terminal"},
                          {"role": "assistant", "text": "World", "reasoning": "Thought"}]}]
        result = self.gateway.history_session("saved")
        self.assertEqual([m["content"] for m in result["messages"]], ["Hello", "World"])
        self.assertEqual(result["messages"][1]["thinking"], "Thought")
        self.assertEqual(result["model"], "original-model")
        self.assertEqual(self.gateway.sessions, {"talaria-chat": {"id": "runtime", "model": "original-model"}})
        self.gateway.call.assert_called_with("session.history", {"session_id": "runtime"})

    def test_history_missing_session_never_creates_replacement(self):
        self.gateway.call.side_effect = RPCError({"code": 4007, "message": "session not found"})
        with self.assertRaisesRegex(RPCError, "session not found"):
            self.gateway.history_session("missing")
        self.gateway.call.assert_called_once_with("session.resume", {"session_id": "missing"})

    def test_history_deletion_closes_idle_runtime_and_clears_aliases(self):
        self.gateway.mappings = {"chat": "saved", "other": "elsewhere"}
        self.gateway.sessions = {"chat": {"id": "runtime", "model": "model"}}
        self.gateway.call.side_effect = [{}, {"deleted": "saved"}]
        self.assertEqual(self.gateway.delete_history_session("saved"), {"deleted": "saved"})
        self.assertEqual([c.args[0] for c in self.gateway.call.call_args_list], ["session.close", "session.delete"])
        self.assertEqual(self.gateway.mappings, {"other": "elsewhere"})
        self.assertEqual(self.gateway.sessions, {})

    def test_history_deletion_refuses_streaming_or_pending_approval(self):
        self.gateway.mappings = {"chat": "saved"}
        self.gateway.sessions = {"chat": {"id": "runtime", "model": "model"}}
        self.gateway.listeners = {"runtime": queue.Queue()}
        with self.assertRaisesRegex(RuntimeError, "finish"):
            self.gateway.delete_history_session("saved")
        self.gateway.call.assert_not_called()

    def test_worker_history_errors_do_not_return_a_success_event(self):
        with patch.object(worker, "tui_gateway") as gateway:
            gateway.return_value.history_sessions.side_effect = RuntimeError("Unavailable")
            output = io.BytesIO()
            worker.handle_request({"operation": "hermes_history", "action": "list", "request_id": "req"}, output)
            events = [json.loads(line) for line in output.getvalue().splitlines()]
            self.assertEqual([event["type"] for event in events], ["error"])

    def catalogue(self, names, aliases=None):
        return {'pairs': [[name, name + ' description'] for name in names], 'canon': aliases or {}}

    def test_resume_preserves_existing_http_session_identity(self):
        self.gateway.call.side_effect = [
            {'session_id': 'runtime', 'resumed': 'talaria_1', 'session_key': 'talaria_1'},
            {'value': 'model'}, {'output': 'Model: model (openrouter)'}]
        self.assertEqual(self.gateway.session('talaria_1', 'model'), 'runtime')
        self.gateway.call.assert_has_calls([
            call('session.resume', {'session_id': 'talaria_1'}),
            call('config.set', {'session_id': 'runtime', 'key': 'model', 'value': 'model --session'})])
        self.assertEqual(json.loads(self.gateway.mapping_path.read_text()), {'talaria_1': 'talaria_1'})

    def test_warm_session_skips_rpc_and_mapping_writes(self):
        self.gateway.call.side_effect = [
            {'session_id': 'runtime', 'stored_session_id': 'saved'},
            {'value': 'model'}, {'output': 'Model: model (openrouter)'}]
        self.gateway.session('chat', 'model')
        self.gateway.call.reset_mock()
        with patch.object(Path, 'write_text') as write:
            for _ in range(3):
                self.assertEqual(self.gateway.session('chat', 'model'), 'runtime')
            write.assert_not_called()
        self.gateway.call.assert_not_called()

    def test_composer_switch_is_local_and_retried_after_failure(self):
        self.gateway.sessions['a'] = {'id': 'a', 'model': 'old'}
        self.gateway.sessions['b'] = {'id': 'b', 'model': 'other'}
        self.gateway.call.return_value = {'confirm_required': True, 'confirm_message': 'Confirm switch'}
        with self.assertRaisesRegex(RuntimeError, 'Confirm switch'):
            self.gateway.session('a', 'new')
        self.assertEqual(self.gateway.sessions['a']['model'], 'old')
        self.gateway.call.side_effect = [{'value': 'new'}, {'output': 'Model: new (openrouter)'}]
        self.assertEqual(self.gateway.session('a', 'new'), 'a')
        self.gateway.call.assert_any_call('config.set', {'session_id': 'a', 'key': 'model',
                                                          'value': 'new --session'})
        self.assertEqual(self.gateway.sessions['b']['model'], 'other')
        self.gateway.call.reset_mock()
        self.gateway.session('a', 'new')
        self.gateway.call.assert_not_called()

    def test_create_only_on_missing_session(self):
        self.gateway.call.side_effect = [RPCError({'code': 4007, 'message': 'session not found'}),
                                        {'session_id': 'runtime', 'stored_session_id': 'saved'},
                                        {'value': 'model'}, {'output': 'Model: model (openrouter)'}]
        self.assertEqual(self.gateway.session('talaria_1', 'model'), 'runtime')
        self.assertEqual(self.gateway.mappings['talaria_1'], 'saved')
        self.gateway.call.reset_mock(side_effect=True)
        self.gateway.call.side_effect = RPCError({'code': 5000, 'message': 'database unavailable'})
        with self.assertRaisesRegex(RPCError, 'database unavailable'):
            self.gateway.session('talaria_2', 'model')
        self.assertEqual(self.gateway.call.call_count, 1)

    def test_switch_does_not_cache_an_acknowledged_but_inactive_model(self):
        self.gateway.sessions['chat'] = {'id': 'runtime', 'model': 'old'}
        self.gateway.call.side_effect = [{'value': 'new'}, {'output': 'Model: old (openrouter)'}]
        with self.assertRaisesRegex(RuntimeError, 'has not activated'):
            self.gateway.select_model('chat', 'new')
        self.assertEqual(self.gateway.sessions['chat']['model'], 'old')

    def test_switch_button_always_contacts_hermes_without_a_prompt(self):
        self.gateway.sessions['chat'] = {'id': 'runtime', 'model': 'new'}
        self.gateway.call.side_effect = [{'value': 'new'}, {'output': 'Model: new (openrouter)'}]
        self.gateway.select_model('chat', 'new')
        self.assertEqual([c.args[0] for c in self.gateway.call.call_args_list], ['config.set', 'session.status'])
        audit = json.loads((self.gateway.home / 'talaria-model-switches.jsonl').read_text())
        self.assertEqual(audit['model'], 'new')
        self.assertTrue(audit['verified'])

    def test_switch_button_refuses_a_concurrent_turn(self):
        lock = threading.Lock()
        lock.acquire()
        self.gateway.session_locks['chat'] = lock
        with self.assertRaisesRegex(RuntimeError, 'current response'):
            self.gateway.select_model('chat', 'new')
        self.gateway.call.assert_not_called()

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

    def test_spinner_updates_are_status_snapshots_and_empty_updates_clear(self):
        self.gateway.sessions['chat'] = {'id': 'runtime', 'model': 'model'}
        frames = [('thinking.delta', 'computing...'),
                  ('thinking.delta', 'waiting — 30s'), ('thinking.delta', 'waiting — 30s'),
                  ('thinking.delta', 'waiting — 60s'), ('thinking.delta', ''),
                  ('reasoning.delta', 'First'), ('reasoning.delta', ' thought'),
                  ('message.complete', 'Answer')]
        def call(method, params):
            for kind, text in frames:
                self.gateway.listeners['runtime'].put({'type': kind, 'payload': {'text': text}})
            return {}
        self.gateway.call.side_effect = call
        chunks = []
        self.gateway.run('chat', 'model', 'hello', lambda kind, text: chunks.append((kind, text)))
        self.assertEqual(chunks, [('status', text) for _, text in frames[:5]] +
                         [('thinking', 'First'), ('thinking', ' thought'), ('content', 'Answer')])

    def test_tool_activity_is_delivered_before_turn_finishes(self):
        self.gateway.sessions['chat'] = {'id': 'runtime', 'model': 'model'}
        frames = [('tool.generating', {'name': 'terminal'}),
                  ('tool.start', {'name': 'terminal', 'tool_id': 'a', 'context': 'pwd', 'args': {'command': 'pwd'}}),
                  ('tool.start', {'name': 'web_search', 'tool_id': 'b', 'context': 'weather'}),
                  ('tool.complete', {'name': 'terminal', 'tool_id': 'a', 'duration_s': 0.1,
                                     'result': {'exit_code': 1}, 'result_text': 'Command failed'}),
                  ('tool.complete', {'name': 'web_search', 'tool_id': 'b', 'summary': 'Did 1 search',
                                     'result': {'data': {'web': []}}})]
        def call(method, params):
            for kind, payload in frames:
                self.gateway.listeners['runtime'].put({'type': kind, 'payload': payload})
        self.gateway.call.side_effect = call
        chunks = []
        def delta(kind, text):
            chunks.append((kind, text))
            # No terminal event exists until all tool updates have been delivered.
            if len(chunks) == len(frames):
                self.gateway.listeners['runtime'].put({'type': 'message.complete', 'payload': {'text': 'Done'}})
        self.gateway.run('chat', 'model', 'hello', delta)
        activities = [json.loads(text) for kind, text in chunks if kind == 'tool_activity']
        self.assertEqual([a['state'] for a in activities], ['preparing', 'running', 'running', 'failed', 'completed'])
        self.assertEqual([a['id'] for a in activities], ['preparing:terminal', 'a', 'b', 'a', 'b'])
        self.assertEqual(activities[1]['detail'], 'pwd')
        self.assertEqual(activities[3]['summary'], 'Command failed')
        self.assertTrue(all('args' not in a and 'result' not in a for a in activities))
        self.assertEqual(chunks[-1], ('content', 'Done'))

    def test_tool_activity_rejects_malformed_and_bounds_display_text(self):
        from hermes_gateway import tool_activity
        for payload in ([], None, {}, {'name': 'terminal'}, {'name': [], 'tool_id': 'a'}):
            self.assertIsNone(tool_activity('tool.start', payload))
        activity = tool_activity('tool.start', {'name': 'terminal', 'tool_id': 'a', 'context': 'x' * 100000})
        self.assertEqual(len(activity['detail']), 1000)
        activity = tool_activity('tool.complete', {'name': 'x', 'tool_id': 'a', 'result': {'success': False}})
        self.assertEqual(activity['state'], 'failed')

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
        self.assertEqual(json.loads(output[0])['request_id'], 'approval')
        with self.assertRaisesRegex(RuntimeError, 'Reply /approve or /deny'):
            self.gateway.run('chat', 'model', 'unrelated message', lambda *_: None)
        self.gateway.run('chat', 'model', '/deny', lambda kind, text: output.append(text))
        self.assertEqual(output[-1], 'Denied')
        self.assertEqual(self.gateway.waiting, {})
        self.assertEqual(self.gateway.listeners, {})

    def test_approval_card_response_is_bound_to_request_and_allowed_choices(self):
        self.gateway.sessions['chat'] = {'id': 'runtime', 'model': 'model'}
        command = "execute_code <<'PY'\nprint('literal **code**')\n# not a heading\nPY"
        payload = {'request_id': 'exact-id', 'command': command, 'description': 'Run research',
                   'choices': ['once', 'deny']}
        def call(method, params):
            events = self.gateway.listeners['runtime']
            if method == 'prompt.submit':
                events.put({'type': 'approval.request', 'payload': payload})
            else:
                self.assertEqual((method, params), ('approval.respond',
                    {'session_id': 'runtime', 'request_id': 'exact-id', 'choice': 'once'}))
                events.put({'type': 'message.complete', 'payload': {'text': 'Finished'}})
            return {}
        self.gateway.call.side_effect = call
        output = []
        self.gateway.run('chat', 'model', 'research', lambda kind, text: output.append((kind, text)))
        self.assertEqual(output[0][0], 'approval')
        self.assertEqual(json.loads(output[0][1]), payload)
        for response in [{'request_id': 'stale-id', 'choice': 'once'},
                         {'request_id': 'exact-id', 'choice': 'always'}]:
            with self.assertRaises(RuntimeError):
                self.gateway.run('chat', 'model', 'Allow once', lambda *_: None, approval_response=response)
        self.assertEqual(self.gateway.call.call_count, 1)
        response = {'request_id': 'exact-id', 'choice': 'once'}
        self.gateway.run('chat', 'model', 'Allow once', lambda kind, text: output.append((kind, text)), approval_response=response)
        self.assertEqual(output[-1], ('content', 'Finished'))
        with self.assertRaisesRegex(RuntimeError, 'no longer pending'):
            self.gateway.run('chat', 'model', 'Allow once', lambda *_: None, approval_response=response)
        self.assertEqual(self.gateway.call.call_count, 2)  # A repeated click never submits a new prompt.

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


class SkillPolicyTests(unittest.TestCase):
    def setUp(self):
        self.gateway = HermesGateway.__new__(HermesGateway)
        self.gateway._skill_policy_applied = False
        self.config = {'skills': {'disabled': ['user-skill', 'uninstalled-skill'],
                                 'platform_disabled': {'telegram': ['telegram-only']},
                                 'external_dirs': ['/custom/skills']},
                       'model': {'default': 'user-model'}}

        def rpc(method, params=None):
            if method == 'config.get':
                self.assertEqual(params, {'key': 'full', 'profile': 'default'})
                return {'config': self.config}
            if method == 'profiles.configure':
                self.assertEqual(set(params), {'name', 'disabled_skills'})
                self.assertEqual(params['name'], 'default')
                self.config.setdefault('skills', {})['disabled'] = params['disabled_skills']
                return {'ok': True, 'applied': {'skills': True}}
            if method == 'skills.reload':
                return {'result': {'total': 2}}
            self.fail(f'Unexpected RPC: {method}')

        self.gateway.call = Mock(side_effect=rpc)

    def test_policy_merges_existing_settings_and_verifies_before_reload(self):
        self.gateway.apply_skill_policy()
        self.assertEqual(self.config['skills'], {
            'disabled': ['grounded-citations', 'uninstalled-skill', 'user-skill'],
            'platform_disabled': {'telegram': ['telegram-only']}, 'external_dirs': ['/custom/skills']})
        self.assertEqual(self.config['model'], {'default': 'user-model'})
        self.assertEqual([c.args[0] for c in self.gateway.call.call_args_list],
                         ['config.get', 'profiles.configure', 'config.get', 'skills.reload'])
        self.gateway.call.reset_mock()
        self.gateway.apply_skill_policy()
        self.gateway.call.assert_not_called()

    def test_existing_policy_avoids_rewriting_profile(self):
        self.config['skills']['disabled'].append('grounded-citations')
        self.gateway.apply_skill_policy()
        self.assertEqual([c.args[0] for c in self.gateway.call.call_args_list], ['config.get', 'skills.reload'])

    def test_fresh_install_and_legacy_scalar_disabled_setting(self):
        for config, expected in [({}, ['grounded-citations']),
                                 ({'skills': None}, ['grounded-citations']),
                                 ({'skills': {'disabled': None}}, ['grounded-citations']),
                                 ({'skills': {'disabled': ' user-skill '}}, ['grounded-citations', 'user-skill'])]:
            with self.subTest(config=config):
                self.gateway._skill_policy_applied = False
                self.gateway.call.side_effect = [{'config': config}, {'applied': {'skills': True}},
                                                {'config': {'skills': {'disabled': expected}}}, {}]
                self.gateway.apply_skill_policy()
                self.assertEqual(self.gateway.call.call_args_list[-3],
                                 call('profiles.configure', {'name': 'default', 'disabled_skills': expected}))

    def test_malformed_settings_never_replace_user_configuration(self):
        for result in [{}, {'config': []}, {'config': {'skills': []}},
                       {'config': {'skills': {'disabled': {'a': True}}}},
                       {'config': {'skills': {'disabled': [42]}}}]:
            with self.subTest(result=result):
                self.gateway.call.reset_mock()
                self.gateway.call.side_effect = None
                self.gateway.call.return_value = result
                with self.assertRaisesRegex(RuntimeError, 'invalid'):
                    self.gateway.apply_skill_policy()
                self.assertFalse(self.gateway._skill_policy_applied)
                self.assertEqual(self.gateway.call.call_count, 1)

    def test_rejected_or_unpersisted_write_is_not_success(self):
        for replies in [
                [{'config': {}}, {'ok': False, 'applied': {'skills': False}}],
                [{'config': {}}, {'applied': {'skills': True}}, {'config': {}}]]:
            with self.subTest(replies=replies):
                self.gateway.call.side_effect = replies
                with self.assertRaisesRegex(RuntimeError, 'did not'):
                    self.gateway.apply_skill_policy()
                self.assertFalse(self.gateway._skill_policy_applied)

    def test_missing_rpc_reports_update_requirement_and_can_retry(self):
        self.gateway.call.side_effect = RPCError({'code': -32601, 'message': 'method unavailable'})
        with self.assertRaisesRegex(RuntimeError, 'Update Hermes'):
            self.gateway.apply_skill_policy()
        self.assertFalse(self.gateway._skill_policy_applied)
        self.gateway.call.side_effect = [{'config': {'skills': {'disabled': ['grounded-citations']}}}, {}]
        self.gateway.apply_skill_policy()
        self.assertTrue(self.gateway._skill_policy_applied)

    def test_failed_reload_retries_even_after_settings_were_saved(self):
        self.gateway.call.side_effect = [
            {'config': {}}, {'applied': {'skills': True}},
            {'config': {'skills': {'disabled': ['grounded-citations']}}},
            RPCError({'message': 'reload failed'})]
        with self.assertRaisesRegex(RuntimeError, 'reload failed'):
            self.gateway.apply_skill_policy()
        self.assertFalse(self.gateway._skill_policy_applied)


class SkillsSettingsTests(unittest.TestCase):
    def setUp(self):
        self.gateway = HermesGateway.__new__(HermesGateway)
        self.gateway.skill_settings_lock = threading.Lock()
        self.disabled = {'grounded-citations', 'beta', 'uninstalled'}
        self.names = ['hermes-agent', 'grounded-citations', 'beta', 'alpha']
        self.descriptions = {'alpha': 'Read documents.', 'beta': 'Search the web.',
                             'grounded-citations': 'Cite sources.'}

        def rpc(method, params=None):
            if method == 'profiles.describe':
                self.assertEqual(params, {'name': 'default'})
                return {'skills': [{'name': name, 'enabled': name not in self.disabled} for name in self.names]}
            if method == 'talaria.skills.describe':
                return {'skills': [{'name': name, 'description': description}
                                   for name, description in self.descriptions.items()]}
            if method == 'config.get':
                return {'config': {'skills': {'disabled': sorted(self.disabled)}}}
            if method == 'profiles.configure':
                self.assertEqual(set(params), {'name', 'disabled_skills'})
                self.disabled = set(params['disabled_skills'])
                return {'applied': {'skills': True}}
            if method == 'skills.reload':
                return {}
            self.fail(method)
        self.gateway.call = Mock(side_effect=rpc)

    def test_catalogue_includes_disabled_and_locked_skills_without_writing(self):
        rows = self.gateway.manage_skills()['skills']
        self.assertEqual([row['name'] for row in rows], ['alpha', 'beta', 'grounded-citations', 'hermes-agent'])
        self.assertFalse(rows[1]['enabled'])
        self.assertEqual(rows[2]['locked_reason'], 'Managed by Talaria')
        self.assertEqual(rows[3]['locked_reason'], 'Required by Hermes')
        self.assertEqual([row['description'] for row in rows],
                         ['Read documents.', 'Search the web.', 'Cite sources.', ''])
        self.assertEqual(self.gateway.call.call_args_list, [call('profiles.describe', {'name': 'default'}),
                                                          call('talaria.skills.describe')])

    def test_save_merges_only_changed_skills_with_current_configuration(self):
        self.gateway.manage_skills()
        self.disabled.add('disabled-elsewhere')
        rows = self.gateway.manage_skills({'alpha': False, 'beta': True})['skills']
        self.assertEqual(self.disabled, {'alpha', 'grounded-citations', 'uninstalled', 'disabled-elsewhere'})
        self.assertFalse(rows[0]['enabled'])
        self.assertTrue(rows[1]['enabled'])
        self.assertEqual([c.args[0] for c in self.gateway.call.call_args_list][-4:],
                         ['config.get', 'skills.reload', 'profiles.describe', 'talaria.skills.describe'])

    def test_metadata_errors_are_reported_without_writing_settings(self):
        original = self.gateway.call.side_effect
        for result in [{}, {'skills': [{'name': 'alpha', 'description': 42}]}]:
            with self.subTest(result=result):
                self.gateway.call.side_effect = lambda method, params=None: result if method == 'talaria.skills.describe' else original(method, params)
                with self.assertRaisesRegex(RuntimeError, 'invalid skill descriptions'):
                    self.gateway.manage_skills({'alpha': False})
                self.assertNotIn('alpha', self.disabled)

    def test_metadata_reader_uses_hermes_parser_and_keeps_disabled_and_platform_skills(self):
        import types
        from talaria_gateway_entry import skill_metadata
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = []
            for name, metadata in [('alpha', {'description': '  "Read documents."  ', 'platforms': ['macos']}),
                                   ('grounded-citations', {'description': 'Cite sources.'}),
                                   ('missing', {}), ('null', {'description': None})]:
                path = root / name / 'SKILL.md'
                path.parent.mkdir()
                path.write_text(json.dumps(metadata))
                paths.append(path)
            index = Mock(return_value=paths)
            parser = Mock(side_effect=lambda text: (json.loads(text), 'Ignore these body instructions.'))
            with patch.dict(sys.modules, {
                'agent.skill_utils': types.SimpleNamespace(iter_skill_index_files=index, parse_frontmatter=parser),
                'hermes_constants': types.SimpleNamespace(get_skills_dir=lambda: root),
            }):
                result = skill_metadata()
            index.assert_called_once_with(root, 'SKILL.md')
            self.assertEqual(parser.call_count, 4)
            self.assertEqual([row['description'] for row in result['skills']], ['Read documents.', 'Cite sources.', '', ''])
            self.assertEqual([row['name'] for row in result['skills']], ['alpha', 'grounded-citations', 'missing', 'null'])

    def test_invalid_unknown_and_locked_changes_never_write(self):
        for changes in [[], {'alpha': 1}, {'removed-skill': False}, {'grounded-citations': True}, {'hermes-agent': False}]:
            with self.subTest(changes=changes):
                self.gateway.call.reset_mock()
                with self.assertRaises((ValueError, RuntimeError)):
                    self.gateway.manage_skills(changes)
                self.assertFalse(any(c.args[0] == 'profiles.configure' for c in self.gateway.call.call_args_list))

    def test_malformed_catalogue_is_an_error_not_an_empty_list(self):
        for result in [{}, {'skills': [{}]}, {'skills': [{'name': 'alpha', 'enabled': 'false'}]}]:
            with self.subTest(result=result):
                self.gateway.call.side_effect = None
                self.gateway.call.return_value = result
                with self.assertRaisesRegex(RuntimeError, 'invalid skill catalogue'):
                    self.gateway.manage_skills()

    def test_worker_skill_requests_need_no_inference_credentials(self):
        for request in [{'operation': 'hermes_skills', 'request_id': 'r'},
                        {'operation': 'hermes_skills', 'request_id': 'r', 'changes': {'alpha': False}}]:
            with self.subTest(request=request), patch.object(worker, 'tui_gateway', return_value=self.gateway) as get:
                output = io.BytesIO()
                worker.handle_request(request, output)
                get.assert_called_once_with()
                events = [json.loads(line) for line in output.getvalue().splitlines()]
                self.assertEqual([event['type'] for event in events], ['delta', 'complete'])
                self.assertEqual(len(json.loads(events[0]['text'])['skills']), 4)


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
            gateway = HermesGateway(sys.executable, {**os.environ, 'PYTHONPATH': str(root)}, home,
                                    entry_module='tui_gateway.entry')
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


class CredentialRPCTests(unittest.TestCase):
    def setUp(self):
        import types
        self.store = {}
        self.config = Mock()
        self.config.OPTIONAL_ENV_VARS = {
            "SEARCH_API_KEY": {"category": "tool", "description": "Search service", "password": True},
            "WEBHOOK_SECRET": {"category": "setting", "password": True},
            "PROVIDER_KEY": {"category": "provider"},
            "CHAT_TOKEN": {"category": "messaging"},
        }
        self.config.load_env.side_effect = lambda: dict(self.store)
        self.config.is_managed.return_value = False
        self.config.save_env_value.side_effect = lambda key, value: self.store.update({key: value})
        self.config.remove_env_value.side_effect = lambda key: self.store.pop(key, None)
        scope = types.SimpleNamespace(is_env_managed=lambda key: False)
        modules = patch.dict(sys.modules, {"hermes_cli": types.SimpleNamespace(managed_scope=scope)})
        modules.start()
        self.addCleanup(modules.stop)

    def test_registry_roundtrip_and_no_secret_in_list(self):
        from talaria_gateway_entry import credentials
        result = credentials("set", {"key": "SEARCH_API_KEY", "value": "test-secret"}, self.config)
        self.assertEqual(result, {"ok": True, "key": "SEARCH_API_KEY", "is_set": True})
        listed = credentials("list", {}, self.config)
        self.assertEqual([row["key"] for row in listed["entries"]], ["SEARCH_API_KEY", "WEBHOOK_SECRET"])
        self.assertNotIn("test-secret", json.dumps(listed))
        self.assertTrue(listed["entries"][0]["is_set"])
        credentials("remove", {"key": "SEARCH_API_KEY"}, self.config)
        self.assertFalse(credentials("list", {}, self.config)["entries"][0]["is_set"])

    def test_rejects_unknown_provider_managed_and_multiline_writes(self):
        from talaria_gateway_entry import credentials
        for key, value in [("PATH", "bad"), ("PROVIDER_KEY", "bad"), ("SEARCH_API_KEY", "one\ntwo"), ("SEARCH_API_KEY", "")]:
            with self.assertRaises(ValueError):
                credentials("set", {"key": key, "value": value}, self.config)
        self.config.is_managed.return_value = True
        with self.assertRaises(ValueError):
            credentials("set", {"key": "SEARCH_API_KEY", "value": "secret"}, self.config)
        self.config.save_env_value.assert_not_called()

    def test_failure_is_not_reported_as_success(self):
        from talaria_gateway_entry import credentials
        self.config.save_env_value.side_effect = None
        with self.assertRaises(ValueError):
            credentials("set", {"key": "SEARCH_API_KEY", "value": "not-saved"}, self.config)

    def test_gateway_uses_only_credential_rpc(self):
        gateway = HermesGateway.__new__(HermesGateway)
        gateway.call = Mock(return_value={"ok": True})
        gateway.credentials("set", "SEARCH_API_KEY", "test-secret")
        gateway.call.assert_called_once_with("talaria.credentials.set", {"key": "SEARCH_API_KEY", "value": "test-secret"})
        with self.assertRaises(ValueError):
            gateway.credentials("exec", "", "")

    def test_rpc_error_never_echoes_value(self):
        from talaria_gateway_entry import register
        server = Mock()
        handlers = {}
        server.method.side_effect = lambda name: lambda fn: handlers.update({name: fn})
        register(server)
        with patch("talaria_gateway_entry.credentials", side_effect=RuntimeError("test-secret")):
            handlers["talaria.credentials.set"](1, {"value": "test-secret"})
        self.assertNotIn("test-secret", str(server._err.call_args))

    def test_entry_registers_credentials_and_automations_and_stops_scheduler(self):
        import types
        from talaria_gateway_entry import main
        for failure in (None, RuntimeError("gateway stopped")):
            with self.subTest(failure=failure):
                handlers = {}
                server = Mock(_LONG_HANDLERS=frozenset())
                server.method.side_effect = lambda name: lambda fn: handlers.update({name: fn})
                entry = types.SimpleNamespace(server=server, main=Mock(side_effect=failure))
                automations = Mock()
                automations.preference.exists.return_value = False
                with patch.dict(sys.modules, {"tui_gateway": types.SimpleNamespace(entry=entry)}), \
                     patch.dict(os.environ, {"HERMES_HOME": "/tmp/talaria-entry-test"}), \
                     patch("talaria_gateway_entry.configure_vm_database") as configure_database, \
                     patch("hermes_automations.Automations", return_value=automations):
                    if failure:
                        with self.assertRaisesRegex(RuntimeError, "gateway stopped"):
                            main()
                    else:
                        main()
                self.assertEqual(set(handlers), {"talaria.credentials.list", "talaria.credentials.set",
                                                "talaria.credentials.remove", "talaria.skills.describe", "talaria.automations"})
                self.assertIn("talaria.automations", server._LONG_HANDLERS)
                entry.main.assert_called_once_with()
                configure_database.assert_called_once_with()
                automations.stop_event.set.assert_called_once_with()

    def test_worker_uses_gateway_and_returns_structured_response(self):
        gateway = Mock()
        gateway.credentials.return_value = {"entries": []}
        output = io.BytesIO()
        with patch.object(worker, "tui_gateway", return_value=gateway):
            worker.handle_request({"operation": "hermes_credentials", "request_id": "keys", "action": "list"}, output)
        frames = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(json.loads(frames[0]["text"]), {"entries": []})
        self.assertEqual(frames[-1]["type"], "complete")


if __name__ == '__main__':
    unittest.main()
