#!/usr/bin/env python3
"""Measure extension APIs in embedded macOS CEF versus a Chrome-style control.

Launches a disposable desktop app from this worktree with an isolated profile.
Exit 0 means the limited probe passed; it does NOT certify Web Store support.
Exit 2 means a full tab-API compatibility check failed. Other failures exit 1.
"""
import argparse
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import tempfile
import threading
import time


ROOT = Path(__file__).resolve().parents[1]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"<!doctype html><title>Extension probe</title><h1>Extension API compatibility</h1>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true", help="Use an already built app in this worktree")
    args = parser.parse_args()
    os.chdir(ROOT)
    if not args.skip_build:
        subprocess.run(["make", "build"], check=True)
    work = Path(tempfile.mkdtemp(prefix="extension-probe-", dir=ROOT / "build"))
    server = None
    launcher = None
    try:
        cef = next((ROOT / "build/deps").glob("cef_binary_*"))
        object_dir = ROOT / "build/app-objects"
        objects = sorted(str(p) for p in object_dir.rglob("*.o")
                         if p.name != "main.mm.o" and
                         (ROOT / "Source" / p.relative_to(object_dir).with_suffix("")).exists())
        frameworks = ["QuickLookThumbnailing", "UniformTypeIdentifiers", "AppKit", "Foundation", "QuartzCore",
                      "SceneKit", "CoreText", "Cocoa", "IOSurface", "WebKit", "Virtualization", "Security"]
        binary = work / "Probe"
        subprocess.run([
            "xcrun", "clang++", "-fobjc-arc", "-std=c++20", "-fno-exceptions", "-fno-rtti",
            "-mmacosx-version-min=13.0", "-I" + str(cef), "-ISource", "Tests/BrowserExtensionCompatibilityProbe.mm",
            *objects, "build/libcef_dll_wrapper.a",
            *[arg for framework in frameworks for arg in ("-framework", framework)],
            "-lsqlite3", "-lpthread", "-o", str(binary)], check=True)
        app = work / "Talaria.app"
        subprocess.run(["cp", "-cRp", "build/Talaria.app", str(app)], check=True)
        shutil.copy2(binary, app / "Contents/MacOS/Talaria")
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = "com.talaria.integration." + work.name
        info_path.write_bytes(plistlib.dumps(info))
        subprocess.run(["codesign", "--force", "--sign",
                        os.environ.get("CODE_SIGN_IDENTITY", "Talaria Local Development"),
                        "--entitlements", "Entitlements.plist", str(app)], check=True)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        output = work / "result.json"
        # --load-extension applies only to this diagnostic app and its profile.
        launcher = subprocess.Popen([
            "open", "-n", "-W", str(app), "--args", f"http://127.0.0.1:{server.server_port}/",
            str(work / "profile"), str(output),
            "--load-extension=" + str(ROOT / "Tests/Fixtures/browser-extension-probe")])
        deadline = time.monotonic() + 45
        while not output.exists() and time.monotonic() < deadline:
            if launcher.poll() is not None:
                break
            time.sleep(0.25)
        if not output.exists():
            raise RuntimeError("Desktop extension probe exited or timed out without a report")
        launcher.wait(timeout=20)
        records = json.loads(output.read_text())
        checks = []
        for embedded in (False, True):
            creations = [r for r in records if r["kind"] == "creation" and r["embedded"] == embedded]
            states = [r for r in records if r["kind"] == "extension" and r["embedded"] == embedded]
            if len(creations) != 1 or len(states) != 1:
                raise RuntimeError(f"Expected one creation and one evaluation for embedded={embedded}: {records}")
            raw = states[0]["state"]["extension"]
            state = json.loads(raw) if raw and raw.startswith("{") else {}
            reply = state.get("reply", {})
            sender = reply.get("sender")
            visible = sender is not None and any(tab.get("id") == sender for tab in reply.get("tabs", []))
            checks.append({
                "embedded": embedded,
                "requestedStyle": "chrome",
                "actualStyle": creations[0]["actualStyle"],
                "contentScript": raw is not None,
                "backgroundMessaging": bool(reply) and not state.get("error"),
                "senderVisibleInTabsQuery": visible,
            })
        report = {"checks": checks, "records": records}
        report_path = ROOT / "build/browser-extension-compatibility.json"
        report_path.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(checks, indent=2))
        print("Report:", report_path)
        if not all(checks[0][k] for k in ("contentScript", "backgroundMessaging", "senderVisibleInTabsQuery")):
            raise RuntimeError("Chrome-style control failed; the embedded comparison is inconclusive")
        supported = all(
            checks[1][k] for k in ("contentScript", "backgroundMessaging", "senderVisibleInTabsQuery"))
        if not supported:
            print("LIMITED: embedded tabs lack full Chrome tab-API compatibility.")
        return 0 if supported else 2
    finally:
        if launcher and launcher.poll() is None:
            pid_file = work / "result.json.pid"
            if pid_file.exists():
                pid = int(pid_file.read_text())
                command = subprocess.run(["ps", "-p", str(pid), "-o", "command="], text=True,
                                         capture_output=True).stdout
                if str(work / "Talaria.app/Contents/MacOS/Talaria") in command:
                    os.kill(pid, signal.SIGTERM)
            launcher.terminate()
            launcher.wait(timeout=5)
        if server:
            server.shutdown()
            server.server_close()
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
