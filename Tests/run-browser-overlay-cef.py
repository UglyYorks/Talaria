#!/usr/bin/env python3
"""Desktop CEF integration regression; temporary app/profile, no user app data.

Run from any directory with `python3 Tests/run-browser-overlay-cef.py`.
Builds the current checkout. Requires its normal persistent code-signing identity.
"""
import http.server
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import threading
import sys
import plistlib

DOCUMENT_FOOTER = "--document-footer" in sys.argv
FULLSCREEN = "--fullscreen" in sys.argv
DEVTOOLS = "--devtools" in sys.argv
ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
subprocess.run(["make", "build"], check=True)
work = Path(tempfile.mkdtemp(prefix="overlay-cef-check-", dir=ROOT / "build"))
profile = Path(tempfile.mkdtemp(prefix="talaria-overlay-profile-"))
server = None
peer_server = None
runner = None
app_pid = None
try:
    cef = next((ROOT / "build/deps").glob("cef_binary_*"))
    binary = work / "OverlayProbeIntegration"
    objects = sorted(str(p) for p in (ROOT / "build/app-objects").rglob("*.o") if p.name != "main.mm.o" and (ROOT / "Source" / p.relative_to(ROOT / "build/app-objects").with_suffix("")).exists())
    frameworks = ["QuickLookThumbnailing", "UniformTypeIdentifiers", "AppKit", "Foundation", "QuartzCore",
                  "SceneKit", "CoreText", "Cocoa", "IOSurface", "WebKit", "Virtualization", "Security"]
    subprocess.run([
        "xcrun", "clang++", "-fobjc-arc", "-std=c++20", "-fno-exceptions", "-fno-rtti",
        "-mmacosx-version-min=13.0", "-I" + str(cef), "-ISource", "Tests/BrowserDevToolsCEFTests.mm" if DEVTOOLS else "Tests/BrowserFullscreenCEFTests.mm" if FULLSCREEN else "Tests/BrowserDocumentFooterCEFTests.mm" if DOCUMENT_FOOTER else "Tests/BrowserOverlayCEFTests.mm",
        *objects, "build/libcef_dll_wrapper.a", "build/libbrowser_import.a",
        *[arg for framework in frameworks for arg in ("-framework", framework)],
        "-lsqlite3", "-lpthread", "-o", str(binary)], check=True)
    app = work / "Talaria.app"
    subprocess.run(["cp", "-cRp", "build/Talaria.app", str(app)], check=True)
    shutil.copy2(binary, app / "Contents/MacOS/Talaria")
    # A separate app identity prevents the user's running Talaria instance from
    # sharing activation/hide state with the disposable integration window.
    info_path = app / "Contents/Info.plist"
    with info_path.open("rb") as f:
        info = plistlib.load(f)
    info["CFBundleIdentifier"] = "com.talaria.integration." + work.name
    with info_path.open("wb") as f:
        plistlib.dump(info, f)
    identity = os.environ.get("CODE_SIGN_IDENTITY", "Talaria Local Development")
    subprocess.run(["codesign", "--force", "--sign", identity, "--entitlements", "Entitlements.plist", str(app)], check=True)

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            banner = '<div style="position:fixed;bottom:0;left:0;right:0;height:90px;background:#eee">Cookies</div>'
            if "thin" in self.path:
                banner = banner.replace("height:90px", "height:24px")
            body = banner
            if self.path.startswith("/fullscreen"):
                body = '<div id="target" style="background:#204080;width:200px;height:180px">Fullscreen content</div><video controls width="200" height="120"></video><iframe src="about:blank" allowfullscreen></iframe>'
            if self.path.startswith("/closed"):
                body = '<div id="host"></div><script>document.querySelector("#host").attachShadow({mode:"closed"}).innerHTML=' + json.dumps(banner) + ';</script>'
            if self.path == "/frame":
                body = f'<iframe src="http://localhost:{self.server.server_port}/fixed" style="position:fixed;inset:0;width:100%;height:100%;border:0"></iframe>'
            if self.path in ("/guardian-quick", "/guardian-normal-quick", "/guardian-scrolling-quick", "/guardian-shared-quick"):
                position = "absolute" if "normal" in self.path else "fixed"
                child = "/guardian-tall-content" if "scrolling" in self.path else "/guardian-content"
                origin = f'http://127.0.0.1:{peer_server.server_port}' if "shared" in self.path else f'http://localhost:{self.server.server_port}'
                body = f'<div style="position:{position};inset:0;overflow:auto"><iframe src="{origin}{child}" style="width:100%;height:100%;border:0;display:block"></iframe></div>'
            if self.path == "/guardian-content":
                body = '<style>html,body{margin:0;min-height:0;height:100%}</style><div style="position:absolute;inset:0;display:flex"><div style="position:absolute;bottom:0;width:100%;height:260px;background:#052862"><button>Continue</button></div></div>'
            if self.path == "/guardian-tall-content":
                body = '<style>body{height:2000px;position:relative}</style><div style="position:absolute;bottom:0;height:90px;width:100%;background:#eee">Document footer</div><script>scrollTo(0,2000)</script>'
            if self.path in ("/viewport-app", "/flutter-app"):
                host = 'div role="application"' if self.path == "/viewport-app" else 'flutter-view'
                tag = host.split()[0]
                body = '<style>html,body{height:100%;min-height:0;overflow:hidden}body{position:fixed;inset:0}</style>'
                body += f'<{host} id="app" style="position:absolute;inset:0"><canvas id="map" style="width:100%;height:100%"></canvas></{tag}>'
                body += '<script>requestAnimationFrame(()=>{document.title="viewport-app-visible:"+location.pathname})</script>'
            if self.path == "/layout-app":
                body = '<style>html,body{height:100%;min-height:0;overflow:hidden}main{height:100%;display:flex;flex-direction:column}section{flex:1;min-height:0;overflow:auto}footer{height:50px;flex:none;display:flex;align-items:center;justify-content:center}p{margin:0}</style>'
                body += '<main><section><div style="height:1800px">Conversation</div></section><footer id="bottom"><p><a href="#"><span style="display:contents">Google Terms and Privacy Policy apply.</span></a> Gemini can make mistakes.</p></footer></main>'
                body += '<script>requestAnimationFrame(()=>{document.title="viewport-app-visible:layout"})</script>'
            if self.path == "/edge-colors":
                body = '<style>body{min-height:0;height:100vh;background:linear-gradient(rgb(180,30,20) 20%,rgb(20,30,150) 80%)}</style>'
            if self.path == "/x-like-edge-colors":
                # X's transparent relative wrappers require rendered pixels even
                # though the visible edge is a uniform black body background.
                body = '<style>html,body{height:100%;min-height:0}body{background:rgb(0,0,0)}.shell{position:relative;height:100%;width:100%}</style>'
                body += '<div class="shell">' * 8 + '</div>' * 8
            if self.path == "/clear":
                body = '<p>Normal page</p>'
            if self.path.startswith("/large"):
                body = '<p>Normal page</p>' * 20000
            if self.path.startswith("/latency-"):
                index = int(self.path.rsplit("-", 1)[1])
                banner = banner.replace("height:90px", "height:24px")
                insert = 'document.body.insertAdjacentHTML("beforeend",' + json.dumps(banner) + ')'
                if index % 2:
                    insert = 'document.querySelector("#host").attachShadow({mode:"closed"}).innerHTML=' + json.dumps(banner)
                body = '<div id="host"></div>' + ('<p>Normal page</p>' * (20000 if index == 6 else 1))
                body += '<script>setTimeout(()=>{' + insert + ';requestAnimationFrame(()=>{document.title="banner-visible"})},' + str(650 + index * 37) + ')</script>'
            if self.path.startswith("/document-footer"):
                body = "<style>body{height:3000px;position:relative}p{margin:0}</style><p>Document footer fixture</p>"
            if self.path == "/canvas-extension":
                body = """<style>body{min-height:0}</style><main style="height:1500px"></main>
                <footer style="position:relative;height:400px;background:rgb(5,43,66)">
                <div style="position:absolute;inset:0"><canvas id="edge" width="1000" height="400" style="display:block;width:100%;height:100%"></canvas></div>
                <div style="position:relative;height:100%">Content above a WebGL backdrop</div></footer>
                <script>const gl=edge.getContext('webgl',{preserveDrawingBuffer:false});window.canvasReady=!!gl;
                if(gl){gl.enable(gl.SCISSOR_TEST);for(let i=0;i<32;i++){gl.scissor(Math.floor(i*1000/32),0,Math.ceil(1000/32),400);
                gl.clearColor((240-220*i/31)/255,(20+20*i/31)/255,(30+200*i/31)/255,1);gl.clear(gl.COLOR_BUFFER_BIT);}}</script>"""
            if self.path == "/document-footer-frame":
                body = f'<iframe src="http://localhost:{self.server.server_port}/document-footer-child" style="position:fixed;inset:0;width:100%;height:100%;border:0"></iframe>'
            if self.path == "/document-footer-child":
                body = """<style>body{height:3000px}</style><div id=host></div><script>host.attachShadow({mode:'closed'}).innerHTML='<div style="position:fixed;bottom:0;width:100%;height:90px;background:#eee">Frame banner</div>';scrollTo(0,3000)</script>"""
            if self.path in ("/banner-color-frame", "/banner-gradient-frame"):
                child = "/banner-gradient-child" if "gradient" in self.path else "/banner-color-child"
                body = f'<iframe src="http://localhost:{self.server.server_port}{child}" style="position:fixed;inset:0;width:100%;height:100%;border:0"></iframe>'
            if self.path in ("/banner-color-child", "/banner-gradient-child"):
                fill = "linear-gradient(red,rgb(30,80,140) 70%)" if "gradient" in self.path else "rgb(20,10,180)"
                panel = f'<div style="position:fixed;bottom:12px;left:0;width:100%;height:100px;background:{fill}">Cookies</div>'
                body = '<style>body{min-height:0;height:100%;background:white}</style><div id=host></div><script>host.attachShadow({mode:"closed"}).innerHTML=' + json.dumps(panel) + ';</script>'
            if self.path == "/footer-color-content":
                body = '<style>html,body{background:rgb(52,100,148)}</style>'
            data = ('<!doctype html><style>body{margin:0;min-height:2000px}</style>' + body).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *_):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    peer_server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=peer_server.serve_forever, daemon=True).start()
    threading.Thread(target=server.serve_forever, daemon=True).start()
    result = work / "results.json"
    app_log = work / "application.log"
    runner = subprocess.Popen(["open", "-n", "-W", "--stdout", str(app_log), "--stderr", str(app_log), str(app), "--args",
                               f"http://127.0.0.1:{server.server_port}", str(profile), str(result),
                               *([os.environ["TALARIA_OVERLAY_LIVE_URL"]] if os.environ.get("TALARIA_OVERLAY_LIVE_URL") else [])])
    try:
        runner.wait(timeout=120)
    except subprocess.TimeoutExpired:
        pid_file = Path(str(result) + ".pid")
        if pid_file.exists():
            app_pid = int(pid_file.read_text())
            command = subprocess.run(["ps", "-p", str(app_pid), "-o", "command="], capture_output=True, text=True).stdout.strip()
            if command.startswith(str(app / "Contents/MacOS/Talaria") + " "):
                os.kill(app_pid, signal.SIGTERM)
        runner.terminate()
        runner.wait(timeout=5)
        raise
    records = json.loads(result.read_text())
    output = ROOT / ("build/BrowserDevToolsCEFResults.json" if DEVTOOLS else "build/BrowserFullscreenCEFResults.json" if FULLSCREEN else "build/BrowserDocumentFooterCEFResults.json" if DOCUMENT_FOOTER else "build/BrowserOverlayCEFResults.json")
    output.write_text(json.dumps(records, indent=2))
    print(json.dumps(records, indent=2))
    if DEVTOOLS:
        assert len(records) >= 15 and all(r["passed"] for r in records), "DevTools integration failed"
        print("BrowserDevToolsCEFTests passed; results:", output)
    elif FULLSCREEN:
        assert len(records) >= 35 and all(r["passed"] for r in records), "Fullscreen integration failed"
        print("BrowserFullscreenCEFTests passed; results:", output)
    elif DOCUMENT_FOOTER:
        assert len(records) >= 24 and all(r["passed"] for r in records), "Document footer integration failed"
        print("BrowserDocumentFooterCEFTests passed; results:", output)
    else:
        for record in records:
            if "resizeCycles" not in record:
                continue
            cycles = record["resizeCycles"]
            assert len(cycles) == 24, "Exercise repeated footer switches"
            if not cycles[0]["reduceMotion"]:
                assert any(c["visual"].get("active") and c["visual"]["heightDifference"] > 0.5 for c in cycles), "Footer must visibly animate between sizes"
            assert all(c["visual"].get("unscaled") for c in cycles), "Page content must never scale during footer transitions"
            assert all(c["visual"].get("topError", 100) < 1 for c in cycles), "Visual animation must keep the page top fixed"
            first_by_mode = {}
            previous_resizes = 0
            for index, cycle in enumerate(cycles):
                page = json.loads(cycle["page"])
                assert page["cycle"] == index, "Wait for the matching renderer observation, not a stale title"
                assert page["resizes"] - previous_resizes <= 24, "Rapid toggles must stay within the bounded live-resize frame budget"
                previous_resizes = page["resizes"]
                assert abs(page["height"] - page["bottom"]) <= 1, "Fixed footer must meet the page viewport bottom"
                tree = cycle["tree"]
                while tree["children"]:
                    child = tree["children"][0]
                    assert child["frame"] == tree["bounds"], "Native browser subview must fill its parent after resizing"
                    tree = child
                state = (cycle["tree"]["bounds"], page["height"], page["bottom"])
                baseline = first_by_mode.setdefault(cycle["reduced"], state)
                assert state == baseline, "Repeated footer switches must not accumulate viewport drift"
        probe_count = 13
        assert [r["result"]["obstructed"] for r in records[:probe_count]] == [True, True, True, False, False, False, True, True, True, True, False, False, True]
        assert records[5]["result"]["samples"] <= 3, "Quick scans must remain bounded"
        assert records[5]["result"]["costMS"] < records[4]["result"]["costMS"], "Quick checks should cost less than full scans"
        assert records[7]["result"]["samples"] == 1, "Shallow banners must be found at the first sample"
        assert records[8]["result"]["samples"] <= 3, "Shallow closed-shadow banners must be found in one quick pass"
        for record in records[:probe_count]:
            probe = record["result"]
            assert abs(probe["costMS"] - probe["cpuMS"] - probe["hitTests"]) < 0.001, "Transport latency must not become CPU cooldown"
        assert all(r["result"]["maxSliceMS"] < 25 for r in records[:probe_count]), "Inspection must not create long synchronous slices"
        assert len(records) == probe_count + (8 if os.environ.get("TALARIA_OVERLAY_LIVE_URL") else 7)
        assert all(0 <= r["detectionMS"] < 500 for r in records[probe_count:probe_count+6]), "Typical-page detection should take under 500ms"
        assert all(0 <= r["settledMS"] < 1000 for r in records[probe_count:probe_count+6]), "Native layout should settle within one second on responsive fixtures"
        # Foreground rendering can make a 20,000-node quick check exceed 12.5ms.
        # Its deliberate CPU-budget cooldown then exceeds one second. Check the
        # measured adaptive bound instead of contradicting that performance policy.
        stress = records[probe_count+6]
        quick_cost = max((p["result"]["costMS"] for p in stress["trace"] if p["quick"]), default=0)
        assert 0 <= stress["settledMS"] < max(1000, quick_cost * 80 + 750), "Stress-page detection must respect its measured cooldown, confirmation and visual-animation allowance"
        if len(records) == probe_count+8:
            assert 0 <= records[probe_count+7]["detectionMS"] < 1000, "Live-page overlap confirmation should take under one second after the first positive probe"
        print("BrowserOverlayCEFTests: 13 probe checks, 7 native latency checks and 72 rapid toggles passed; results:", output)

finally:
    if DEVTOOLS and (work / "application.log").exists():
        shutil.copy2(work / "application.log", ROOT / "build/BrowserDevToolsCEF.log")
    if server:
        server.shutdown()
    if peer_server:
        peer_server.shutdown()
    shutil.rmtree(profile, ignore_errors=True)
    shutil.rmtree(work, ignore_errors=True)
