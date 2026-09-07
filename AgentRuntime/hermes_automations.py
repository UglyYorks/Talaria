"""Scheduled-job extension hosted INSIDE Hermes's TUI gateway process.

The VM worker only sends JSON-RPC. Hermes owns validation, storage, execution,
delivery, scheduler locking and model calls. No job store is mirrored in Talaria.
"""
import inspect
import json
from pathlib import Path
import threading


METHOD = "talaria.automations"


class Automations:
    def __init__(self, home):
        self.home = Path(home)
        self.lock = threading.RLock()
        self.stop_event = threading.Event()
        self.thread = None
        self.scheduler_error = ""
        self.preference = self.home / "talaria-scheduler-enabled"

    def scheduler_status(self):
        from cron.jobs import get_ticker_last_error, get_ticker_heartbeat_age
        from gateway.status import is_gateway_runtime_lock_active
        from cron.scheduler_provider import resolve_cron_scheduler
        own = bool(self.thread and self.thread.is_alive() and not self.stop_event.is_set())
        external = bool(is_gateway_runtime_lock_active())
        return {"running": own or external, "owned": own, "external": external,
                "provider": resolve_cron_scheduler().name,
                "heartbeat_age": get_ticker_heartbeat_age(),
                "error": self.scheduler_error or get_ticker_last_error() or ""}

    def set_scheduler(self, enabled, persist=True):
        from cron.scheduler_provider import resolve_cron_scheduler
        with self.lock:
            if enabled:
                status = self.scheduler_status()
                if status["external"]:
                    raise ValueError("A Hermes gateway already owns scheduling. Manage that gateway separately.")
                scheduler = resolve_cron_scheduler()
                if scheduler.name != "builtin":
                    raise ValueError("This Hermes installation uses a managed scheduler. Manage it through its provider.")
                if self.thread and self.thread.is_alive():
                    if self.stop_event.is_set():
                        raise ValueError("The scheduler is still stopping. Retry shortly.")
                else:
                    self.stop_event = threading.Event()
                    self.scheduler_error = ""
                    def run():
                        try:
                            scheduler.start(self.stop_event, can_dispatch=lambda: not self.stop_event.is_set())
                        except BaseException as exc:
                            self.scheduler_error = str(exc)
                    self.thread = threading.Thread(target=run, daemon=True, name="talaria-hermes-cron")
                    self.thread.start()
                if persist:
                    self.preference.touch()
            else:
                self.stop_event.set()
                if persist:
                    self.preference.unlink(missing_ok=True)
        return {"scheduler": self.scheduler_status()}

    @staticmethod
    def fields():
        from tools.cronjob_tools import cronjob, CRONJOB_SCHEMA
        # Discover installed capabilities, including user-owned model overrides
        # deliberately omitted from the model-facing tool schema.
        properties = CRONJOB_SCHEMA["parameters"]["properties"]
        internal = {"action", "job_id", "include_disabled", "task_id", "session_id", "reason", "skill"}
        fields = []
        for name, parameter in inspect.signature(cronjob).parameters.items():
            if name in internal:
                continue
            annotation = str(parameter.annotation)
            kind = ("boolean" if "bool" in annotation else "integer" if "int" in annotation
                    else "array" if "List" in annotation and "str, List" not in annotation else "string")
            definition = dict(properties.get(name) or {})
            definition.update({"key": name, "type": definition.get("type", kind)})
            fields.append(definition)
        return fields

    @staticmethod
    def jobs():
        from cron.jobs import list_jobs
        from tools.cronjob_tools import _format_job
        result = []
        for job in list_jobs(include_disabled=True):
            formatted = _format_job(job)
            values = {**job, **formatted, "prompt": job.get("prompt", ""),
                      "repeat": (job.get("repeat") or {}).get("times")}
            # schedule_display is human text, not necessarily accepted input.
            schedule = job.get("schedule") or {}
            if schedule.get("kind") == "cron":
                values["schedule"] = schedule.get("expr", "")
            elif schedule.get("kind") == "interval":
                values["schedule"] = f"every {schedule.get('minutes', 0)}m"
            elif schedule.get("kind") == "once":
                values["schedule"] = schedule.get("run_at", "")
            else:
                values["schedule"] = job.get("schedule_display", "")
            result.append({**formatted, "values": values, "last_error": job.get("last_error"),
                           "last_output": job.get("last_output")})
        return result

    @staticmethod
    def require_job(job_id):
        from cron.jobs import get_job
        if not isinstance(job_id, str) or not job_id or not get_job(job_id):
            raise ValueError("This automation no longer exists. Refresh the list.")

    def handle(self, params):
        action = params.get("action")
        if action == "list":
            return {"jobs": self.jobs(), "fields": self.fields(), "scheduler": self.scheduler_status()}
        if action == "scheduler":
            if not isinstance(params.get("enabled"), bool):
                raise ValueError("Scheduler enabled must be a boolean.")
            return self.set_scheduler(params["enabled"])
        if action in {"create", "update", "pause", "resume", "run", "remove"}:
            from tools.cronjob_tools import cronjob
            values = params.get("values", {})
            if not isinstance(values, dict):
                raise ValueError("Automation fields must be an object.")
            allowed = {field["key"] for field in self.fields()}
            if set(values) - allowed:
                raise ValueError("This Hermes version does not support: " + ", ".join(sorted(set(values) - allowed)))
            if action != "create":
                self.require_job(params.get("job_id"))
            result = json.loads(cronjob(action=action, job_id=params.get("job_id"), **values))
            if not isinstance(result, dict) or not result.get("success"):
                raise ValueError(result.get("error", "Hermes could not complete the operation."))
            return result
        if action == "runs":
            from cron.executions import list_executions
            self.require_job(params.get("job_id"))
            directory = self.output_directory(params["job_id"])
            return {"runs": list_executions(job_id=params["job_id"], limit=100),
                    "outputs": [{"name": path.name} for path in sorted(directory.glob("*.md"), reverse=True)[:100]
                                if not path.is_symlink()]}
        if action == "output":
            self.require_job(params.get("job_id"))
            directory = self.output_directory(params["job_id"])
            name = params.get("name")
            if not isinstance(name, str) or Path(name).name != name or not name.endswith(".md"):
                raise ValueError("Invalid output filename.")
            path = directory / name
            if path.is_symlink() or path.resolve().parent != directory:
                raise ValueError("Invalid output path.")
            # Bound transport/UI memory without silently truncating output.
            if path.stat().st_size > 2 * 1024 * 1024:
                raise ValueError("This output exceeds the 2 MB viewer limit. Open it in the VM terminal.")
            return {"text": path.read_text(encoding="utf-8")}
        if action == "notes":
            from cron import notepad
            self.require_job(params.get("job_id"))
            operation = params.get("operation", "list")
            if operation == "set":
                notepad.set_note(params["job_id"], params["key"], params["value"])
            elif operation == "delete":
                notepad.delete_note(params["job_id"], params["key"])
            elif operation != "list":
                raise ValueError("Unknown notepad operation.")
            return {"notes": notepad.list_notes(params["job_id"])}
        if action == "incidents":
            from cron.incidents import list_incidents, ack_incident
            if params.get("incident_id") and not ack_incident(params["incident_id"]):
                raise ValueError("Incident not found.")
            return {"incidents": list_incidents()}
        if action == "doctor":
            from cron.jobs import list_jobs
            from hermes_cli.cron import _cron_doctor_issues_for_job
            return {"issues": [{"job_id": job["id"], "name": job.get("name"),
                                "issues": _cron_doctor_issues_for_job(job)}
                               for job in list_jobs(include_disabled=True)],
                    "scheduler": self.scheduler_status()}
        raise ValueError("Unknown automation action.")

    @staticmethod
    def output_directory(job_id):
        from cron.jobs import get_cron_output_dir
        root = get_cron_output_dir().resolve()
        directory = (root / job_id).resolve()
        if directory.parent != root:
            raise ValueError("Invalid automation output directory.")
        return directory


def register(server, home):
    automations = Automations(home)
    # Hermes's pool keeps slow disk operations and manual runs off the RPC reader.
    server._LONG_HANDLERS = server._LONG_HANDLERS | {METHOD}
    @server.method(METHOD)
    def handle(request_id, params):
        try:
            return server._ok(request_id, automations.handle(params))
        except Exception as exc:
            return server._err(request_id, -32000, f"Hermes automations: {exc}")
    if automations.preference.exists():
        try:
            automations.set_scheduler(True, persist=False)
        except Exception as exc:
            automations.scheduler_error = str(exc)
    return automations
