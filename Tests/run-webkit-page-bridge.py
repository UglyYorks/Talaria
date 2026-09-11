#!/usr/bin/env python3
"""Build and launch a disposable desktop WKWebView page-bridge regression app."""
import http.server
import json
from pathlib import Path
import plistlib
import subprocess
import threading
import shutil

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build' / 'webkit-page-bridge-tests'
APP = WORK / 'PageBridgeTests.app'
RESOURCES = APP / 'Contents' / 'Resources'
MACOS = APP / 'Contents' / 'MacOS'
RESOURCES.mkdir(parents=True, exist_ok=True)
MACOS.mkdir(parents=True, exist_ok=True)
for name in ['BrowserOverlayProbe', 'BrowserDocumentFooter', 'BrowserFooterColor', 'BrowserWebKitBridge']:
    shutil.copy2(ROOT / 'Source' / f'{name}.js', RESOURCES)
shutil.copy2(ROOT / 'Vendor/readability/Readability.js', RESOURCES)
with (APP / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleIdentifier':'com.talaria.tests.pagebridge','CFBundleExecutable':'PageBridgeTests','CFBundlePackageType':'APPL','LSUIElement':False}, f)
subprocess.run(['xcrun','clang','-fobjc-arc','-fmodules',f'-fmodules-cache-path={WORK / "module-cache"}','-Wno-unused-parameter','-mmacosx-version-min=13.0','-ISource',
                'Tests/WebKitPageBridgeTests.m','Source/WebKitPageBridge.m','Source/BrowserPageContext.m','Source/PromptBuilder.m','Source/TLBrowserContentColor.m',
                '-framework','Foundation','-framework','AppKit','-framework','WebKit','-framework','ImageIO','-o',str(MACOS / 'PageBridgeTests')], cwd=ROOT, check=True)
subprocess.run(['codesign','--force','--sign','-',str(APP)], check=True)
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        banner = '<div style="position:fixed;bottom:0;left:0;right:0;height:90px;background:rgb(20,10,180)">Cookies</div>'
        body = banner
        if self.path == '/closed':
            body = '<div id="host"></div><script>host.attachShadow({mode:"closed"}).innerHTML=' + json.dumps(banner) + ';</script>'
        if self.path == '/pointer':
            body = banner.replace('position:fixed', 'pointer-events:none;position:fixed')
        if self.path == '/frame':
            body = f'<iframe src="http://localhost:{self.server.server_port}/closed" style="position:fixed;inset:0;width:100%;height:100%;border:0"></iframe>'
        if self.path == '/clear': body = '<p>Normal page</p>' * 20000
        if self.path == '/gradient': body = '<style>body{min-height:0;height:100vh;background:linear-gradient(rgb(180,30,20) 20%,rgb(20,30,150) 80%)}</style>'
        if self.path == '/read': body = '<title>Readable story</title><article><h1>Story</h1><p>This is a readable article with enough text. The page bridge preserves page context for the assistant. ' * 10 + '</p></article>'
        if self.path == '/find': body = f'<p>Needle and <strong>needle</strong> and need<span>le</span>.</p><div hidden>needle</div><iframe src="http://localhost:{self.server.server_port}/find-child"></iframe>'
        if self.path == '/find-child': body = '<p>needle inside another origin</p>'
        if self.path == '/footer': body = '<p>Document footer</p>'
        data = ('<!doctype html><style>body{margin:0;min-height:2000px}</style>' + body).encode()
        self.send_response(200); self.send_header('Content-Type','text/html'); self.end_headers(); self.wfile.write(data)
    def log_message(self, *_): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1',0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
result = WORK / 'results.json'
result.unlink(missing_ok=True)
try:
    subprocess.run(['open','-n','-W','--stdout',str(WORK / 'app.log'),'--stderr',str(WORK / 'app.log'),str(APP),'--args',f'http://127.0.0.1:{server.server_port}',str(result)],check=True,timeout=90)
finally:
    server.shutdown()
results = json.loads(result.read_text())
by_path = {row['path']:row['result'] for row in results}
print(json.dumps(results, indent=2))
for path in ['/fixed','/closed','/pointer','/frame']:
    assert by_path[path]['obstructed'] is True, (path,by_path[path])
assert by_path['/clear']['obstructed'] is False
assert by_path['/gradient']['rgb'] == [20,30,150], by_path['/gradient']
assert by_path['/gradient']['top']['rgb'] == [180,30,20], by_path['/gradient']
assert 'page bridge preserves' in by_path['/read']['text']
assert by_path['/find']['matches'] == [[4,1],[4,2],[4,1]], by_path['/find']
assert by_path['/find']['finding'] is False
assert by_path['/footer']['applied'] is True
assert by_path['/footer']['state']['height'] >= 2070, by_path['/footer']
print('WebKitPageBridgeTests passed')
