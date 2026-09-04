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
import time
import urllib.error
import urllib.parse
import urllib.request


CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"
MODELS_URL = "https://openrouter.ai/api/v1/models?output_modalities=text"
HERMES_HOME = Path("/workspace/.hermes")
HERMES_INSTALL_DIR = HERMES_HOME / "hermes-agent"
HERMES_API_URL = "http://127.0.0.1:8642"
HERMES_API_KEY = "talaria-vsock-only"
_gateway_process = None
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
        "API_SERVER_ENABLED": "true",
        "API_SERVER_KEY": HERMES_API_KEY,
        "API_SERVER_HOST": "127.0.0.1",
        "API_SERVER_PORT": "8642",
        "HERMES_INFERENCE_PROVIDER": "openrouter",
    })
    if trim(token):
        environment["OPENROUTER_API_KEY"] = trim(token)
    if trim(model):
        environment["HERMES_INFERENCE_MODEL"] = trim(model)
    return environment


def install_hermes(request, output=None):
    request_id = trim(request.get("request_id")) or "install"
    if hermes_executable():
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


def configure_hermes(token, model):
    HERMES_HOME.mkdir(parents=True, exist_ok=True)
    safe_token = trim(token).replace("\n", "").replace("\r", "")
    safe_model = trim(model).replace("\n", "").replace("\r", "")
    env_path = HERMES_HOME / ".env"
    env_path.write_text(
        f"OPENROUTER_API_KEY={safe_token}\n"
        f"HERMES_INFERENCE_PROVIDER=openrouter\n"
        f"HERMES_INFERENCE_MODEL={safe_model}\n"
        f"API_SERVER_ENABLED=true\n"
        f"API_SERVER_KEY={HERMES_API_KEY}\n"
        f"API_SERVER_HOST=127.0.0.1\n"
        f"API_SERVER_PORT=8642\n",
        encoding="utf-8",
    )


def api_request(path, method="GET", body=None, timeout=60):
    payload = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(
        HERMES_API_URL + path,
        data=payload,
        headers={"Authorization": f"Bearer {HERMES_API_KEY}", "Content-Type": "application/json"},
        method=method,
    )
    return urllib.request.urlopen(request, timeout=timeout)


def ensure_hermes_gateway(token, model):
    global _gateway_process
    executable = hermes_executable()
    if not executable:
        raise RuntimeError("Hermes Agent is not installed. Start onboarding from Settings.")
    configure_hermes(token, model)
    try:
        with api_request("/health", timeout=2) as response:
            if response.status == 200:
                return
    except (OSError, urllib.error.URLError):
        pass

    with _gateway_lock:
        try:
            with api_request("/health", timeout=2) as response:
                if response.status == 200:
                    return
        except (OSError, urllib.error.URLError):
            pass
        log_path = HERMES_HOME / "talaria-gateway.log"
        log_file = log_path.open("ab")
        _gateway_process = subprocess.Popen(
            [executable, "gateway", "run"],
            stdout=log_file,
            stderr=subprocess.STDOUT,
            env=hermes_environment(token, model),
            cwd="/workspace",
        )
        deadline = time.time() + 45
        while time.time() < deadline:
            if _gateway_process.poll() is not None:
                raise RuntimeError(f"Hermes gateway exited. See {log_path}.")
            try:
                with api_request("/health", timeout=2) as response:
                    if response.status == 200:
                        return
            except (OSError, urllib.error.URLError):
                time.sleep(0.5)
        raise RuntimeError("Timed out waiting for the Hermes gateway.")


def ensure_hermes_session(session_id, model):
    quoted = urllib.parse.quote(session_id, safe="")
    try:
        with api_request(f"/api/sessions/{quoted}", timeout=5):
            return
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            raise
    with api_request("/api/sessions", method="POST", body={
        "id": session_id,
        "source": "talaria",
        "model": model,
    }, timeout=10):
        return


def stream_hermes_session(request, output=None):
    request_id = trim(request.get("request_id"))
    session_id = trim(request.get("session_id"))
    token = trim(request.get("token"))
    model = trim(request.get("model"))
    prompt = trim(request.get("prompt"))
    if not request_id or not session_id or not token or not model or not prompt:
        error("Hermes session, OpenRouter token, model, request ID, and prompt are required.", output)
        return
    try:
        ensure_hermes_gateway(token, model)
        ensure_hermes_session(session_id, model)
        quoted = urllib.parse.quote(session_id, safe="")
        with api_request(f"/api/sessions/{quoted}/chat/stream", method="POST", body={
            "input": prompt,
            "model": model,
            "provider": "openrouter",
        }, timeout=600) as response:
            event_name = ""
            for raw_line in response:
                line = raw_line.decode("utf-8", errors="replace").strip()
                if line.startswith("event:"):
                    event_name = line[6:].strip()
                    continue
                if not line.startswith("data:"):
                    continue
                payload = json.loads(line[5:].strip())
                if event_name == "assistant.delta":
                    text = payload.get("delta")
                    if isinstance(text, str) and text:
                        emit({"type": "delta", "request_id": request_id, "kind": "content", "text": text}, output)
                elif event_name == "tool.progress" and payload.get("tool_name") == "_thinking":
                    text = payload.get("delta") or payload.get("preview")
                    if isinstance(text, str) and text:
                        emit({"type": "delta", "request_id": request_id, "kind": "thinking", "text": text}, output)
                elif event_name == "run.completed":
                    emit({"type": "complete"}, output)
                    return
                elif event_name == "error":
                    error(payload.get("message") or "Hermes session failed.", output)
                    return
    except urllib.error.HTTPError as exc:
        error(f"Hermes returned HTTP {exc.code}: {exc.read().decode('utf-8', errors='replace')}", output)
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        error(f"Could not run the Hermes session: {exc}", output)


def headers(token="", content_type=None):
    result = {
        "Accept": "application/json",
        "HTTP-Referer": "app://talaria",
        "X-Title": "Talaria",
    }
    if content_type:
        result["Content-Type"] = content_type
    token = trim(token)
    if token:
        result["Authorization"] = f"Bearer {token}"
    return result


def content_to_text(value):
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        parts = []
        for item in value:
            if isinstance(item, dict):
                text = item.get("text") or item.get("content")
                if isinstance(text, str):
                    parts.append(text)
        joined = "".join(parts)
        return joined or None
    return None


def thinking_text(delta):
    details = delta.get("reasoning_details")
    if isinstance(details, list):
        parts = []
        for item in details:
            if isinstance(item, dict):
                text = item.get("text") or item.get("summary")
                if isinstance(text, str):
                    parts.append(text)
        joined = "".join(parts)
        if joined:
            return joined

    for key in ("reasoning", "reasoning_content"):
        text = content_to_text(delta.get(key))
        if text:
            return text
    return None


def parse_delta(data):
    payload = json.loads(data)
    choices = payload.get("choices")
    content_parts = []
    thinking_parts = []
    if not isinstance(choices, list):
        return "", ""

    for choice in choices:
        if not isinstance(choice, dict):
            continue
        delta = choice.get("delta")
        if not isinstance(delta, dict):
            continue
        content = content_to_text(delta.get("content"))
        if content:
            content_parts.append(content)
        thought = thinking_text(delta)
        if thought:
            thinking_parts.append(thought)

    return "".join(content_parts), "".join(thinking_parts)


def http_error_message(exc):
    body = exc.read().decode("utf-8", errors="replace")
    try:
        payload = json.loads(body)
        message = payload.get("error", {}).get("message")
        if isinstance(message, str) and message:
            return f"OpenRouter returned {exc.code}: {message}"
    except json.JSONDecodeError:
        pass
    return f"OpenRouter returned {exc.code}: {body}"


def fetch_models(request, output=None):
    token = trim(request.get("token"))
    url_request = urllib.request.Request(MODELS_URL, headers=headers(token), method="GET")
    try:
        with urllib.request.urlopen(url_request, timeout=60) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        error(http_error_message(exc), output)
        return
    except OSError as exc:
        error(f"Could not load OpenRouter models: {exc}", output)
        return

    try:
        emit({"type": "models", "response": json.loads(body)}, output)
    except json.JSONDecodeError as exc:
        error(f"OpenRouter returned an unexpected models response: {exc}", output)


def stream_chat(request, output=None):
    token = trim(request.get("token"))
    model = trim(request.get("model"))
    request_id = trim(request.get("request_id"))
    messages = request.get("messages")
    if not token:
        error("OpenRouter token is required.", output)
        return
    if not model:
        error("OpenRouter model is required.", output)
        return
    if not request_id:
        error("Request ID is required.", output)
        return
    if not isinstance(messages, list) or not messages:
        error("At least one message is required.", output)
        return

    body = json.dumps({
        "model": model,
        "messages": messages,
        "temperature": 0.7,
        "stream": True,
        "reasoning": {"max_tokens": 2000},
    }).encode("utf-8")
    url_request = urllib.request.Request(
        CHAT_URL,
        data=body,
        headers=headers(token, "application/json"),
        method="POST",
    )

    received = False
    try:
        with urllib.request.urlopen(url_request, timeout=60) as response:
            for raw_line in response:
                line = raw_line.decode("utf-8", errors="replace").strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    emit({"type": "complete"}, output)
                    return
                try:
                    content, thought = parse_delta(data)
                except json.JSONDecodeError as exc:
                    error(f"OpenRouter returned an unexpected stream chunk: {exc}", output)
                    return
                if thought:
                    received = True
                    emit({"type": "delta", "request_id": request_id, "kind": "thinking", "text": thought}, output)
                if content:
                    received = True
                    emit({"type": "delta", "request_id": request_id, "kind": "content", "text": content}, output)
    except urllib.error.HTTPError as exc:
        error(http_error_message(exc), output)
        return
    except OSError as exc:
        error(f"Could not read OpenRouter stream: {exc}", output)
        return

    if received:
        emit({"type": "complete"}, output)
    else:
        error("OpenRouter returned an empty assistant message.", output)


def handle_request(request, output=None):
    operation = request.get("operation")
    if operation == "shell_command":
        run_shell_command(request, output)
        return 0
    if operation == "install_hermes":
        install_hermes(request, output)
        return 0
    if operation == "hermes_session_chat":
        stream_hermes_session(request, output)
        return 0
    if operation == "models":
        fetch_models(request, output)
        return 0
    if operation == "stream_chat":
        stream_chat(request, output)
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

        handle_request(request, writer)


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
    parser = argparse.ArgumentParser(description="Talaria OpenRouter agent runtime.")
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
