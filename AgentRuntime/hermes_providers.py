"""Provider setup inside Hermes's stdio gateway. Hermes owns catalogs and auth."""
import asyncio
import os
import subprocess
import sys
import threading
import uuid

_logins = {}
_lock = threading.RLock()


def auth_helpers():
    try:
        from hermes_cli.web_routers import oauth
        return oauth
    except ImportError:
        from hermes_cli import web_server
        return web_server


def endpoint_helpers():
    try:
        from hermes_cli.web_routers import config_env
        return config_env
    except ImportError:
        from hermes_cli import web_server
        return web_server


def descriptors():
    from dataclasses import asdict
    from hermes_cli.provider_catalog import provider_catalog
    rows = [asdict(row) for row in provider_catalog()]
    metadata = endpoint_helpers()._catalog_provider_env_metadata()
    for row in rows:
        fields = {key: info for key, info in metadata.items() if info.get("provider") == row["slug"]}
        row["credential_fields"] = fields
        row["api_key_env_vars"] = list(dict.fromkeys([*row["api_key_env_vars"], *fields]))
    return rows


def provider_action(params):
    from hermes_cli import config
    action = params.get("action")
    if action == "describe":
        rows = descriptors()
        for row in rows:
            if row["slug"] == "custom":
                row["custom_fields"] = ["name", "base_url", "api_key"]
        return {"providers": rows}
    slug = params.get("slug", "")
    descriptor = next((row for row in descriptors() if row["slug"] == slug), None)
    if descriptor is None:
        raise ValueError("Unknown Hermes provider. Refresh the provider list.")
    if config.is_managed():
        raise ValueError("Provider setup is managed by your administrator.")
    if action == "custom.configure":
        from hermes_cli.web_models import CustomEndpointUpdate
        values = params.get("values", {})
        if slug != "custom" or not isinstance(values, dict) or set(values) - {"name", "base_url", "api_key"}:
            raise ValueError("Invalid custom endpoint fields.")
        body = CustomEndpointUpdate(**values, model=params.get("model", ""), make_default=False)
        cfg = config.load_config()
        endpoint_id, _ = endpoint_helpers()._write_custom_endpoint(cfg, body)
        config.save_config(cfg)
        return {"slug": endpoint_id}
    if action == "configure":
        from hermes_cli.credential_lifecycle import save_provider_env_credential
        from hermes_cli import managed_scope
        values = params.get("values", {})
        allowed = set(descriptor["api_key_env_vars"])
        if descriptor["base_url_env_var"]:
            allowed.add(descriptor["base_url_env_var"])
        if not isinstance(values, dict) or set(values) - allowed:
            raise ValueError("Use the fields supplied by Hermes for this provider.")
        for key, value in values.items():
            if not isinstance(value, str) or not value.strip() or any(c in value for c in "\n\r\x00"):
                raise ValueError("Credential values must be nonempty single lines.")
            if managed_scope.is_env_managed(key):
                raise ValueError("This credential is managed by your administrator.")
            config.validate_env_var_name_for_write(key)
        for key, value in values.items():
            save_provider_env_credential(key, value.strip())
            os.environ[key] = value.strip()
        return {"ok": True}
    if action.startswith("login."):
        return login_action(action, slug, params)
    raise ValueError("Unsupported provider setup action.")


def login_action(action, slug, params):
    # Reuse Hermes's login implementation without starting or calling an HTTP
    # server. Device code polling, exchange, storage and cancellation stay there.
    auth = auth_helpers()
    catalog = {row["id"]: row for row in auth._build_oauth_catalog()}
    entry = catalog.get(slug)
    if action == "login.start":
        if entry and entry["flow"] == "device_code":
            result = asyncio.run(auth._start_device_code_flow(slug))
            with _lock:
                _logins[result["session_id"]] = {"slug": slug, "device": True}
            return result
        # External/account/plugin flows use the installed Hermes auth command,
        # reached over this RPC, with a PTY so its native prompts still work.
        import pty
        import termios
        master, slave = pty.openpty()
        attrs = termios.tcgetattr(slave)
        attrs[3] &= ~termios.ECHO
        attrs[3] &= ~termios.ECHONL
        termios.tcsetattr(slave, termios.TCSANOW, attrs)
        environment = dict(os.environ, TERM="dumb")
        try:
            process = subprocess.Popen([sys.executable, "-m", "hermes_provider_login", slug],
                                       stdin=slave, stdout=slave, stderr=slave, start_new_session=True, env=environment)
        finally:
            os.close(slave)
        sid = uuid.uuid4().hex
        state = {"slug": slug, "process": process, "fd": master, "text": "", "device": False}
        with _lock:
            _logins[sid] = state
        def read():
            try:
                while True:
                    data = os.read(master, 4096)
                    if not data:
                        break
                    with _lock:
                        state["text"] = (state["text"] + data.decode(errors="replace"))[-32000:]
            except OSError:
                pass
            finally:
                os.close(master)
        threading.Thread(target=read, daemon=True).start()
        return {"session_id": sid, "flow": "interactive", "poll_interval": 1}
    sid = params.get("session_id", "")
    with _lock:
        state = _logins.get(sid)
        if not state or state["slug"] != slug:
            raise ValueError("Login expired. Start again.")
        if action == "login.cancel":
            if state["device"]:
                with auth._oauth_sessions_lock:
                    session = auth._oauth_sessions.pop(sid, None)
                    if session:
                        session["cancelled"] = True
            elif state["process"].poll() is None:
                import signal
                os.killpg(state["process"].pid, signal.SIGTERM)
            _logins.pop(sid, None)
            return {"ok": True}
        if state["device"]:
            if action != "login.poll":
                raise ValueError("Complete login in your browser.")
            result = asyncio.run(auth.poll_oauth_session(slug, sid))
            # Do not return upstream exception text, which may contain secrets.
            if result.get("status") == "error":
                result["error_message"] = "Login failed. Start again."
            return result
        if action == "login.input":
            value = params.get("input", "")
            if not isinstance(value, str) or any(c in value for c in "\r\n\x00"):
                raise ValueError("Enter a single line.")
            if state["process"].poll() is not None:
                raise ValueError("Login has ended. Start again.")
            os.write(state["fd"], (value + "\n").encode())
        elif action != "login.poll":
            raise ValueError("Unsupported login action.")
        code = state["process"].poll()
        text, state["text"] = state["text"], ""
        return {"session_id": sid, "status": "pending" if code is None else "approved" if code == 0 else "error",
                "text": text}


def register(server):
    @server.method("talaria.providers")
    def handle(rid, params):
        try:
            with _lock:
                result = provider_action(params)
            return server._ok(rid, result)
        except (ImportError, AttributeError):
            return server._err(rid, -32601, "Update Hermes to use provider setup and account login.")
        except Exception:
            return server._err(rid, -32602, "Provider setup failed. Check your entries, installation and managed settings, then retry.")

    @server.method("talaria.session.ready")
    def ready(rid, params):
        session = server._sessions.get(params.get("session_id", ""))
        if session is None:
            return server._err(rid, 4007, "Hermes session not found.")
        server._start_agent_build(params["session_id"], session)
        failure = server._wait_agent(session, rid)
        return failure or server._ok(rid, {"ready": True})

    @server.method("talaria.session.verify_model")
    def verify_model(rid, params):
        try:
            session = server._sessions.get(params.get("session_id", ""))
            agent = session.get("agent") if session else None
            if agent is None:
                return server._err(rid, 5032, "Hermes model is not ready.")
            runtime = server._runtime_model_config(agent)
            requested = params.get("provider", "")
            actual = runtime.get("provider")
            # Hermes collapses named endpoint clients to billing class "custom";
            # compare durable identities resolved by Hermes, never just that class.
            if actual != requested:
                from hermes_cli.runtime_provider import canonical_custom_identity
                requested = canonical_custom_identity(config_provider=requested) or requested
            return server._ok(rid, {"verified": runtime.get("model") == params.get("model") and actual == requested})
        except (ImportError, AttributeError):
            return server._err(rid, -32601, "Update Hermes to verify provider model selection.")
