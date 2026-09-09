"""Durable findings and exact transcript anchors, owned by the Hermes profile.

This module is also the installed native Hermes plugin's entry point. Its copy
under HERMES_HOME/plugins works in detached cron workers without Talaria's
gateway process or PYTHONPATH. Only the gateway exposes user-facing RPCs.
"""
import contextlib
from datetime import datetime, timezone
import inspect
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import uuid


PLUGIN = "talaria-notifications"
TOOLSET = "talaria_notifications"
TOOL = "create_notification"
URGENCIES = {"low": 0, "medium": 1, "high": 2}
FIELDS = {"title": 160, "summary": 2000, "finding_key": 512, "change_key": 2048}
DESCRIPTION_FILE = "talaria-notification-tool-description.txt"
_setup_lock = threading.RLock()


def _text(value, field, limit):
    if not isinstance(value, str) or not value.strip() or len(value) > limit or "\x00" in value:
        raise ValueError(f"{field} must be non-empty text of at most {limit} characters.")
    return value.strip()


def _integer(value, field, minimum=0):
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        raise ValueError(f"{field} must be an integer of at least {minimum}.")
    return value


def _date(value):
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, timezone.utc).isoformat()
    return value if isinstance(value, str) else ""


def _timestamp(value):
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except (AttributeError, TypeError, ValueError):
        raise ValueError("Hermes did not provide a valid execution timestamp.")


def _arguments(args):
    if not isinstance(args, dict) or set(args) != set(FIELDS) | {"urgency"}:
        raise ValueError("A notification requires title, summary, urgency, finding_key and change_key only.")
    clean = {key: _text(args.get(key), key, limit) for key, limit in FIELDS.items()}
    if args.get("urgency") not in URGENCIES:
        raise ValueError("Notification urgency must be low, medium or high.")
    return {**clean, "urgency": args["urgency"]}


@contextlib.contextmanager
def _session_db(home):
    from hermes_state_registry import acquire, release
    database = acquire(Path(home) / "state.db")
    try:
        yield database
    finally:
        release(database)


def _calls(message):
    calls = message.get("tool_calls") or []
    if isinstance(calls, str):
        calls = json.loads(calls)
    return calls if isinstance(calls, list) else []


def _plain_content(value):
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(part.get("text", "") for part in value
                         if isinstance(part, dict) and isinstance(part.get("text"), str))
    return ""


class HermesSources:
    def __init__(self, home):
        self.home = Path(home)

    def verify(self, task_id, session_id, tool_call_id, args):
        """Attribution is supplied by dispatch, then checked against Hermes stores."""
        from cron.executions import get_execution
        from cron.jobs import get_job
        if not isinstance(task_id, str) or not task_id.startswith("cron:"):
            raise ValueError("Notifications require an automation execution context.")
        job_id, separator, run_id = task_id[5:].rpartition(":")
        if not separator or not job_id or not run_id or not session_id or not tool_call_id:
            raise ValueError("Hermes did not provide notification source identities.")
        execution = get_execution(run_id)
        if not execution or execution.get("job_id") != job_id:
            raise ValueError("The notification execution does not belong to this task.")
        job = get_job(job_id)
        if not job:
            raise ValueError("The automation no longer exists.")
        # Tool-call rows are committed by Hermes before dispatch. Never invent a
        # UI anchor from a timestamp or the newest visible assistant message.
        anchor = None
        with _session_db(self.home) as database:
            if not database.get_session(session_id):
                raise ValueError("The notification session has not been persisted.")
            offset = 0
            while anchor is None:
                rows = database.get_messages(session_id, include_inactive=True,
                                             limit=200, offset=offset, latest=True)
                for row in reversed(rows):
                    if row.get("role") != "assistant":
                        continue
                    for call in _calls(row):
                        if call.get("id") != tool_call_id:
                            continue
                        function = call.get("function") or {}
                        raw_args = function.get("arguments") or {}
                        stored_args = json.loads(raw_args) if isinstance(raw_args, str) else raw_args
                        name = function.get("name")
                        if name == "tool_call":
                            # Hermes progressive disclosure persists the bridge
                            # call, while dispatch supplies the underlying tool.
                            from tools.tool_search import resolve_underlying_call
                            name, stored_args, bridge_error = resolve_underlying_call(stored_args)
                            if bridge_error:
                                raise ValueError("The persisted notification bridge call is invalid.")
                        if name != TOOL or _arguments(stored_args) != args:
                            raise ValueError("The persisted notification call does not match this request.")
                        anchor = row
                        break
                if anchor or len(rows) < 200:
                    break
                offset += len(rows)
        if not anchor or not isinstance(anchor.get("id"), int):
            raise ValueError("The notification's tool-calling message has not been persisted.")
        return {"task_id": job_id, "task_name": str(job.get("name") or job_id),
                "source_kind": "cron", "run_id": run_id, "session_id": session_id,
                "message_id": anchor["id"], "tool_call_id": tool_call_id,
                "run_order": _timestamp(execution.get("claimed_at")),
                "execution_status": execution.get("status")}

    def open(self, notification, related_notifications=()):
        from agent.compaction_display import project_compaction_message_for_display
        sid, anchor_id = notification["session_id"], notification["message_id"]
        with _session_db(self.home) as database:
            session = database.get_session(sid)
            if not session:
                raise ValueError("This notification's source session was deleted.")
            continuation = database.resolve_resume_session_id(sid)
            lineage = database._resume_lineage_ids(continuation)
            if sid not in lineage:
                raise ValueError("Hermes could not resolve this notification's conversation lineage.")
            continued_session = database.get_session(continuation) or session
            sessions = [database.get_session(identifier) for identifier in lineage]
            updated_at = max((_timestamp(item.get("last_active") or item.get("started_at"))
                              for item in sessions if item and (item.get("last_active") or item.get("started_at"))),
                             default=0)
            # One Hermes-owned SELECT is a finite SQLite snapshot across every
            # segment, including intermediate compression children. Paging only
            # the original session would erase completed continuation turns when
            # the native cache replaces its transcript. Explicit branch/delegate
            # sessions are excluded by Hermes's resume-lineage resolver.
            raw_rows = database._fetch_conversation_rows(lineage, "", with_session_id=True)
            originals = {row["id"]: row for row in raw_rows}
            anchor = originals.get(anchor_id)
            if anchor is None or anchor["session_id"] != sid or not any(
                    call.get("id") == notification["tool_call_id"] for call in _calls(dict(anchor))):
                raise ValueError("This notification's source message is no longer available.")
            related = related_notifications(lineage) if callable(related_notifications) else related_notifications
            cards_by_call = {}
            protected = set()
            for item in [*related, notification]:
                original = originals.get(item["message_id"])
                if original is not None and original["session_id"] == item["session_id"]:
                    cards_by_call.setdefault(item["tool_call_id"], []).append(item)
                    protected.add(item["message_id"])
            # Hermes owns the exact generation identity: role, original
            # timestamp, content and all tool metadata. This collapses inherited
            # copies without merging ordinary repeated text. Keep notification
            # anchors even if an Undo later made their source row inactive.
            display_rows = database._dedupe_display_generations([
                row for row in raw_rows if row["active"] or row["compacted"] or row["id"] in protected])
            rows = []
            for raw in display_rows:
                row = database._row_to_message_dict(raw, warn_context="Talaria notification source", summary_flag=True)
                cards = {}
                for call in _calls(row):
                    for card in cards_by_call.get(call.get("id"), []):
                        original = originals[card["message_id"]]
                        # A compaction clone has a new row ID. Only attach a
                        # card when Hermes confirms the exact same generation
                        # identity, and preserve the ORIGINAL row/call anchor.
                        if len(database._dedupe_display_generations([original, raw])) == 1:
                            cards[card["tool_call_id"]] = card
                projected = row if cards else project_compaction_message_for_display(row)
                if projected is not None:
                    rows.append((projected, cards))
        messages = []
        for row, cards in rows:
            role = row.get("role")
            if role not in {"user", "assistant", "system"}:
                continue
            if row.get("display_kind") == "hidden" and not cards:
                continue
            content = _plain_content(row.get("content"))
            thinking = row.get("reasoning") or row.get("reasoning_content") or ""
            if not content.strip() and not thinking and not cards:
                continue
            message = {"role": role, "content": content, "thinking": thinking,
                       "created_at": _date(row.get("timestamp")),
                       "source_message_id": row["id"],
                       "source_tool_call_ids": [call["id"] for call in _calls(row) if call.get("id")]}
            if cards:
                # Several calls can share one assistant row. Give each call a
                # separate card with the same row ID, retaining prose only once.
                for call in _calls(row):
                    card = cards.get(call.get("id"))
                    if card:
                        messages.append({**message, "source_message_id": card["message_id"], "notification": card})
                        message = {**message, "content": "", "thinking": ""}
            else:
                messages.append(message)
        return {"notification": notification,
                "session": {"id": sid, "title": session.get("title") or notification["task_name"],
                            "model": session.get("model") or "",
                            "created_at": _date(session.get("started_at")),
                            "updated_at": _date(updated_at) if updated_at else ""},
                "messages": messages, "source_session_id": sid,
                "continuation_session_id": continuation,
                "model": continued_session.get("model") or ""}


class Notifications:
    def __init__(self, home, sources=None):
        self.home = Path(home)
        self.path = self.home / "talaria-notifications.sqlite3"
        self.sources = sources or HermesSources(home)
        self.ready = threading.Event()

    def prepare(self, description):
        with _setup_lock:
            try:
                setup(self.home, description)
                self.ready.set()
            except Exception:
                self.ready.clear()
                raise

    @contextlib.contextmanager
    def transaction(self):
        self.home.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(self.path, timeout=5, isolation_level=None)
        connection.row_factory = sqlite3.Row
        try:
            connection.execute("PRAGMA busy_timeout=5000")
            try:
                from hermes_state_wal import apply_wal_with_fallback
            except ImportError:
                # Standalone store tests use SQLite's rollback journal. Hermes
                # supplies the shared-filesystem-aware policy in production.
                pass
            else:
                apply_wal_with_fallback(connection, db_label="talaria-notifications.sqlite3")
            connection.execute("PRAGMA synchronous=FULL")
            connection.execute("BEGIN IMMEDIATE")
            connection.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            connection.execute("INSERT OR IGNORE INTO meta VALUES ('generation', ?)", (uuid.uuid4().hex,))
            connection.execute("INSERT OR IGNORE INTO meta VALUES ('sequence', '0')")
            connection.execute("""CREATE TABLE IF NOT EXISTS findings (
                id TEXT PRIMARY KEY, task_id TEXT NOT NULL, finding_key TEXT NOT NULL,
                version INTEGER NOT NULL, change_seq INTEGER NOT NULL, payload TEXT NOT NULL,
                last_run_order REAL NOT NULL, last_run_id TEXT NOT NULL, last_message_id INTEGER NOT NULL,
                UNIQUE(task_id, finding_key))""")
            connection.execute("CREATE INDEX IF NOT EXISTS findings_changes ON findings(change_seq)")
            connection.execute("""CREATE TABLE IF NOT EXISTS versions (
                id TEXT NOT NULL, version INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(id, version))""")
            connection.execute("CREATE INDEX IF NOT EXISTS version_sources ON versions(json_extract(payload,'$.session_id'),json_extract(payload,'$.message_id'))")
            connection.execute("""CREATE TABLE IF NOT EXISTS receipts (
                session_id TEXT NOT NULL, tool_call_id TEXT NOT NULL, result TEXT NOT NULL,
                PRIMARY KEY(session_id, tool_call_id))""")
            yield connection
            connection.execute("COMMIT")
        except BaseException:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            raise
        finally:
            connection.close()

    @staticmethod
    def next_sequence(connection):
        connection.execute("UPDATE meta SET value=CAST(value AS INTEGER)+1 WHERE key='sequence'")
        return int(connection.execute("SELECT value FROM meta WHERE key='sequence'").fetchone()[0])

    def create(self, args, *, task_id, session_id, tool_call_id):
        args = _arguments(args)
        source = self.sources.verify(task_id, session_id, tool_call_id, args)
        with self.transaction() as connection:
            receipt = connection.execute("SELECT result FROM receipts WHERE session_id=? AND tool_call_id=?",
                                         (session_id, tool_call_id)).fetchone()
            if receipt:
                return json.loads(receipt[0])
            if source.get("execution_status") != "running":
                raise ValueError("This automation execution is no longer running.")
            row = connection.execute("SELECT * FROM findings WHERE task_id=? AND finding_key=?",
                                     (source["task_id"], args["finding_key"])).fetchone()
            old = json.loads(row["payload"]) if row else None
            incoming_order = (source["run_order"], source["run_id"], source["message_id"])
            previous_order = (row["last_run_order"], row["last_run_id"], row["last_message_id"]) if row else None
            stale = previous_order is not None and incoming_order < previous_order
            changed = old is None or args["change_key"] != old["change_key"] or URGENCIES[args["urgency"]] > URGENCIES[old["urgency"]]
            if stale or not changed:
                result = {"status": "stale" if stale else "unchanged", "notification": old}
                if not stale:
                    # Watermark advances without changing notification content,
                    # read state, source anchor, sort position or sync sequence.
                    connection.execute("UPDATE findings SET last_run_order=?, last_run_id=?, last_message_id=? WHERE id=?",
                                       (*incoming_order, old["id"]))
            else:
                now = datetime.now(timezone.utc).isoformat()
                notification = {key: value for key, value in source.items()
                                if key not in {"run_order", "execution_status"}}
                notification.update(args)
                notification.update(id=old["id"] if old else uuid.uuid4().hex,
                                    version=old["version"] + 1 if old else 1, is_read=False,
                                    created_at=old["created_at"] if old else now, updated_at=now,
                                    change_seq=self.next_sequence(connection))
                payload = json.dumps(notification, ensure_ascii=False)
                connection.execute("""INSERT INTO findings VALUES (?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(task_id,finding_key) DO UPDATE SET version=excluded.version,
                    change_seq=excluded.change_seq,payload=excluded.payload,last_run_order=excluded.last_run_order,
                    last_run_id=excluded.last_run_id,last_message_id=excluded.last_message_id""",
                    (notification["id"], notification["task_id"], args["finding_key"], notification["version"],
                     notification["change_seq"], payload, *incoming_order))
                connection.execute("INSERT INTO versions VALUES (?,?,?)",
                                   (notification["id"], notification["version"], payload))
                result = {"status": "updated" if old else "created", "notification": notification}
            connection.execute("INSERT INTO receipts VALUES (?,?,?)",
                               (session_id, tool_call_id, json.dumps(result, ensure_ascii=False)))
        return result

    def sync(self, params):
        requested_generation = params.get("generation", "")
        if not isinstance(requested_generation, str):
            raise ValueError("generation must be text.")
        cursor = _integer(params.get("cursor", 0), "cursor")
        limit = _integer(params.get("limit", 200), "limit", 1)
        if limit > 1000:
            raise ValueError("limit must not exceed 1000.")
        with self.transaction() as connection:
            generation = connection.execute("SELECT value FROM meta WHERE key='generation'").fetchone()[0]
            latest = int(connection.execute("SELECT value FROM meta WHERE key='sequence'").fetchone()[0])
            reset = requested_generation != generation or cursor > latest
            if reset:
                cursor = 0
            rows = connection.execute("SELECT payload FROM findings WHERE change_seq>? ORDER BY change_seq LIMIT ?",
                                      (cursor, limit + 1)).fetchall()
            notifications = [json.loads(row[0]) for row in rows[:limit]]
            has_more = len(rows) > limit
            return {"generation": generation, "cursor": notifications[-1]["change_seq"] if has_more else latest,
                    "has_more": has_more, "reset": reset, "notifications": notifications}

    def set_read(self, params):
        identifier = _text(params.get("id"), "id", 128)
        version = _integer(params.get("version"), "version", 1)
        if not isinstance(params.get("read"), bool):
            raise ValueError("read must be a boolean.")
        with self.transaction() as connection:
            row = connection.execute("SELECT payload FROM findings WHERE id=?", (identifier,)).fetchone()
            if not row:
                raise ValueError("Notification not found.")
            notification = json.loads(row[0])
            if notification["version"] == version and notification["is_read"] != params["read"]:
                notification["is_read"] = params["read"]
                notification["change_seq"] = self.next_sequence(connection)
                connection.execute("UPDATE findings SET payload=?, change_seq=? WHERE id=?",
                                   (json.dumps(notification, ensure_ascii=False), notification["change_seq"], identifier))
            return notification

    def open_source(self, params):
        identifier = _text(params.get("id"), "id", 128)
        version = _integer(params.get("version"), "version", 1)
        with self.transaction() as connection:
            row = connection.execute("SELECT payload FROM versions WHERE id=? AND version=?", (identifier, version)).fetchone()
            if not row:
                raise ValueError("This notification version is no longer available.")
            notification = json.loads(row[0])
            current = connection.execute("SELECT payload FROM findings WHERE id=? AND version=?", (identifier, version)).fetchone()
            if current:
                notification = json.loads(current[0])
        return self.sources.open(notification, related_notifications=self.source_notifications)

    def source_notifications(self, session_ids):
        with self.transaction() as connection:
            return [json.loads(item[0]) for sid in session_ids for item in connection.execute(
                "SELECT payload FROM versions WHERE json_extract(payload,'$.session_id')=?", (sid,))]


def create_notification(args, *, task_id=None, session_id=None, **_kwargs):
    from hermes_constants import get_hermes_home
    # Hermes currently exposes these as private ContextVars. Keep this version
    # dependency in one adapter, capability checked during setup; never fall back
    # to process environment variables shared by concurrent jobs.
    from tools.approval_context import _approval_tool_call_id, _approval_session_id
    if not session_id or _approval_session_id.get() != session_id:
        raise ValueError("Hermes did not provide a trusted notification session.")
    call_id = _approval_tool_call_id.get()
    if not call_id:
        raise ValueError("Hermes did not provide a trusted notification tool call.")
    result = Notifications(get_hermes_home()).create(args, task_id=task_id, session_id=session_id, tool_call_id=call_id)
    return json.dumps(result, ensure_ascii=False)


def _cron_toolsets(tool_name, args, **_kwargs):
    if tool_name == "cronjob" and isinstance(args, dict) and args.get("action") in {"create", "update"}:
        selected = args.get("enabled_toolsets")
        if isinstance(selected, list) and selected and TOOLSET not in selected:
            return {"action": "modify", "args": {"enabled_toolsets": [*selected, TOOLSET]}}
    return None


def register(ctx):
    """Native Hermes plugin entry, discovered in gateway and detached workers."""
    from hermes_constants import get_hermes_home
    description = (get_hermes_home() / DESCRIPTION_FILE).read_text(encoding="utf-8")
    schema = {"name": TOOL, "description": description,
              "parameters": {"type": "object", "additionalProperties": False,
                             "properties": {key: {"type": "string", "minLength": 1, "maxLength": limit}
                                            for key, limit in FIELDS.items()},
                             "required": [*FIELDS, "urgency"]}}
    schema["parameters"]["properties"]["urgency"] = {"type": "string", "enum": list(URGENCIES)}
    ctx.register_tool(name=TOOL, toolset=TOOLSET, schema=schema, handler=create_notification,
                      description="Talaria notifications", emoji="🔔")
    ctx.register_hook("pre_tool_call", _cron_toolsets)


def _atomic_write(path, text):
    if path.exists() and path.read_text(encoding="utf-8") == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(text)
            stream.close()
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    return True


def setup(home, description):
    """Reconcile the packaged plugin through Hermes-owned profile APIs."""
    description = _text(description, "notification_tool_description", 16000)
    from hermes_cli import config
    from hermes_cli.plugins import discover_plugins, get_plugin_manager, PluginContext
    from tools.approval_context import _approval_tool_call_id, _approval_session_id
    from tools.registry import registry
    from cron.jobs import list_jobs
    from tools.cronjob_tools import cronjob
    from hermes_state import SessionDB
    from agent.compaction_display import project_compaction_message_for_display
    if not all(hasattr(SessionDB, name) for name in ("get_messages", "get_messages_around", "resolve_resume_session_id",
            "_resume_lineage_ids", "_fetch_conversation_rows", "_dedupe_display_generations", "_row_to_message_dict")) or \
            not hasattr(PluginContext, "register_tool") or not hasattr(_approval_tool_call_id, "get") or \
            not hasattr(_approval_session_id, "get") or "enabled_toolsets" not in inspect.signature(cronjob).parameters or \
            "after_id" not in inspect.signature(SessionDB.get_messages).parameters:
        raise RuntimeError("This Hermes version does not support Talaria notifications. Update Hermes and retry.")
    home = Path(home)
    with _setup_lock:
        if config.is_managed():
            raise RuntimeError("This Hermes profile is managed; Talaria notifications cannot be configured.")
        changed = _atomic_write(home / DESCRIPTION_FILE, description)
        directory = home / "plugins" / PLUGIN
        changed = _atomic_write(directory / "__init__.py", Path(__file__).read_text(encoding="utf-8")) or changed
        changed = _atomic_write(directory / "plugin.yaml",
                                'name: talaria-notifications\nversion: "1.0.0"\ndescription: "Talaria notifications"\nhooks:\n  - pre_tool_call\n') or changed
        raw = config.read_raw_config() or {}
        plugins = dict(raw.get("plugins") or {})
        enabled = plugins.get("enabled", [])
        disabled = plugins.get("disabled", [])
        if not isinstance(enabled, list) or not isinstance(disabled, list):
            raise ValueError("Hermes plugin settings must contain lists of plugin names.")
        # Installation is automatic, activation remains the user's choice.
        # A disabled notification plugin must not disable the scheduler itself.
        if PLUGIN in disabled:
            return
        updates = {}
        if PLUGIN not in enabled:
            plugins.update(enabled=list(dict.fromkeys([*enabled, PLUGIN])), disabled=[name for name in disabled if name != PLUGIN])
            updates["plugins"] = plugins
        platforms = dict(raw.get("platform_toolsets") or {})
        if isinstance(platforms.get("cron"), list) and TOOLSET not in platforms["cron"]:
            platforms["cron"] = [*platforms["cron"], TOOLSET]
            updates["platform_toolsets"] = platforms
        disabled_tools = (raw.get("agent") or {}).get("disabled_toolsets") or []
        if TOOLSET in disabled_tools:
            raise ValueError("Talaria notifications are disabled in Hermes agent toolset settings.")
        if updates:
            config.save_config(updates, merge_existing=True)
            changed = True
        discover_plugins(force=changed)
        entry = registry.get_entry(TOOL)
        if not entry and not changed:
            previous = next((item for item in get_plugin_manager().list_plugins() if item["key"] == PLUGIN), {})
            if previous.get("error") == "disabled via config":
                # Enabled again in Settings, but this gateway began with the
                # plugin disabled. New cron workers load the saved setting;
                # keep the scheduler available while this session awaits restart.
                return
        if not entry or entry.toolset != TOOLSET:
            raise RuntimeError("Hermes could not load the Talaria notification tool.")
        # Explicit job lists override platform defaults. Reconcile them through
        # cronjob, preserving every existing toolset and all unrelated fields.
        for job in list_jobs(include_disabled=True):
            selected = job.get("enabled_toolsets")
            if isinstance(selected, list) and selected and TOOLSET not in selected and not job.get("no_agent"):
                result = json.loads(cronjob(action="update", job_id=job["id"], enabled_toolsets=[*selected, TOOLSET]))
                if not result.get("success"):
                    raise RuntimeError(result.get("error") or "Could not enable notifications for an automation.")


def register_rpc(server, home):
    service = Notifications(home)
    methods = {"sync": service.sync, "set_read": service.set_read, "open_source": service.open_source}
    server._LONG_HANDLERS = server._LONG_HANDLERS | {"talaria.notifications." + name for name in methods}
    for action, operation in methods.items():
        def handler(request_id, params, action=action, operation=operation):
            try:
                if not isinstance(params, dict):
                    raise ValueError("Notification parameters must be an object.")
                if action == "sync" and "notification_tool_description" in params:
                    service.prepare(params["notification_tool_description"])
                result = operation(params)
                return server._ok(request_id, {"notification": result} if action == "set_read" else result)
            except Exception as exc:
                return server._err(request_id, -32000, f"Hermes notifications: {exc}")
        server.method("talaria.notifications." + action)(handler)
    return service
