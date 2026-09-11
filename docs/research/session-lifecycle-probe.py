#!/usr/bin/env python3
"""Deterministic fake-RPC probe; no Hermes process, network or stored data used."""
from pathlib import Path
import sys
import threading
import tempfile

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(root / 'AgentRuntime'))
from hermes_gateway import HermesGateway

with tempfile.TemporaryDirectory() as directory:
    gateway = HermesGateway.__new__(HermesGateway)
    gateway.lock = threading.RLock()
    gateway.sessions = {'chat': {'id': 'live', 'model': 'old'}}
    gateway.mappings = {'chat': 'stored'}
    gateway.listeners, gateway.waiting, gateway.session_locks = {}, {}, {}
    gateway.home = Path(directory)
    gateway.mapping_path = gateway.home / 'sessions.json'
    blocked, release = threading.Event(), threading.Event()
    methods, errors, selected = [], [], []

    def call(method, params):
        methods.append(method)
        if method == 'config.set':
            blocked.set()
            if not release.wait(2):
                raise TimeoutError('Probe did not release blocked fake RPC')
            return {'value': 'new'}
        if method == 'session.status':
            return {'output': 'Model: new (openrouter)'}
        if method == 'session.delete':
            return {'deleted': True}
        return {}

    gateway.call = call

    def select():
        try:
            selected.append(gateway.select_model('chat', 'new'))
        except Exception as exc:
            errors.append(str(exc))

    thread = threading.Thread(target=select)
    thread.start()
    assert blocked.wait(2)
    try:
        print('model switch owns chat lock:', gateway.session_locks['chat'].locked())
        try:
            gateway.delete_history_session('stored')
            blocked_delete = False
        except RuntimeError:
            blocked_delete = True
        print('concurrent deletion blocked:', blocked_delete)
    finally:
        release.set()
        thread.join(2)
    print('model switch result:', selected, 'errors:', errors)
    print('RPC order:', methods)
    print('session retained:', bool(gateway.sessions))
    assert blocked_delete and methods == ['config.set', 'session.status']
    assert selected == ['live'] and not errors and gateway.sessions
