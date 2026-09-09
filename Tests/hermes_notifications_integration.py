"""Real-Hermes, disposable-profile check without model calls or deliveries.

Run with a Hermes dependency environment:
  python Tests/hermes_notifications_integration.py /path/to/hermes-agent
The child probe imports ONLY the installed profile plugin, proving detached
worker discovery does not depend on Talaria's gateway module path.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def probe(home, source):
    os.environ.update(HERMES_HOME=str(home), HERMES_DISABLE_MCP="1")
    sys.path.insert(0, str(source))
    from hermes_cli.plugins import discover_plugins
    from tools.registry import registry
    from cron.jobs import list_jobs
    from cron.executions import create_execution, mark_execution_running
    from hermes_state import SessionDB
    discover_plugins()
    entry = registry.get_entry("create_notification")
    assert entry is not None, "Detached process did not discover installed plugin"
    job = list_jobs(include_disabled=True)[0]
    assert "talaria_notifications" in job["enabled_toolsets"], job
    from cron.scheduler import _resolve_cron_enabled_toolsets, _resolve_cron_disabled_toolsets
    from hermes_cli.config import load_config
    import model_tools
    cfg = load_config()
    enabled = _resolve_cron_enabled_toolsets(job, cfg)
    disabled = _resolve_cron_disabled_toolsets(cfg)
    tool_defs = model_tools.get_tool_definitions(enabled_toolsets=enabled, disabled_toolsets=disabled,
                                                quiet_mode=True, skip_tool_search_assembly=True)
    assert "create_notification" in {tool["function"]["name"] for tool in tool_defs}, tool_defs
    execution = create_execution(job["id"], source="integration")
    mark_execution_running(execution["id"])
    database = SessionDB(home / "state.db")
    sid = "talaria-notification-integration"
    database.create_session(sid, source="cron", model="test/no-inference")
    args = {"title": "Payment pending", "summary": "Invoice 123 is due tomorrow.", "urgency": "medium",
            "finding_key": "gmail:account-1:message-123:payment", "change_key": "unpaid:50:2026-09-10"}
    database.append_message(sid, "user", "Check for useful findings")
    bridge_args = {"name": "create_notification", "arguments": args}
    row_id = database.append_message(sid, "assistant", "", tool_calls=[{
        "id": "call-integration", "type": "function", "function": {
            "name": "tool_call", "arguments": json.dumps(bridge_args)}}])
    try:
        result = model_tools.handle_function_call("tool_call", bridge_args,
                                   task_id=f"cron:{job['id']}:{execution['id']}", session_id=sid,
                                   tool_call_id="call-integration", enabled_toolsets=enabled, disabled_toolsets=disabled)
        result = json.loads(result) if isinstance(result, str) else result
        assert result.get("status") == "created", result
        note = result["notification"]
        assert note["message_id"] == row_id, (row_id, note)
        retry = model_tools.handle_function_call("tool_call", bridge_args,
                                  task_id=f"cron:{job['id']}:{execution['id']}", session_id=sid,
                                  tool_call_id="call-integration", enabled_toolsets=enabled, disabled_toolsets=disabled)
        retry = json.loads(retry) if isinstance(retry, str) else retry
        assert retry == result, (retry, result)
        # Real Hermes compression creates new row IDs for inherited history.
        # Keep both generations and repeated genuine requests while recovering
        # the immutable notification anchor in the original source segment.
        for number, parent in ((1, sid), (2, sid + "-continuation-1")):
            child = sid + f"-continuation-{number}"
            holder = f"integration-compression-{number}"
            assert database.try_acquire_compression_lock(parent, holder)
            inherited = database.get_messages(parent, include_inactive=True)
            database.publish_compression_child(
                parent_session_id=parent, child_session_id=child, source="cron",
                model=f"test/continuation-{number}", compression_lock_holder=holder,
                messages=[{"role": "user", "content": "[CONTEXT SUMMARY]: fixture handoff", "_compressed_summary": True},
                          *inherited])
            database.release_compression_lock(parent, holder)
            database.append_message(child, "user", "Check again", timestamp=1800000000 + number)
            database.append_message(child, "assistant", f"Completed follow-up {number}", timestamp=1800000010 + number)
        database.create_session(sid + "-branch", source="cli", parent_session_id=child,
                                model_config={"_branched_from": child})
        database.append_message(sid + "-branch", "user", "Unrelated branch must stay separate")
    finally:
        database.close()
    # Import the registry handler's own plugin module; no AgentRuntime path.
    plugin = sys.modules[entry.handler.__module__]
    service = plugin.Notifications(home)
    synced = service.sync({})
    assert len(synced["notifications"]) == 1, synced
    opened = service.open_source({"id": note["id"], "version": 1})
    assert opened["source_session_id"] == sid, opened
    assert opened["continuation_session_id"] == sid + "-continuation-2", opened
    assert opened["model"] == "test/continuation-2", opened
    assert [message["content"] for message in opened["messages"]] == [
        "Check for useful findings", "", "Check again", "Completed follow-up 1", "Check again", "Completed follow-up 2"], opened
    assert opened["messages"][1]["notification"]["tool_call_id"] == "call-integration", opened
    assert opened["messages"][1]["source_message_id"] == row_id, opened
    service.set_read({"id": note["id"], "version": 1, "read": True})
    assert service.sync({})["notifications"][0]["is_read"]
    print("Detached plugin: trusted call, durable anchor, receipt retry, two compression generations, exact open, read state passed.")


def main():
    source = Path(sys.argv[1]).resolve()
    runtime = Path(__file__).resolve().parents[1] / "AgentRuntime"
    with tempfile.TemporaryDirectory(prefix="talaria-notifications-integration-") as temporary:
        home = Path(temporary)
        os.environ.update(HERMES_HOME=str(home), HERMES_DISABLE_MCP="1")
        sys.path[:0] = [str(source), str(runtime)]
        from hermes_cli import config
        # Give setup real lists to preserve, and a restrictive existing job.
        config.save_config({"platform_toolsets": {"cron": ["terminal"]}, "plugins": {"enabled": []}})
        from tools.cronjob_tools import cronjob
        created = json.loads(cronjob(action="create", name="Notification integration", schedule="every 2h",
                                    prompt="Integration fixture", deliver="local", enabled_toolsets=["terminal"]))
        assert created.get("success"), created
        from hermes_notifications import setup, TOOLSET
        setup(home, "Native TLPromptBuilder notification policy fixture.")
        setup(home, "Native TLPromptBuilder notification policy fixture.")
        stored = config.read_raw_config()
        assert stored["platform_toolsets"]["cron"] == ["terminal", TOOLSET], stored
        environment = {**os.environ, "PYTHONPATH": str(source)}
        subprocess.run([sys.executable, str(Path(__file__).resolve()), "--probe", str(home), str(source)],
                       env=environment, cwd=str(home), check=True, timeout=60)
        # Exercise production stdio RPC registration, including bootstrap setup
        # from the persisted native description and sync after process restart.
        from hermes_gateway import HermesGateway
        gateway = HermesGateway(sys.executable, environment, home)
        try:
            synced = gateway.call("talaria.notifications.sync", {})
            assert synced["notifications"][0]["is_read"], synced
            note = synced["notifications"][0]
            opened = gateway.call("talaria.notifications.open_source", {"id": note["id"], "version": 1})
            assert opened["source_session_id"] == note["session_id"], opened
            gateway.call("talaria.notifications.set_read", {"id": note["id"], "version": 1, "read": False})
            assert not gateway.call("talaria.notifications.sync", {})["notifications"][0]["is_read"]
        finally:
            gateway.process.terminate()
            gateway.process.wait(timeout=10)
        print("Real Hermes notification integration passed; no inference or deliveries.")


if __name__ == "__main__":
    if sys.argv[1] == "--probe":
        probe(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        main()
