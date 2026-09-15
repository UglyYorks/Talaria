"""Snapshot explicitly delivered files into conversation-owned attachments."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import uuid

MAX_BYTES = 20 * 1024 * 1024
MAX_FILES = 10
MARKER = "TALARIA_ATTACHMENT: "


def delivery_paths(text):
    fence = None
    for index, line in enumerate(text.splitlines()):
        stripped = line.lstrip()
        match = re.match(r"(`{3,}|~{3,})", stripped)
        if match:
            token = match[1]
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence):
                fence = None
            continue
        if fence is None and line.startswith(MARKER):
            yield index, line[len(MARKER):].strip()


def safe_directory(path):
    # Workspace is a trusted runtime root; agent-created descendants must not
    # redirect writes through symlinks.
    path.mkdir(exist_ok=True)
    if path.is_symlink() or not path.is_dir():
        raise ValueError("The attachment destination must be a regular directory.")
    return path


def export_response(text, session_id, workspace, private=False):
    markers = list(delivery_paths(text))
    if not markers:
        return text, []
    if not re.fullmatch(r"[A-Za-z0-9_-]+", session_id):
        raise ValueError("Invalid attachment conversation.")
    root = Path(workspace)
    for component in ("attachments", session_id, "generated"):
        root = safe_directory(root / component)
    key = hashlib.sha256(text.encode()).hexdigest()
    manifest = root / (key + ".json")
    if manifest.is_file() and not manifest.is_symlink():
        saved = json.loads(manifest.read_text())
        return saved["content"], saved["attachments"]
    rows, replacements, total = [], {}, 0
    seen = {}
    for index, raw_path in markers:
        try:
            if raw_path in seen:
                replacements[index] = ""
                continue
            if len(rows) >= MAX_FILES:
                raise ValueError("Return at most 10 files per response.")
            source = Path(raw_path)
            if not source.is_absolute() or source.is_symlink():
                raise ValueError("Use an absolute path to a regular file, not a symbolic link.")
            descriptor = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            with os.fdopen(descriptor, "rb") as handle:
                if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
                    raise ValueError("Only regular files can be attached; zip folders first.")
                data = handle.read(MAX_BYTES - total + 1)
            if len(data) > MAX_BYTES - total:
                raise ValueError("Returned files must total at most 20 MiB per response.")
            total += len(data)
            directory = safe_directory(root / uuid.uuid4().hex)
            target = directory / source.name
            target.write_bytes(data)
            row = {"name": source.name, "guestPath": str(target), "directory": False}
            if private:
                row["data"] = base64.b64encode(data).decode("ascii")
            rows.append(row)
            seen[raw_path] = row
            replacements[index] = ""
        except (OSError, ValueError) as exc:
            replacements[index] = f"Could not attach {Path(raw_path).name or 'file'}: {exc}"
    content = "\n".join(replacements.get(index, line) for index, line in enumerate(text.splitlines())).strip()
    saved = {"content": content, "attachments": rows}
    temporary = root / (key + "." + uuid.uuid4().hex + ".tmp")
    temporary.write_text(json.dumps(saved))
    temporary.replace(manifest)
    return content, rows
