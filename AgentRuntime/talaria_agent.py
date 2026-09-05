#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import threading
import tempfile
import time
import urllib.error
import urllib.request

from hermes_gateway import HermesGateway


HERMES_HOME = Path("/workspace/.hermes")
HERMES_INSTALL_DIR = HERMES_HOME / "hermes-agent"
_tui_token = None
_tui_gateway = None
_gateway_lock = threading.Lock()
_shell_directories = {}
_shell_lock = threading.Lock()


def trim(value):
    return value.strip() if isinstance(value, str) else ""


def emit(event, output=None):
    data = (json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    if output is None:
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
        return
    output.write(data)
    output.flush()


def error(message, output=None):
    emit({"type": "error", "message": message or "Agent worker failed."}, output)


def progress(request_id, text, output=None):
    emit({"type": "delta", "request_id": request_id, "kind": "thinking", "text": text}, output)


def hermes_executable():
    candidates = (
        HERMES_INSTALL_DIR / "venv/bin/hermes",
        Path("/workspace/.local/bin/hermes"),
        Path("/usr/local/bin/hermes"),
    )
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return ""


def hermes_environment(token="", model=""):
    environment = os.environ.copy()
    environment.update({
        "HOME": "/workspace",
        "HERMES_HOME": str(HERMES_HOME),
        "HERMES_INFERENCE_PROVIDER": "openrouter",
    })
    if trim(token):
        environment["OPENROUTER_API_KEY"] = trim(token)
    if trim(model):
        environment["HERMES_INFERENCE_MODEL"] = trim(model)
    return environment


def save_agent_soul(request):
    # A VM hosts one Hermes instance, so its soul belongs to that instance.
    if "soul" not in request:
        return
    soul = request["soul"]
    if not isinstance(soul, str):
        raise ValueError("Agent soul must be text.")
    HERMES_HOME.mkdir(parents=True, exist_ok=True)
    path = HERMES_HOME / "SOUL.md"
    if path.exists() and path.read_text(encoding="utf-8") == soul:
        return
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=HERMES_HOME,
                                     prefix=".SOUL-", delete=False) as file:
        temporary = Path(file.name)
        try:
            file.write(soul)
            file.close()
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


def install_hermes(request, output=None):
    request_id = trim(request.get("request_id")) or "install"
    if hermes_executable():
        try:
            save_agent_soul(request)
        except (OSError, ValueError) as exc:
            error(f"Could not save agent soul: {exc}", output)
            return
        progress(request_id, "Hermes Agent is already installed.\n", output)
        emit({"type": "complete"}, output)
        return

    HERMES_HOME.mkdir(parents=True, exist_ok=True)
    installer_path = Path("/tmp/hermes-install.sh")
    progress(request_id, "Downloading the official Hermes Agent installer…\n", output)
    installer_url = "https://hermes-agent.nousresearch.com/install.sh"
    try:
        installer_data = None
        last_download_error = None
        for attempt in range(1, 7):
            try:
                with urllib.request.urlopen(installer_url, timeout=60) as response:
                    installer_data = response.read()
                break
            except (OSError, urllib.error.URLError) as exc:
                last_download_error = exc
                if attempt < 6:
                    delay = min(5, attempt)
                    progress(request_id, f"Network is not ready yet; retrying in {delay} second(s)…\n", output)
                    time.sleep(delay)
        if installer_data is None:
            raise RuntimeError(
                "Could not reach the Hermes installer after several attempts. "
                f"Check the Mac's network connection and retry. ({last_download_error})"
            )
        installer_path.write_bytes(installer_data)
        return_code = 0
        common_args = ["--skip-setup", "--skip-browser", "--skip-computer-use", "--non-interactive",
                       "--dir", str(HERMES_INSTALL_DIR), "--hermes-home", str(HERMES_HOME)]
        # The full installer always provisions browser-side Node dependencies. Talaria's
        # headless VM needs the agent, session store, and gateway only, so use Hermes's
        # supported bootstrap stages and deliberately omit node-deps/browser/setup.
        for stage in ("repository", "venv", "python-deps", "path", "config", "complete"):
            progress(request_id, f"\n[{stage}]\n", output)
            process = subprocess.Popen(
                ["/bin/bash", str(installer_path), *common_args, "--stage", stage],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                env=hermes_environment(),
            )
            for line in process.stdout:
                progress(request_id, line, output)
            return_code = process.wait()
            if return_code != 0:
                break
    except (OSError, RuntimeError, urllib.error.URLError) as exc:
        error(f"Could not install Hermes Agent: {exc}", output)
        return

    if return_code != 0 or not hermes_executable():
        error(f"Hermes Agent installation failed with exit code {return_code}.", output)
        return
    try:
        save_agent_soul(request)
    except (OSError, ValueError) as exc:
        error(f"Could not save agent soul: {exc}", output)
        return
    progress(request_id, "Hermes Agent is ready.\n", output)
    emit({"type": "complete"}, output)


def run_shell_command(request, output=None):
    request_id = trim(request.get("request_id"))
    session_id = trim(request.get("session_id"))
    command = trim(request.get("command"))
    if not request_id or not session_id or not command:
        error("Shell session, request ID, and command are required.", output)
        return

    default_directory = "/workspace" if Path("/workspace").is_dir() else "/"
    with _shell_lock:
        working_directory = _shell_directories.get(session_id, default_directory)
    if not Path(working_directory).is_dir():
        working_directory = default_directory

    marker = f"__TALARIA_CWD_{secrets.token_hex(12)}__"
    script = f"{command}\nprintf '\\n{marker}%s\\n' \"$PWD\"\n"
    environment = os.environ.copy()
    environment.update({
        "HOME": "/workspace",
        "PATH": "/workspace/.local/bin:/workspace/.hermes/bin:" + environment.get("PATH", ""),
        "TERM": "xterm-256color",
    })
    process = subprocess.Popen(
        ["/bin/bash", "-c", script],
        cwd=working_directory,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        command_output, _ = process.communicate(timeout=60)
    except subprocess.TimeoutExpired:
        process.kill()
        command_output, _ = process.communicate()
        if command_output:
            emit({"type": "delta", "request_id": request_id, "kind": "content", "text": command_output}, output)
        error("Command exceeded the 60 second debug terminal limit.", output)
        return

    marker_index = command_output.rfind("\n" + marker)
    if marker_index >= 0:
        visible_output = command_output[:marker_index]
        directory_text = command_output[marker_index + len(marker) + 1:].splitlines()
        if directory_text and Path(directory_text[0]).is_dir():
            with _shell_lock:
                _shell_directories[session_id] = directory_text[0]
    else:
        visible_output = command_output

    if visible_output:
        emit({"type": "delta", "request_id": request_id, "kind": "content", "text": visible_output}, output)
    emit({"type": "complete"}, output)


def tui_gateway(token="", model=""):
    global _tui_gateway, _tui_token
    with _gateway_lock:
        if _tui_gateway is not None and token and token != _tui_token:
            if _tui_gateway.listeners:
                raise RuntimeError("Finish the active Hermes turn before changing credentials.")
            _tui_gateway.process.terminate()
            try:
                _tui_gateway.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                _tui_gateway.process.kill()
                _tui_gateway.process.wait()
            _tui_gateway = None
        if _tui_gateway is None or _tui_gateway.process.poll() is not None:
            executable = hermes_executable()
            if not executable:
                raise RuntimeError("Hermes Agent is not installed. Open Agents, select this agent, and click Install Hermes.")
            HERMES_HOME.mkdir(parents=True, exist_ok=True)
            python = Path(executable).resolve().parent / "python"
            _tui_gateway = HermesGateway(python, hermes_environment(token, model), HERMES_HOME)
            _tui_token = token
        return _tui_gateway


def fetch_hermes_commands(request, output=None):
    try:
        catalogue = tui_gateway(trim(request.get("token")), trim(request.get("model"))).catalog()
        emit({"type": "delta", "request_id": request["request_id"], "kind": "content",
              "text": json.dumps(catalogue)}, output)
        emit({"type": "complete"}, output)
    except (OSError, ValueError, RuntimeError) as exc:
        error(f"Could not load Hermes commands: {exc}", output)


class StreamCancellation:
    """Per-connection cancellation; callbacks also run if registered after Stop."""
    def __init__(self):
        self.event = threading.Event()
        self.lock = threading.Lock()
        self.callbacks = []
        self.finished = False

    def finish(self):
        with self.lock:
            self.finished = True
            self.callbacks = []

    def cancelled(self):
        return self.event.is_set()

    def on_cancel(self, callback):
        with self.lock:
            cancelled = self.cancelled()
            if not cancelled:
                self.callbacks.append(callback)
        if cancelled:
            callback()

    def cancel(self):
        with self.lock:
            if self.cancelled() or self.finished:
                return
            self.event.set()
            callbacks, self.callbacks = self.callbacks, []
        for callback in callbacks:
            callback()


def stream_hermes_session(request, output=None, cancellation=None):
    cancellation = cancellation or StreamCancellation()
    request_id = trim(request.get("request_id"))
    session_id = trim(request.get("session_id"))
    token = trim(request.get("token"))
    model = trim(request.get("model"))
    prompt = trim(request.get("prompt"))
    if not request_id or not session_id or not token or not model or not prompt:
        error("Hermes session, OpenRouter token, model, request ID, and prompt are required.", output)
        return
    try:
        if cancellation.cancelled():
            return
        save_agent_soul(request)
        gateway = tui_gateway(token, model)
        gateway.run(session_id, model, prompt, lambda kind, text: emit(
            {"type": "delta", "request_id": request_id, "kind": kind, "text": text}, output), cancellation=cancellation)
        cancellation.finish()
        if not cancellation.cancelled():
            emit({"type": "complete"}, output)
    except (OSError, ValueError, RuntimeError) as exc:
        if cancellation.cancelled():
            return
        error(f"Could not run the Hermes session: {exc}", output)


def select_hermes_model(request, output=None):
    token, model, session_id = (trim(request.get(key)) for key in ("token", "model", "session_id"))
    if not token or not model or not session_id:
        error("Token, model, and Hermes session are required to switch models.", output)
        return
    try:
        tui_gateway(token, model).select_model(session_id, model)
        emit({"type": "complete"}, output)
    except (OSError, ValueError, RuntimeError) as exc:
        error(f"Could not switch Hermes model: {exc}", output)


def fetch_models(request, output=None):
    try:
        catalogue = tui_gateway(trim(request.get("token"))).model_options()
        emit({"type": "models", "response": catalogue}, output)
    except (OSError, ValueError, RuntimeError) as exc:
        error(f"Could not load Hermes models: {exc}", output)


def generate_hermes_text(request, output=None):
    request_id = trim(request.get("request_id"))
    token, model = trim(request.get("token")), trim(request.get("model"))
    instructions, user_input = request.get("instructions"), request.get("input")
    if not request_id or not token or not model or not isinstance(instructions, str) or not isinstance(user_input, str) or not user_input.strip():
        error("Request ID, token, model, instructions, and input are required for Hermes text generation.", output)
        return
    try:
        text = tui_gateway(token, model).generate_text(model, instructions, user_input)
        emit({"type": "delta", "request_id": request_id, "kind": "content", "text": text}, output)
        emit({"type": "complete"}, output)
    except (OSError, ValueError, RuntimeError) as exc:
        error(f"Could not generate text through Hermes: {exc}", output)


def handle_request(request, output=None, cancellation=None):
    operation = request.get("operation")
    if operation == "shell_command":
        run_shell_command(request, output)
        return 0
    if operation == "install_hermes":
        install_hermes(request, output)
        return 0
    if operation == "hermes_commands":
        fetch_hermes_commands(request, output)
        return 0
    if operation == "hermes_session_chat":
        stream_hermes_session(request, output, cancellation)
        return 0
    if operation == "hermes_select_model":
        select_hermes_model(request, output)
        return 0
    if operation == "models":
        fetch_models(request, output)
        return 0
    if operation == "hermes_generate_text":
        generate_hermes_text(request, output)
        return 0

    error("Agent operation is not supported.", output)
    return 1


def handle_connection(connection):
    with connection:
        reader = connection.makefile("rb")
        writer = connection.makefile("wb")
        try:
            line = reader.readline()
            if not line:
                return
            request = json.loads(line.decode("utf-8"))
        except json.JSONDecodeError as exc:
            error(f"Agent received an invalid request: {exc}", writer)
            return
        except OSError as exc:
            error(f"Agent socket read failed: {exc}", writer)
            return

        cancellation = StreamCancellation()
        monitor = None
        if request.get("operation") == "hermes_session_chat":
            def monitor_disconnect():
                try:
                    # This connection carries one request. EOF means its caller stopped.
                    while reader.read(1):
                        pass
                except (OSError, ValueError):
                    pass  # A reset or read failure is also a disconnected caller.
                try:
                    cancellation.cancel()
                except (OSError, ValueError, RuntimeError) as exc:
                    print(f"Stream cancellation: {exc}", file=sys.stderr)
            monitor = threading.Thread(target=monitor_disconnect, daemon=True)
            monitor.start()
        try:
            handle_request(request, writer, cancellation)
        except (BrokenPipeError, ConnectionResetError):
            cancellation.cancel()
        finally:
            cancellation.finish()
            # Wake the reader on normal completion without issuing an extra stop.
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            if monitor:
                monitor.join(timeout=6)
            reader.close()
            writer.close()


def serve_vsock(port):
    if not hasattr(socket, "AF_VSOCK"):
        raise RuntimeError("Python was built without AF_VSOCK support.")

    listener = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    try:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    except OSError:
        pass
    listener.bind((socket.VMADDR_CID_ANY, port))
    listener.listen(16)
    while True:
        connection, _address = listener.accept()
        thread = threading.Thread(target=handle_connection, args=(connection,), daemon=True)
        thread.start()


def main():
    parser = argparse.ArgumentParser(description="Talaria Hermes TUI agent runtime.")
    parser.add_argument("--serve-vsock", type=int, default=0)
    args = parser.parse_args()
    if args.serve_vsock:
        serve_vsock(args.serve_vsock)
        return 0

    try:
        request = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        error(f"Agent received an invalid request: {exc}")
        return 1

    return handle_request(request)


if __name__ == "__main__":
    raise SystemExit(main())
