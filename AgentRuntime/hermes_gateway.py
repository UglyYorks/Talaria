"""Hermes's native JSON-RPC transport, shared by chat and slash commands.

Protocol reference: NousResearch/hermes-agent, tui_gateway/entry.py and
tui_gateway/methods_tools.py (commands.catalog, command.dispatch, slash.exec).
"""
import json
import os
from pathlib import Path
from datetime import datetime, timezone
import queue
import threading
import time
from hermes_rpc_transport import HermesRPCTransport, RPCError
from hermes_sessions import SessionRegistry


# Talaria manages these bundled skills through Hermes's own profile settings.
# Keep the files installed so Hermes upgrades can continue to maintain them.
TALARIA_DISABLED_SKILLS = frozenset({"grounded-citations"})


def tool_activity(kind, payload):
    """Project Hermes tool_progress.py callbacks into bounded presentation data.

    Prefer Hermes's display context and redacted verbose text. Do not copy full
    tool arguments, binary results, or arbitrary result objects into the UI.
    """
    if not isinstance(payload, dict):
        return None

    def text(key, limit=1000):
        value = payload.get(key)
        return value[:limit] if isinstance(value, str) else ""

    name, tool_id = text("name", 200), text("tool_id", 200)
    if not name or (kind != "tool.generating" and not tool_id):
        return None
    state = {"tool.generating": "preparing", "tool.start": "running", "tool.complete": "completed"}[kind]
    result = payload.get("result")
    if kind == "tool.complete" and isinstance(result, dict):
        exit_code = result.get("exit_code")
        if (result.get("error") or result.get("is_error") is True or result.get("success") is False
                or (isinstance(exit_code, (int, float)) and exit_code != 0)):
            state = "failed"
    return {"id": tool_id or "preparing:" + name, "name": name, "state": state,
            "detail": text("context") or text("preview") or text("args_text"),
            "summary": text("summary") or text("result_text")}


def model_identity(selection):
    """Legacy IDs belong to OpenRouter; new selections retain provider identity."""
    provider, separator, model = selection.partition("::")
    if not separator:
        return "openrouter", selection
    if not provider or not model or any(c.isspace() for c in provider + model) or model.startswith("-"):
        raise ValueError("Invalid provider/model selection.")
    return provider, model


class HermesGateway:
    def __init__(self, python, environment, home, entry_module="talaria_gateway_entry"):
        self.home = home
        self.transport = HermesRPCTransport(python, environment, home, entry_module)
        self.lock = self.transport.lock
        self.listeners = self.transport.listeners
        self.pending = self.transport.pending
        self.process = self.transport.process
        self.registry = SessionRegistry(self.lock, home / "talaria-sessions.json")
        self.skill_settings_lock = threading.Lock()
        self._skill_policy_applied = False

    def call(self, method, params=None, timeout=120):
        return self.transport.call(method, params, timeout)

    def _session_registry(self):
        # Also supports isolated facade tests that inject fake RPC and state.
        if not hasattr(self, "registry"):
            self.registry = SessionRegistry(self.lock)
        return self.registry

    @property
    def sessions(self):
        return self._session_registry().sessions

    @sessions.setter
    def sessions(self, value):
        self._session_registry().sessions = value

    @property
    def waiting(self):
        return self._session_registry().waiting

    @waiting.setter
    def waiting(self, value):
        self._session_registry().waiting = value

    @property
    def session_locks(self):
        return self._session_registry().session_locks

    @session_locks.setter
    def session_locks(self, value):
        self._session_registry().session_locks = value

    @property
    def mappings(self):
        return self._session_registry().mappings

    @mappings.setter
    def mappings(self, value):
        self._session_registry().mappings = value

    @property
    def mapping_path(self):
        return self._session_registry().mapping_path

    @mapping_path.setter
    def mapping_path(self, value):
        self._session_registry().mapping_path = value

    def credentials(self, action, key="", value=""):
        if action not in ("list", "set", "remove"):
            raise ValueError("Unsupported credential action.")
        params = {} if action == "list" else {"key": key}
        if action == "set":
            params["value"] = value
        return self.call("talaria.credentials." + action, params)

    def disabled_skills(self):
        result = self.call("config.get", {"key": "full", "profile": "default"})
        config = result.get("config") if isinstance(result, dict) else None
        if not isinstance(config, dict):
            raise RuntimeError("Hermes returned invalid skill settings.")
        skills = config.get("skills")
        if skills is None:
            skills = {}
        if not isinstance(skills, dict):
            raise RuntimeError("Hermes returned invalid skill settings.")
        disabled = skills.get("disabled")
        if disabled is None:
            disabled = []
        if isinstance(disabled, str):
            disabled = [disabled]
        if not isinstance(disabled, list) or any(not isinstance(name, str) for name in disabled):
            raise RuntimeError("Hermes returned an invalid disabled-skill list.")
        return {name.strip() for name in disabled if name.strip()}

    def write_disabled_skills(self, desired):
        result = self.call("profiles.configure", {"name": "default", "disabled_skills": sorted(desired)})
        applied = result.get("applied") if isinstance(result, dict) else None
        if not isinstance(applied, dict) or applied.get("skills") is not True:
            raise RuntimeError("Hermes did not apply the skill settings.")
        if self.disabled_skills() != desired:
            raise RuntimeError("Hermes did not retain the skill settings.")

    def skill_catalogue(self):
        result = self.call("profiles.describe", {"name": "default"})
        rows = result.get("skills") if isinstance(result, dict) else None
        if not isinstance(rows, list) or any(not isinstance(row, dict) or
                not isinstance(row.get("name"), str) or not row["name"].strip() or
                not isinstance(row.get("enabled"), bool) for row in rows):
            raise RuntimeError("Hermes returned an invalid skill catalogue.")
        metadata = self.call("talaria.skills.describe")
        details = metadata.get("skills") if isinstance(metadata, dict) else None
        if not isinstance(details, list) or any(not isinstance(row, dict) or
                not isinstance(row.get("name"), str) or not isinstance(row.get("description"), str) for row in details):
            raise RuntimeError("Hermes returned invalid skill descriptions.")
        descriptions = {row["name"]: row["description"].strip() for row in details}
        skills = {}
        for row in rows:
            name = row["name"]
            reason = "Managed by Talaria" if name in TALARIA_DISABLED_SKILLS else (
                "Required by Hermes" if name == "hermes-agent" else "")
            skills[name] = {"name": name, "enabled": row["enabled"], "locked_reason": reason,
                            "description": descriptions.get(name, "")}
        return {"skills": sorted(skills.values(), key=lambda row: row["name"].casefold())}

    def manage_skills(self, changes=None):
        with self.skill_settings_lock:
            catalogue = self.skill_catalogue()
            if changes is None:
                return catalogue
            if not isinstance(changes, dict) or any(not isinstance(name, str) or
                    not isinstance(enabled, bool) for name, enabled in changes.items()):
                raise ValueError("Skill changes must map skill names to enabled states.")
            installed = {row["name"]: row for row in catalogue["skills"]}
            for name in changes:
                if name not in installed:
                    raise RuntimeError(f"Skill '{name}' is no longer installed. Reload the skill list.")
                if installed[name]["locked_reason"]:
                    raise RuntimeError(f"Skill '{name}' cannot be changed: {installed[name]['locked_reason']}.")
            existing = self.disabled_skills()
            desired = existing | TALARIA_DISABLED_SKILLS
            for name, enabled in changes.items():
                if enabled:
                    desired.discard(name)
                else:
                    desired.add(name)
            if desired != existing:
                self.write_disabled_skills(desired)
            # Also refresh after a retry whose previous write succeeded but reload failed.
            self.call("skills.reload")
            result = self.skill_catalogue()
            states = {row["name"]: row["enabled"] for row in result["skills"]}
            if any(states.get(name) != enabled for name, enabled in changes.items()):
                raise RuntimeError("Hermes did not retain the requested skill changes. Reload the skill list.")
            return result

    def apply_skill_policy(self):
        """Apply once per runtime, before any session is created or resumed.

        Reconcile at startup so existing installations and Hermes upgrades receive
        Talaria's policy too. Only the global disabled list is changed; preserve
        user entries even when their corresponding skills are no longer installed.
        """
        if self._skill_policy_applied:
            return

        try:
            existing = self.disabled_skills()
            desired = existing | TALARIA_DISABLED_SKILLS
            if desired != existing:
                self.write_disabled_skills(desired)
            # Startup can discover slash commands before configuration is applied.
            # Refresh that catalogue before Talaria advertises it to the user.
            self.call("skills.reload")
        except RPCError as exc:
            raise RuntimeError("Could not apply Talaria's Hermes skill settings. "
                               "Update Hermes and retry. " + str(exc)) from exc
        self._skill_policy_applied = True

    def catalog(self):
        result = self.call("commands.catalog")
        if not isinstance(result.get("pairs"), list):
            raise RuntimeError("This Hermes version does not provide a command catalogue. Update Hermes and retry.")
        return result

    def history_sessions(self):
        # session.list has a limit but no offset. Expand the window until complete;
        # never silently restrict search to its default 200 rows.
        limit = 200
        while True:
            result = self.call("session.list", {"limit": limit})
            rows = result.get("sessions")
            if not isinstance(rows, list) or any(not isinstance(row, dict) or not row.get("id") for row in rows):
                raise RuntimeError("Hermes returned an invalid session list.")
            if len(rows) < limit:
                break
            if limit >= 102400:
                raise RuntimeError("Hermes history is too large to load completely.")
            limit *= 2
        with self.lock:
            aliases = {}
            for chat, stored in self.mappings.items():
                if stored not in aliases or chat != stored:
                    aliases[stored] = chat
        sessions = []
        seen = set()
        for row in rows:
            stored = row["id"]
            if stored in seen:
                continue
            seen.add(stored)
            sessions.append({**row, "hermes_session_id": aliases.get(stored, stored),
                             "title": row.get("title") or row.get("preview") or "Untitled session",
                             "model": (str(row["provider"]) + "::" + str(row.get("model") or "")) if row.get("provider") else row.get("model", ""),
                             "created_at": self.history_date(row.get("started_at")),
                             "updated_at": self.history_date(row.get("last_active") or row.get("started_at"))})
        return {"sessions": sessions}

    @staticmethod
    def history_date(value):
        if isinstance(value, (int, float)):
            return datetime.fromtimestamp(value, timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        return value if isinstance(value, str) else ""

    def history_session(self, stored):
        with self.lock:
            if getattr(self, "_provider_mutating", False):
                raise RuntimeError("Wait for provider setup to finish before opening history.")
            gate = self._session_registry().gate(stored)
            acquired = gate.acquire(blocking=False)
        if not acquired:
            raise RuntimeError("Wait for this Hermes session to finish before opening it.")
        try:
            return self._history_session(stored)
        finally:
            gate.release()

    def _history_session(self, stored):
        if not stored:
            raise RuntimeError("A Hermes session ID is required.")
        with self.lock:
            live = next((state for chat, state in self.sessions.items()
                         if self.mappings.get(chat, chat) == stored), None)
        if live:
            sid = live["id"]
            model = live["model"]
        else:
            # Explicit resume: a missing history row must never create a new session.
            result = self.call("session.resume", {"session_id": stored})
            info = result.get("info") or {}
            model = info.get("model") or ""
            if info.get("provider") and model:
                model = info["provider"] + "::" + model
            with self.lock:
                chat_id = next((chat for chat, target in self.mappings.items() if target == stored), stored)
            sid = self._remember(chat_id, result, model)
        result = self.call("session.history", {"session_id": sid})
        messages = result.get("messages")
        if not isinstance(messages, list):
            raise RuntimeError("Hermes returned an invalid transcript.")
        transcript = []
        for message in messages:
            if not isinstance(message, dict):
                raise RuntimeError("Hermes returned an invalid transcript message.")
            if message.get("role") not in {"user", "assistant", "system"}:
                continue
            text = message.get("text", "")
            if not isinstance(text, str):
                raise RuntimeError("Hermes returned an invalid transcript message.")
            shaped = {"role": message["role"], "content": text,
                               "thinking": message.get("reasoning") or message.get("reasoning_content") or "",
                               "created_at": self.history_date(message.get("timestamp"))}
            source_id = message.get("source_message_id", message.get("row_id"))
            if source_id is not None:
                shaped["source_message_id"] = source_id
            for key in ("source_tool_call_ids", "notification"):
                if key in message:
                    shaped[key] = message[key]
            transcript.append(shaped)
        return {"messages": transcript, "model": model}

    def delete_history_session(self, stored):
        with self.lock:
            if getattr(self, "_provider_mutating", False):
                raise RuntimeError("Wait for provider setup to finish before deleting history.")
            gate = self._session_registry().gate(stored)
            acquired = gate.acquire(blocking=False)
        if not acquired:
            raise RuntimeError("Wait for this Hermes session to finish before deleting it.")
        try:
            return self._delete_history_session(stored)
        finally:
            gate.release()

    def _delete_history_session(self, stored):
        if not stored:
            raise RuntimeError("A Hermes session ID is required.")
        with self.lock:
            aliases = [chat for chat in self.sessions if self.mappings.get(chat, chat) == stored]
            if any(self.sessions[chat]["id"] in self.listeners for chat in aliases):
                raise RuntimeError("Wait for this Hermes session to finish before deleting it.")
            runtime_ids = {self.sessions[chat]["id"] for chat in aliases}
        for sid in runtime_ids:
            self.call("session.close", {"session_id": sid})
        with self.lock:
            for chat in aliases:
                self.sessions.pop(chat, None)
                self.waiting.pop(chat, None)
        result = self.call("session.delete", {"session_id": stored})
        if not result.get("deleted"):
            raise RuntimeError("Hermes did not confirm session deletion.")
        with self.lock:
            self.mappings = {chat: target for chat, target in self.mappings.items() if target != stored}
            self._session_registry().save_mappings()
        return {"deleted": stored}

    def model_options(self):
        result = self.call("model.options", {"explicit_only": True})
        if not isinstance(result.get("providers"), list):
            raise RuntimeError("Hermes returned an invalid model catalogue.")
        return result

    def providers(self, params):
        action = params.get("action")
        mutating = action not in {"list", "models", "login.poll", "login.cancel"}
        if mutating:
            with self.lock:
                if (self.listeners or getattr(self, "_support_requests", 0) or any(lock.locked() for lock in self.session_locks.values())
                        or getattr(self, "_provider_mutating", False)):
                    raise RuntimeError("Finish the active response before changing provider settings.")
                self._provider_mutating = True
        try:
            return self._provider_request(params)
        finally:
            if mutating:
                with self.lock:
                    self._provider_mutating = False

    def _provider_request(self, params):
        action = params.get("action")
        if action == "list":
            catalogue = self.call("model.options", {"include_unconfigured": True, "refresh": True})
            metadata = self.call("talaria.providers", {"action": "describe"})
            by_slug = {row["slug"]: row for row in catalogue.get("providers", [])}
            rows = []
            for descriptor in metadata["providers"]:
                row = dict(by_slug.pop(descriptor["slug"], {}))
                row.update(descriptor)
                row["name"] = descriptor["label"]
                rows.append(row)
            rows.extend(by_slug.values())
            return {"providers": rows}
        if action == "models":
            catalogue = self.call("model.options", {"include_unconfigured": True, "refresh": True})
            return {"providers": [row for row in catalogue.get("providers", []) if row.get("slug") == params.get("slug")]}
        if action == "select":
            provider, model = model_identity(params.get("selection", ""))
            if provider == "custom" and params.get("custom"):
                endpoint = self.call("talaria.providers", {"action": "custom.configure", "slug": provider,
                                                          "model": model, "values": params["custom"]})
                provider = endpoint["slug"]
            readiness = self.call("setup.runtime_check", {"provider": provider})
            if not readiness.get("ok"):
                raise RuntimeError("Connect this provider before choosing a model.")
            result = self.call("config.set", {"key": "model", "value": f"{model} --provider {provider}",
                                             "confirm_expensive_model": bool(params.get("confirmed"))})
            if result.get("confirm_required"):
                return result
            if result.get("value") != model:
                raise RuntimeError("Hermes did not accept this model.")
            return {"ok": True, "selection": provider + "::" + model}
        result = self.call("talaria.providers", params)
        if action == "configure" or (action == "login.poll" and result.get("status") == "approved"):
            # Rebuild idle clients with the new credentials on their next turn.
            # Persistent session mappings/history remain owned by Hermes.
            with self.lock:
                self._stale_sessions = set(self.sessions)
        return result

    def generate_text(self, model, instructions, user_input):
        with self.lock:
            if getattr(self, "_provider_mutating", False):
                raise RuntimeError("Wait for provider setup to finish before generating text.")
            self._support_requests = getattr(self, "_support_requests", 0) + 1
        try:
            return self._generate_text(model, instructions, user_input)
        finally:
            with self.lock:
                self._support_requests -= 1

    def _generate_text(self, model, instructions, user_input):
        provider, model_id = model_identity(model)
        # A private draft runtime supplies the chosen supporting model to llm.oneshot.
        # No prompt.submit, conversation history, or persistent Talaria mapping is used.
        created = self.call("session.create", {"model": model_id, "provider": provider, "source": "talaria", "hidden": True})
        sid = created.get("session_id")
        if not sid:
            raise RuntimeError("Hermes did not create a supporting-model session.")
        try:
            # Bare model + --session waits for the lazy agent build and explicitly avoids
            # persisting a global model change. oneshot can then inherit its runtime.
            if "::" in model:
                self._apply_session_model(sid, model)
                configured = {}
            else:
                configured = self.call("config.set", {"session_id": sid, "key": "model", "value": model + " --session"})
            if configured.get("confirm_required"):
                raise RuntimeError(configured.get("confirm_message") or "Hermes requires confirmation of the supporting model.")
            result = self.call("llm.oneshot", {"session_id": sid, "instructions": instructions,
                                               "input": user_input, "max_tokens": 1024})
            text = result.get("text")
            if not isinstance(text, str) or not text.strip():
                raise RuntimeError("Hermes returned an empty text-generation response.")
            return text
        finally:
            # Cleanup must not conceal the original inference error.
            try:
                self.call("session.close", {"session_id": sid})
            except (OSError, RuntimeError):
                pass

    def _remember(self, chat_id, result, model):
        sid = result.get("session_id")
        stored = result.get("stored_session_id") or result.get("session_key") or result.get("resumed")
        if not sid or not stored:
            raise RuntimeError("Hermes returned a session without its persistent identity.")
        with self.lock:
            self._session_registry().remember_mapping(chat_id, stored)
            self.sessions[chat_id] = {"id": sid, "model": model}
        return sid

    def _apply_session_model(self, sid, model):
        provider, model_id = model_identity(model)
        value = f"{model_id} --session"
        if "::" in model:
            self.call("talaria.session.ready", {"session_id": sid})
            value += f" --provider {provider}"
        # A bare model waits for Hermes' lazy agent build. Supplying --provider
        # skips that wait and can race a resumed agent loading its old model.
        result = self.call("config.set", {"session_id": sid, "key": "model",
                                          "value": value})
        if result.get("confirm_required"):
            raise RuntimeError(result.get("confirm_message") or "Hermes requires confirmation of this model change.")
        if result.get("value") != model_id:
            raise RuntimeError(f"Hermes did not accept the requested model {model}.")
        if "::" in model:
            verified = self.call("talaria.session.verify_model", {"session_id": sid, "model": model_id, "provider": provider}).get("verified")
        else:
            status = self.call("session.status", {"session_id": sid})
            verified = f"Model: {model_id} ({provider})" in status.get("output", "").splitlines()
        if not verified:
            raise RuntimeError(f"Hermes has not activated {model}. Wait for the current response to finish and retry.")
        # This audit contains model identifiers only, never prompts or credentials.
        with (self.home / "talaria-model-switches.jsonl").open("a") as log:
            log.write(json.dumps({"session_id": sid, "model": model, "verified": True, "time": time.time()}) + "\n")

    def session(self, chat_id, model, force_model=False):
        chat_id = self._session_registry().runtime_owner(chat_id)
        if chat_id in getattr(self, "_stale_sessions", set()):
            state = self.sessions.get(chat_id)
            if state:
                self.call("session.close", {"session_id": state["id"]})
                self.sessions.pop(chat_id, None)
            self._stale_sessions.discard(chat_id)
        if chat_id not in self.sessions:
            try:
                result = self.call("session.resume", {"session_id": self.mappings.get(chat_id, chat_id)})
            except RPCError as exc:
                if exc.code != 4007:
                    raise
                result = self.call("session.create", {"model": model_identity(model)[1], "provider": model_identity(model)[0], "source": "talaria"})
            # Both create and resume are lazy. Pin and verify after loading before
            # remembering a selection, including the very first turn.
            self._remember(chat_id, result, "")
        state = self.sessions[chat_id]
        if force_model or state["model"] != model:
            self._apply_session_model(state["id"], model)
            state["model"] = model
        return state["id"]

    def select_model(self, chat_id, model):
        with self.lock:
            if getattr(self, "_provider_mutating", False):
                raise RuntimeError("Wait for provider setup to finish before sending or switching models.")
            chat_id = self._session_registry().runtime_owner(chat_id)
            session_lock = self._session_registry().gate(chat_id)
            acquired = session_lock.acquire(blocking=False)
        if not acquired:
            raise RuntimeError("Wait for the current response to finish before switching models.")
        try:
            with self.lock:
                state = self.sessions.get(chat_id)
                if state and state["id"] in self.listeners:
                    raise RuntimeError("Finish the pending Hermes interaction before switching models.")
            return self.session(chat_id, model, force_model=True)
        finally:
            session_lock.release()

    def command(self, chat_id, sid, text, model, depth=0):
        if depth >= 8:
            raise RuntimeError("Hermes command alias cycle detected.")
        parts = text.lstrip("/").split(maxsplit=1)
        if not parts:
            raise RuntimeError("Choose a Hermes command after /.")
        name, arg = parts[0].lower(), parts[1] if len(parts) > 1 else ""
        catalog = self.catalog()
        canonical = catalog.get("canon", {}).get("/" + name, "/" + name).lstrip("/")
        known = {pair[0] for pair in catalog["pairs"] if isinstance(pair, list) and pair}
        if "/" + canonical not in known and "/" + name not in known:
            raise RuntimeError(f"Unknown Hermes command: /{name}")
        params = {"session_id": sid}
        # These commands are host actions in Hermes's TUI, not slash-worker actions.
        if canonical in {"new", "reset", "clear"}:
            result = self.call("session.create", {"model": model_identity(model)[1], "provider": model_identity(model)[0], "source": "talaria", "title": arg})
            self._remember(chat_id, result, model)
            return {"output": "Started a new Hermes session."}
        if canonical in {"resume"} and arg:
            result = self.call("session.resume", {"session_id": arg})
            self._remember(chat_id, result, model)
            return {"output": "Resumed Hermes session " + self.mappings[chat_id] + "."}
        if canonical in {"sessions", "resume"}:
            result = self.call("session.list")
            return {"output": json.dumps(result, ensure_ascii=False, indent=2)}
        if canonical == "model" and arg:
            result = self.call("config.set", {**params, "key": "model", "value": arg})
            return {"output": result.get("confirm_message") or result.get("warning") or "Model: " + str(result.get("value", arg))}
        if canonical in {"title", "rename"}:
            result = self.call("session.title", {**params, **({"title": arg} if arg else {})})
            return {"output": "Session title: " + str(result.get("title") or "Untitled")}
        if canonical == "save":
            result = self.call("session.save", params)
            return {"output": "Saved conversation to " + str(result.get("file", "Hermes"))}
        if canonical in {"branch", "fork"}:
            result = self.call("session.branch", {**params, **({"title": arg} if arg else {})})
            self._remember(chat_id, result, model)
            return {"output": "Branched Hermes session " + self.mappings[chat_id] + "."}
        if canonical in {"stop", "interrupt"}:
            self.call("session.interrupt", params)
            return {"output": "Interrupted the Hermes session."}
        if canonical in {"quit", "exit"}:
            self.call("session.close", params)
            self.sessions.pop(chat_id, None)
            return {"output": "Closed the Hermes session."}
        try:
            result = self.call("command.dispatch", {**params, "name": name, "arg": arg})
        except RPCError as exc:
            # Only the explicit dispatcher miss may fall through. Never retry a failed
            # command that could already have changed state or executed a custom action.
            if exc.code != 4018 or not str(exc).startswith("not a quick/plugin/bundle/skill command:"):
                raise
            result = self.call("slash.exec", {**params, "command": text})
        if result.get("type") == "alias":
            target = result.get("target", "").strip()
            if not target:
                raise RuntimeError("Hermes returned an empty command alias.")
            return self.command(chat_id, sid, target + (" " + arg if arg else ""), model, depth + 1)
        return result

    def run(self, chat_id, model, text, delta, cancellation=None, approval_response=None, wait_for_previous_turn=False):
        if cancellation and cancellation.cancelled():
            return
        with self.lock:
            if getattr(self, "_provider_mutating", False):
                raise RuntimeError("Wait for provider setup to finish before sending or switching models.")
            chat_id = self._session_registry().runtime_owner(chat_id)
            session_lock = self._session_registry().gate(chat_id)
            acquired = session_lock.acquire(blocking=False)
        control_command = (text.split(maxsplit=1) or [""])[0].lower() in {"/stop", "/interrupt", "/steer"}
        if not acquired and wait_for_previous_turn and not control_command and approval_response is None:
            # The native Stop finishes locally before Hermes emits its terminal
            # event. Keep the new turn out of that listener until it is drained.
            deadline = time.monotonic() + 30
            while not acquired:
                if cancellation and cancellation.cancelled():
                    return
                if time.monotonic() >= deadline:
                    raise RuntimeError("Hermes is still stopping the previous turn. Try sending again.")
                acquired = session_lock.acquire(timeout=0.1)
                if acquired:
                    with self.lock:
                        if getattr(self, "_provider_mutating", False):
                            session_lock.release()
                            raise RuntimeError("Wait for provider setup to finish before sending or switching models.")
        if not acquired:
            if approval_response is not None:
                raise RuntimeError("This approval is already being submitted. Wait for the current request.")
            name = text.split(maxsplit=1)[0].lower()
            if name not in {"/stop", "/interrupt", "/steer"} or chat_id not in self.sessions:
                raise RuntimeError("Hermes is busy. Use /stop or /steer, or wait for the current turn.")
            result = self.command(chat_id, self.sessions[chat_id]["id"], text, model)
            delta("content", result.get("output") or "Hermes received the command.")
            return
        try:
            sid = self.session(chat_id, model)
            if cancellation and cancellation.cancelled():
                return
            waiting = self.waiting.get(chat_id)
            if approval_response is not None and (not waiting or waiting[2] != "approval.request"):
                raise RuntimeError("This approval is no longer pending. Send your request again.")
            if waiting:
                sid, events, kind, payload = waiting
                if kind == "approval.request":
                    if approval_response is not None:
                        if not isinstance(approval_response, dict) or approval_response.get("request_id") != payload.get("request_id"):
                            raise RuntimeError("This approval has expired or was replaced. Use the current approval card.")
                        choice = approval_response.get("choice")
                    else:
                        choice = {"/approve": "once", "/approve once": "once", "/approve session": "session",
                                  "/approve always": "always", "/deny": "deny"}.get(text.strip().lower())
                    if choice not in payload.get("choices", ["once", "deny"]):
                        raise RuntimeError("Reply /approve or /deny to the pending Hermes command.")
                    result = self.call("approval.respond", {"session_id": sid, "request_id": payload.get("request_id"), "choice": choice})
                else:
                    result = self.call("clarify.respond", {"session_id": sid, "request_id": payload.get("request_id"), "answer": text})
                self.waiting.pop(chat_id, None)
                if result.get("expired") or (kind == "approval.request" and result.get("resolved") is False):
                    with self.lock:
                        self.listeners.pop(sid, None)
                    raise RuntimeError("Hermes's input request expired. Send your request again.")
            elif text.startswith("/"):
                result = self.command(chat_id, sid, text, model)
                for key in ("notice", "output", "warning"):
                    if result.get(key):
                        delta("content", str(result[key]) + "\n")
                if result.get("type") == "prefill":
                    delta("content", result.get("message", ""))
                    return
                if result.get("type") not in {"send", "skill"}:
                    return
                text = result.get("message", "")
                if not text:
                    raise RuntimeError("Hermes returned an empty command prompt.")
            if not waiting:
                events = queue.Queue()
                with self.lock:
                    if sid in self.listeners:
                        raise RuntimeError("This Hermes session is already running in another chat.")
                    self.listeners[sid] = events
            try:
                if cancellation and cancellation.cancelled():
                    return
                if not waiting:
                    self.call("prompt.submit", {"session_id": sid, "text": text})
                if cancellation:
                    # Bind only after submission; a Stop during submit is delivered here.
                    # Drain its terminal event before releasing this session's lock, so
                    # a following turn cannot receive the interrupted turn's events.
                    cancellation.on_cancel(lambda: self.call("session.interrupt", {"session_id": sid}))
                deadline = time.monotonic() + 600
                streamed = ""
                while True:
                    event = events.get(timeout=max(0.01, deadline - time.monotonic()))
                    kind, payload = event.get("type"), event.get("payload") or {}
                    if cancellation and cancellation.cancelled():
                        if kind in {"message.complete", "error"}:
                            return
                        continue
                    if kind == "message.delta":
                        chunk = payload.get("text", "")
                        streamed += chunk
                        delta("content", chunk)
                    elif kind == "reasoning.delta":
                        delta("thinking", payload.get("text", ""))
                    elif kind == "thinking.delta":
                        # Hermes's thinking callback replaces its spinner text;
                        # it is not a reasoning token stream. Empty text clears it.
                        delta("status", payload.get("text", ""))
                    elif kind in {"tool.generating", "tool.start", "tool.complete"}:
                        activity = tool_activity(kind, payload)
                        if activity:
                            delta("tool_activity", activity)
                    elif kind == "message.complete":
                        if payload.get("status") == "error":
                            raise RuntimeError(payload.get("text") or "Hermes turn failed.")
                        final = payload.get("text", "")
                        if not streamed:
                            delta("content", final)
                        elif final.startswith(streamed):
                            delta("content", final[len(streamed):])
                        elif final and not streamed.endswith(final):
                            delta("content", "\n" + final)
                        return
                    elif kind == "error":
                        raise RuntimeError(payload.get("message") or "Hermes turn failed.")
                    elif kind in {"approval.request", "clarify.request"}:
                        self.waiting[chat_id] = (sid, events, kind, payload)
                        if kind == "approval.request":
                            delta("approval", payload)
                            return
                        question = payload.get("question") or payload.get("command") or json.dumps(payload.get("questions", []), ensure_ascii=False)
                        suffix = "\nReply /approve or /deny." if kind == "approval.request" else "\nReply with your answer."
                        delta("content", "\n" + question + suffix)
                        return
                    elif kind in {"sudo.request", "secret.request"}:
                        self.call("session.interrupt", {"session_id": sid})
                        raise RuntimeError("Hermes needs a secure credential. Configure it in the Hermes terminal, then retry; do not paste secrets into chat.")
            except queue.Empty:
                self.call("session.interrupt", {"session_id": sid})
                raise RuntimeError("Hermes turn timed out.")
            finally:
                with self.lock:
                    if chat_id not in self.waiting:
                        self.listeners.pop(sid, None)

        finally:
            session_lock.release()
