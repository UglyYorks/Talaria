"""Interactive VM PTYs over virtio sockets (no host TCP listener).

Frames are a one-byte kind and a network-order uint32 length, followed by bytes.
Host: H JSON handshake, D raw terminal input, W uint16 rows/columns.
Guest: D raw terminal output, X uint32 exit status, E UTF-8 error.
"""
import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import socket
import struct
import termios
import time

MAX_FRAME = 1024 * 1024


def frame(kind, data):
    return kind + struct.pack("!I", len(data)) + data


def read_exact(connection, length):
    result = bytearray()
    while len(result) < length:
        data = connection.recv(length - len(result))
        if not data:
            raise EOFError("Terminal disconnected")
        result.extend(data)
    return bytes(result)


def set_size(master, rows, columns):
    if not 1 <= rows <= 65535 or not 1 <= columns <= 65535:
        raise ValueError("Invalid terminal size")
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))


def end_shell(pid, master):
    # Closing a Terminal tab must also end its foreground program, including a
    # program in a different process group from the interactive shell.
    try:
        foreground = os.tcgetpgrp(master)
    except OSError:
        foreground = pid
    for group in {pid, foreground}:
        if group > 0:
            try:
                os.killpg(group, signal.SIGHUP)
            except ProcessLookupError:
                pass
    os.close(master)
    for _ in range(20):
        try:
            if os.waitpid(pid, os.WNOHANG)[0]:
                return
        except ChildProcessError:
            return
        time.sleep(0.05)
    for group in {pid, foreground}:
        if group > 0:
            try:
                os.killpg(group, signal.SIGKILL)
            except ProcessLookupError:
                pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass


def handle_connection(connection, workspace=Path("/workspace")):
    pid = master = None
    reaped = False
    with connection:
        try:
            connection.settimeout(60)
            header = read_exact(connection, 5)
            length = struct.unpack("!I", header[1:])[0]
            if header[:1] != b"H" or length > 4096:
                raise ValueError("Invalid terminal handshake")
            hello = json.loads(read_exact(connection, length))
            terminal = hello.get("term", "xterm-256color")
            if not isinstance(terminal, str) or not re.fullmatch(r"[a-zA-Z0-9+_.-]{1,64}", terminal):
                raise ValueError("Invalid terminal type")
            rows, columns = int(hello["rows"]), int(hello["columns"])
            if not 1 <= rows <= 65535 or not 1 <= columns <= 65535:
                raise ValueError("Invalid terminal size")
            workspace = workspace.resolve()
            environment = os.environ.copy()
            environment.update(HOME=str(workspace), SHELL="/bin/bash", TERM=terminal,
                               LANG="C.UTF-8", COLORTERM="truecolor",
                               HERMES_HOME=str(workspace / ".hermes"),
                               HISTFILE=str(workspace / ".bash_history"))
            environment["PATH"] = f"{workspace}/.hermes/hermes-agent/venv/bin:{workspace}/.local/bin:" + environment.get("PATH", "/usr/bin:/bin")
            # This service is a separate, single-threaded process. Never fork
            # from the multithreaded AI worker (or from a macOS AppKit process).
            pid, master = pty.fork()
            if pid == 0:
                connection.close()
                try:
                    # Init starts this service as a background job, which can
                    # inherit ignored SIGINT/SIGQUIT. Give the interactive shell
                    # normal signal dispositions so Ctrl-C and job control work.
                    for signum in (signal.SIGINT, signal.SIGQUIT, signal.SIGTSTP,
                                   signal.SIGTTIN, signal.SIGTTOU, signal.SIGHUP,
                                   signal.SIGPIPE, signal.SIGCHLD):
                        signal.signal(signum, signal.SIG_DFL)
                    os.chdir(workspace)
                    os.execve("/bin/bash", ["bash", "--login", "-i"], environment)
                except OSError as exc:
                    os.write(2, f"Could not start the VM shell: {exc}\n".encode())
                    os._exit(127)
            set_size(master, rows, columns)
            os.set_blocking(master, False)
            connection.settimeout(30)
            incoming, pending_input = bytearray(), bytearray()
            while True:
                readers = [master]
                if len(pending_input) < MAX_FRAME:
                    readers.append(connection)
                ready, writable, _ = select.select(readers, [master] if pending_input else [], [], 1)
                if master in writable:
                    try:
                        written = os.write(master, pending_input[:65536])
                        del pending_input[:written]
                    except BlockingIOError:
                        pass
                if connection in ready:
                    data = connection.recv(65536)
                    if not data:
                        return
                    incoming.extend(data)
                    while len(incoming) >= 5:
                        kind, length = incoming[:1], struct.unpack("!I", incoming[1:5])[0]
                        if length > MAX_FRAME:
                            raise ValueError("Terminal frame is too large")
                        if len(incoming) < 5 + length:
                            break
                        payload = bytes(incoming[5:5 + length])
                        del incoming[:5 + length]
                        if kind == b"D":
                            pending_input.extend(payload)
                        elif kind == b"W" and length == 4:
                            set_size(master, *struct.unpack("!HH", payload))
                        else:
                            raise ValueError("Invalid terminal frame")
                if master in ready:
                    try:
                        output = os.read(master, 65536)
                    except OSError as exc:
                        if exc.errno != errno.EIO:
                            raise
                        output = b""
                    if not output:
                        _, status = os.waitpid(pid, 0)
                        reaped = True
                        code = os.waitstatus_to_exitcode(status)
                        connection.sendall(frame(b"X", struct.pack("!I", code if code >= 0 else 128 - code)))
                        return
                    connection.sendall(frame(b"D", output))
        except (EOFError, OSError, ValueError, KeyError, TypeError) as exc:
            try:
                connection.sendall(frame(b"E", str(exc).encode("utf-8")))
            except OSError:
                pass
        finally:
            if pid:
                if reaped:
                    os.close(master)
                else:
                    end_shell(pid, master)


def serve(port):
    listener = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    listener.bind((socket.VMADDR_CID_ANY, port))
    listener.listen(16)
    signal.signal(signal.SIGCHLD, signal.SIG_IGN)
    while True:
        connection, _ = listener.accept()
        pid = os.fork()
        if pid == 0:
            listener.close()
            signal.signal(signal.SIGCHLD, signal.SIG_DFL)
            handle_connection(connection)
            os._exit(0)
        connection.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=7048)
    serve(parser.parse_args().port)
