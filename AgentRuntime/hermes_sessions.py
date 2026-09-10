"""Persistent session identity and per-session lifecycle exclusion.

Aliases of a persisted Hermes session always share a gate. The gateway's RPC
reader never waits on these gates, so interrupt delivery and terminal-event
routing remain available while a turn drains.
"""
import json
import threading


class SessionRegistry:
    def __init__(self, lock, mapping_path=None):
        self.lock = lock
        self.mapping_path = mapping_path
        self.mappings = (json.loads(mapping_path.read_text())
                         if mapping_path and mapping_path.exists() else {})
        self.sessions = {}
        self.waiting = {}
        self.session_locks = {}

    def runtime_owner(self, identity):
        with self.lock:
            stored = self.mappings.get(identity, identity)
            return next((alias for alias in self.sessions
                         if self.mappings.get(alias, alias) == stored), identity)

    def gate(self, identity):
        with self.lock:
            stored = self.mappings.get(identity, identity)
            aliases = [alias for alias, target in self.mappings.items() if target == stored]
            keys = [stored, identity, *aliases]
            existing = [self.session_locks[key] for key in keys if key in self.session_locks]
            # Compatibility with an already-leased alias: never install a fresh
            # unlocked gate over work that began under that alias.
            leased = set(gate for gate in existing if gate.locked())
            if len(leased) > 1:
                raise RuntimeError("This Hermes session has overlapping operations. Retry after they finish.")
            gate = next(iter(leased), None)
            if gate is None:
                gate = existing[0] if existing else threading.Lock()
            for key in keys:
                self.session_locks[key] = gate
            return gate

    def remember_mapping(self, chat_id, stored):
        with self.lock:
            gate = self.gate(chat_id)
            other = self.session_locks.get(stored)
            if other is not None and other is not gate and other.locked():
                raise RuntimeError("This Hermes session is already being opened in another chat.")
            self.mappings[chat_id] = stored
            self.session_locks[stored] = gate
            for alias, target in self.mappings.items():
                if target == stored: self.session_locks[alias] = gate
            self.save_mappings()

    def save_mappings(self):
        with self.lock:
            if self.mapping_path is None: return
            temporary = self.mapping_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(self.mappings))
            temporary.replace(self.mapping_path)
