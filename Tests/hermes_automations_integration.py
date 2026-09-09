"""Optional real-Hermes integration: python this_file.py /path/to/hermes-agent.

Use a Python environment with Hermes dependencies installed. All jobs, outputs,
notes and scheduler state live in a temporary home. Only a local Python script
is executed; no provider requests or delivery messages are made.
"""
from datetime import datetime, timedelta, timezone
import os
from pathlib import Path
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "AgentRuntime"))
from hermes_gateway import HermesGateway


def main():
    source = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="talaria-automations-integration-") as temporary:
        home = Path(temporary)
        (home / "scripts").mkdir()
        (home / "scripts/probe.py").write_text("print('Talaria scheduled output verified')\n")
        environment = {**os.environ, "HERMES_HOME": str(home), "PYTHONPATH": str(source),
                       "HERMES_DISABLE_MCP": "1"}
        gateway = HermesGateway(sys.executable, environment, home)
        def call(action, **params):
            return gateway.call("talaria.automations", {"action": action, **params}, timeout=45)
        try:
            # Settings credentials and scheduled jobs share the production entry point.
            credentials = gateway.call("talaria.credentials.list")
            assert isinstance(credentials["entries"], list)
            assert all("value" not in item for item in credentials["entries"])
            gateway.call("talaria.notifications.sync", {
                "notification_tool_description": "Native TLPromptBuilder notification policy fixture."})
            initial = call("list")
            assert initial["jobs"] == []
            assert {"script", "no_agent", "model", "context_from"} <= {field["key"] for field in initial["fields"]}
            created = call("create", values={"name": "Talaria integration probe", "schedule": "every 2h",
                "script": "probe.py", "no_agent": True, "deliver": "local"})
            job_id = created["job_id"]
            job = call("list")["jobs"][0]
            assert job["values"]["schedule"] == "every 120m"
            call("update", job_id=job_id, values={"name": "Renamed probe", "continuity": True})
            assert call("list")["jobs"][0]["name"] == "Renamed probe"
            call("pause", job_id=job_id)
            assert not call("list")["jobs"][0]["enabled"]
            call("resume", job_id=job_id)
            assert call("list")["jobs"][0]["enabled"]
            call("notes", job_id=job_id, operation="set", key="tested", value="yes")
            assert call("notes", job_id=job_id)["notes"][0]["value"] == "yes"
            call("notes", job_id=job_id, operation="delete", key="tested")
            assert call("notes", job_id=job_id)["notes"] == []
            executed = call("run", job_id=job_id)
            assert executed["success"], executed
            runs = call("runs", job_id=job_id)
            assert runs["runs"][0]["status"] == "completed", runs
            assert "Talaria scheduled output verified" in call("output", job_id=job_id, name=runs["outputs"][0]["name"])["text"]
            call("doctor")
            call("incidents")
            # Make the same real job due, then let Hermes's own scheduler fire it.
            schedule = (datetime.now(timezone.utc) + timedelta(seconds=1)).isoformat()
            call("update", job_id=job_id, values={"schedule": schedule, "repeat": 2})
            time.sleep(1.2)
            call("scheduler", enabled=True)
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                runs = call("runs", job_id=job_id)["runs"]
                if len(runs) >= 2 and runs[0]["status"] == "completed":
                    break
                time.sleep(0.2)
            else:
                raise AssertionError(f"Hermes scheduler did not execute the due job: {runs}")
            call("scheduler", enabled=False)
            assert not call("list")["scheduler"]["owned"]
            call("remove", job_id=job_id)
            assert call("list")["jobs"] == []
            print("Real Hermes TUI integration passed: create/edit/pause/resume, manual run, scheduled execution, outputs, notes, diagnostics, incidents, delete.")
        finally:
            gateway.process.terminate()
            try:
                gateway.process.wait(timeout=10)
            except Exception:
                gateway.process.kill()
                gateway.process.wait()
            if gateway.process.returncode not in (0, -15):
                log = home / "talaria-tui-gateway.log"
                print(log.read_text()[-3000:] if log.exists() else "No gateway log", file=sys.stderr)


if __name__ == "__main__":
    main()
