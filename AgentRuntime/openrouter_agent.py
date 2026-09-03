#!/usr/bin/env python3
import argparse
import json
import socket
import sys
import threading
import urllib.error
import urllib.request


CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"
MODELS_URL = "https://openrouter.ai/api/v1/models?output_modalities=text"


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
