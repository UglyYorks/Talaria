"""Opt-in integration test using the built, signed TerminalVMProbe and app.

This boots one disposable VM, never opens the app database, and removes its
workspace afterward. Ordinary make test uses local PTYs instead.

Build the probe from the repository root with:
  xcrun clang -fobjc-arc -fmodules -ISource Tests/TerminalVMProbe.m \
    Source/AgentVMService.m Source/TalariaModels.m Source/TLVMTerminalSession.m \
    -framework Foundation -framework AppKit -framework Virtualization \
    -o build/TerminalVMProbe
Sign it with the app's development identity and Entitlements.plist, then run:
  python3 -B Tests/TerminalVMIntegration.py
"""
import fcntl
import os
from pathlib import Path
import select
import re
import signal
import struct
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "build/Talaria.app/Contents/MacOS/Talaria"
RUNTIME = ROOT / "build/agent-runtime/linux-arm64"


def main():
    with tempfile.TemporaryDirectory(prefix="talaria-vm-terminal-", dir="/tmp") as folder:
        log_path = Path(folder) / "probe.log"
        with log_path.open("w+") as log:
            probe = subprocess.Popen([str(ROOT / "build/TerminalVMProbe"), str(RUNTIME), folder, str(APP)],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log)
            client = None
            master = slave = None
            try:
                if not select.select([probe.stdout], [], [], 60)[0]:
                    raise AssertionError("VM terminal service did not start")
                path = probe.stdout.readline().decode().strip()
                if not path:
                    log.seek(0)
                    raise AssertionError(log.read())
                master, slave = os.openpty()
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
                client = subprocess.Popen([str(APP), "--vm-terminal", path], stdin=slave, stdout=slave, stderr=slave,
                                          start_new_session=True, env={**os.environ, "TERM": "xterm-256color"})
                output = bytearray()

                def until(expected, timeout=8):
                    deadline = time.monotonic() + timeout
                    while expected not in output:
                        if not select.select([master], [], [], max(0, deadline - time.monotonic()))[0]:
                            raise AssertionError(f"Missing {expected!r}: {bytes(output)!r}")
                        output.extend(os.read(master, 65536))
                        # Bash 5 toggles bracketed paste around each prompt. Keep
                        # all other escape sequences for the full-screen checks.
                        output[:] = re.sub(rb"\x1b\[\?2004[hl]\r?", b"", output)
                    index = output.index(expected) + len(expected)
                    result = bytes(output[:index])
                    del output[:index]
                    return result

                def command(value):
                    os.write(master, value.encode() + b"\r")

                until(b"# ")
                command("uname -s; test -t 0 && test -t 1 && printf '__REAL_TTY__\\n'")
                until(b"Linux\r\n")
                until(b"__REAL_TTY__\r\n")
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 42, 133, 0, 0))
                os.kill(client.pid, signal.SIGWINCH)
                time.sleep(0.2)
                command("stty size")
                until(b"42 133\r\n")
                command("sleep 30")
                time.sleep(0.2)
                os.write(master, b"\x03")
                command("printf '__INTERRUPT_OK__\\n'")
                until(b"__INTERRUPT_OK__\r\n", timeout=3)
                command("sleep 30")
                time.sleep(0.2)
                os.write(master, b"\x1a")
                until(b"Stopped", timeout=3)
                command("fg")
                time.sleep(0.2)
                os.write(master, b"\x03")
                command("printf '__JOB_CONTROL_OK__\\n'")
                until(b"__JOB_CONTROL_OK__\r\n", timeout=3)
                command("printf '\\033[31mVM 🌍\\033[0m\\n'")
                until("\x1b[31mVM 🌍\x1b[0m\r\n".encode())
                command("printf '__COMPLETION_OK__\\n' > terminal-completion.txt")
                until(b"# ")
                os.write(master, b"cat terminal-compl\t\r")
                until(b"__COMPLETION_OK__\r\n")
                command("printf '__HISTORY_OK__\\n'")
                until(b"__HISTORY_OK__\r\n")
                os.write(master, b"\x1b[A\r")
                until(b"__HISTORY_OK__\r\n")
                command("top")
                screen = until(b"Mem:")
                assert b"\x1b[" in screen, "top did not use terminal escape sequences"
                os.write(master, b"q")
                time.sleep(0.2)
                command("printf '__FULLSCREEN_OK__\\n'")
                until(b"__FULLSCREEN_OK__\r\n")
                command("exit 7")
                assert client.wait(timeout=5) == 7, "VM shell exit status was not forwarded"
                print("Real Linux VM: TTY, resize, Ctrl-C, job control, Unicode/ANSI, tab completion, history, top, and exit status passed.")
            finally:
                if client and client.poll() is None:
                    client.terminate()
                    client.wait(timeout=5)
                if master is not None:
                    os.close(master)
                    os.close(slave)
                if probe.poll() is None:
                    try:
                        probe.stdin.write(b"q")
                        probe.stdin.flush()
                        probe.wait(timeout=10)
                    except (BrokenPipeError, subprocess.TimeoutExpired):
                        probe.terminate()
                        probe.wait(timeout=5)
                probe.stdin.close()
                probe.stdout.close()
            assert probe.returncode == 0, "Disposable VM did not shut down cleanly"


if __name__ == "__main__":
    main()
