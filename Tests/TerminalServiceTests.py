import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import select
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("terminal_service", ROOT / "AgentRuntime/terminal_service.py")
service = importlib.util.module_from_spec(spec)
spec.loader.exec_module(service)


class Shell:
    def __init__(self, workspace):
        self.connection, guest = socket.socketpair()
        self.process = subprocess.Popen([sys.executable, "-B", __file__, "--serve-fd", str(guest.fileno()), str(workspace)],
                                        pass_fds=(guest.fileno(),), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        guest.close()
        self.pending = bytearray()
        self.output = bytearray()
        self.exit_code = None
        self.send(b"H", json.dumps({"term": "xterm-256color", "rows": 24, "columns": 80}).encode())

    def send(self, kind, data):
        self.connection.sendall(service.frame(kind, data))

    def command(self, command):
        self.send(b"D", command.encode() + b"\r")

    def until(self, expected, timeout=5):
        deadline = time.monotonic() + timeout
        while expected not in self.output:
            if time.monotonic() > deadline:
                raise AssertionError(f"Missing {expected!r}: {bytes(self.output)!r}")
            if not select.select([self.connection], [], [], max(0, deadline - time.monotonic()))[0]:
                continue
            data = self.connection.recv(65536)
            if not data:
                raise AssertionError(f"Unexpected disconnect: {bytes(self.output)!r}")
            self.pending.extend(data)
            while len(self.pending) >= 5:
                length = struct.unpack("!I", self.pending[1:5])[0]
                if len(self.pending) < 5 + length:
                    break
                kind, payload = self.pending[:1], bytes(self.pending[5:5 + length])
                del self.pending[:5 + length]
                if kind == b"D":
                    self.output.extend(payload)
                elif kind == b"X":
                    self.exit_code = struct.unpack("!I", payload)[0]
                else:
                    raise AssertionError(payload)
        index = self.output.index(expected) + len(expected)
        result = bytes(self.output[:index])
        del self.output[:index]
        return result

    def close(self):
        self.connection.close()
        try:
            self.process.wait(timeout=4)
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()
            self.process.stderr.close()


class TerminalServiceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="talaria-pty-")
        self.workspace = Path(self.directory.name).resolve()
        # Tests never load the user's shell configuration or history.
        (self.workspace / ".bash_profile").write_text("export PS1='VM> '\n")
        self.shell = Shell(self.workspace)
        self.shell.until(b"VM> ")

    def tearDown(self):
        self.shell.close()
        self.directory.cleanup()

    def test_tty_unicode_ansi_and_persistent_directory(self):
        self.shell.command("test -t 0 && test -t 1 && printf '__TTY__\\n'")
        self.shell.until(b"\r\n__TTY__\r\n")
        self.shell.command("printf '\\033[31mhello 🌍\\033[0m\\n'")
        self.shell.until("\x1b[31mhello 🌍\x1b[0m\r\n".encode())
        (self.workspace / "subdir").mkdir()
        self.shell.command("cd subdir")
        self.shell.until(b"VM> ")
        self.shell.command("pwd")
        self.shell.until(str(self.workspace / "subdir").encode() + b"\r\n")

    def test_resize_control_c_and_job_control(self):
        self.shell.send(b"W", struct.pack("!HH", 43, 132))
        self.shell.command("stty size")
        self.shell.until(b"\r\n43 132\r\n")
        self.shell.command("sleep 30")
        time.sleep(0.15)
        self.shell.send(b"D", b"\x03")
        self.shell.command("printf '__INTERRUPTED__\\n'")
        self.shell.until(b"\r\n__INTERRUPTED__\r\n", timeout=3)
        self.shell.command("sleep 30")
        time.sleep(0.15)
        self.shell.send(b"D", b"\x1a")
        self.shell.until(b"Stopped", timeout=3)
        self.shell.command("fg")
        time.sleep(0.15)
        self.shell.send(b"D", b"\x03")
        self.shell.command("printf '__JOB_CONTROL__\\n'")
        self.shell.until(b"\r\n__JOB_CONTROL__\r\n", timeout=3)

    def test_tab_completion_and_arrow_history(self):
        (self.workspace / "completion-file.txt").write_text("__COMPLETED__\n")
        self.shell.send(b"D", b"cat completion-f\t\r")
        self.shell.until(b"\r\n__COMPLETED__\r\n")
        self.shell.command("printf '__HISTORY__\\n'")
        self.shell.until(b"\r\n__HISTORY__\r\n")
        self.shell.send(b"D", b"\x1b[A\r")
        self.shell.until(b"\r\n__HISTORY__\r\n")

    def test_fragmented_input_and_large_output(self):
        packet = service.frame(b"D", b"printf '__FRAGMENTED__\\n'\r")
        for byte in packet:
            self.shell.connection.sendall(bytes([byte]))
        self.shell.until(b"\r\n__FRAGMENTED__\r\n")
        self.shell.command("printf '%020000d\\n' 0; printf '__END__\\n'")
        output = self.shell.until(b"\r\n__END__\r\n")
        self.assertIn(b"0" * 20000, output)

    def test_disconnect_ends_foreground_process(self):
        self.shell.command("sh -c 'echo CHILD_PID=$$; exec sleep 30'")
        output = self.shell.until(b"CHILD_PID=")
        output += self.shell.until(b"\r\n")
        # Discard the command's echoed occurrence and read the actual PID line.
        match = re.search(rb"\r\nCHILD_PID=(\d+)\r\n", output)
        if not match:
            output += self.shell.until(b"\r\n")
            match = re.search(rb"\r\nCHILD_PID=(\d+)\r\n", output)
        self.assertIsNotNone(match, output)
        pid = int(match.group(1))
        self.shell.connection.shutdown(socket.SHUT_RDWR)
        self.shell.process.wait(timeout=4)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.05)
        else:
            self.fail("Foreground process survived terminal disconnect")


class NativeTerminalClientTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="tl-client-", dir="/tmp")
        self.workspace = Path(self.directory.name).resolve()
        (self.workspace / ".bash_profile").write_text("export PS1='VM> '\n")
        path = str(self.workspace / "socket")
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.bind(path)
        listener.listen(1)
        self.master, self.slave = os.openpty()
        self.original = termios.tcgetattr(self.slave)
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        self.client = subprocess.Popen([str(ROOT / "build/TerminalClientProbe"), path],
                                       stdin=self.slave, stdout=self.slave, stderr=self.slave,
                                       start_new_session=True, env={**os.environ, "TERM": "xterm-256color"})
        guest, _ = listener.accept()
        listener.close()
        self.server = subprocess.Popen([sys.executable, "-B", __file__, "--serve-fd", str(guest.fileno()), str(self.workspace)],
                                       pass_fds=(guest.fileno(),), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        guest.close()
        self.output = bytearray()
        self.until(b"VM> ")

    def until(self, expected, timeout=5):
        deadline = time.monotonic() + timeout
        while expected not in self.output:
            if not select.select([self.master], [], [], max(0, deadline - time.monotonic()))[0]:
                raise AssertionError(f"Missing {expected!r}: {bytes(self.output)!r}")
            self.output.extend(os.read(self.master, 65536))
        index = self.output.index(expected) + len(expected)
        result = bytes(self.output[:index])
        del self.output[:index]
        return result

    def tearDown(self):
        if self.client.poll() is None:
            self.client.terminate()
        self.client.wait(timeout=5)
        self.server.wait(timeout=5)
        self.server.stderr.close()
        os.close(self.master)
        os.close(self.slave)
        self.directory.cleanup()

    def test_round_trip_resize_interrupt_exit_and_tty_restore(self):
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 51, 140, 0, 0))
        os.kill(self.client.pid, signal.SIGWINCH)
        time.sleep(0.2)
        os.write(self.master, b"stty size\r")
        self.until(b"\r\n51 140\r\n")
        os.write(self.master, b"sleep 30\r")
        time.sleep(0.15)
        os.write(self.master, b"\x03printf '__CLIENT_OK__\\n'\r")
        self.until(b"\r\n__CLIENT_OK__\r\n", timeout=3)
        os.write(self.master, b"exit 7\r")
        self.assertEqual(self.client.wait(timeout=5), 7)
        restored = termios.tcgetattr(self.slave)
        # macOS sets PENDIN when returning to canonical input; it is kernel state,
        # not a changed terminal setting.
        restored[3] &= ~getattr(termios, "PENDIN", 0)
        expected = list(self.original)
        expected[3] &= ~getattr(termios, "PENDIN", 0)
        self.assertEqual(restored, expected)

    def test_signal_restores_host_terminal(self):
        self.client.terminate()
        self.assertEqual(self.client.wait(timeout=5), 128 + signal.SIGTERM)
        restored = termios.tcgetattr(self.slave)
        # macOS sets PENDIN when returning to canonical input; it is kernel state,
        # not a changed terminal setting.
        restored[3] &= ~getattr(termios, "PENDIN", 0)
        expected = list(self.original)
        expected[3] &= ~getattr(termios, "PENDIN", 0)
        self.assertEqual(restored, expected)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--serve-fd":
        # Match the VM init script's background service: asynchronous shell jobs
        # inherit ignored interrupt/quit signals before Python starts.
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGQUIT, signal.SIG_IGN)
        service.handle_connection(socket.socket(fileno=int(sys.argv[2])), Path(sys.argv[3]))
    else:
        unittest.main()
