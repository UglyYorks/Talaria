#!/usr/bin/env python3
"""Launch the real native workspace with a disposable page/profile."""
import http.server
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import sys
import threading

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'build/BrowserPopupTabTests.app'
resources = APP / 'Contents/Resources'
macos = APP / 'Contents/MacOS'
resources.mkdir(parents=True, exist_ok=True)
macos.mkdir(parents=True, exist_ok=True)
shutil.copy2(ROOT / 'build/BrowserPopupTabTests', macos)
for name in ['BrowserOverlayProbe', 'BrowserDocumentFooter', 'BrowserFooterColor', 'BrowserWebKitBridge']:
    shutil.copy2(ROOT / 'Source' / f'{name}.js', resources)
shutil.copy2(ROOT / 'Vendor/readability/Readability.js', resources)
with (APP / 'Contents/Info.plist').open('wb') as file:
    plistlib.dump({'CFBundleIdentifier': 'com.talaria.tests.popuptab',
                  'CFBundleExecutable': 'BrowserPopupTabTests', 'CFBundlePackageType': 'APPL'}, file)
subprocess.run(['codesign', '--force', '--sign', '-', str(APP)], check=True)
class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        data = b'<!doctype html><title>Popup destination</title><p>Popup destination fixture</p>'
        self.send_response(200); self.send_header('Content-Type', 'text/html'); self.end_headers(); self.wfile.write(data)
    def log_message(self, *_): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='talaria-popup-tab-', dir='/tmp') as profile:
        log = ROOT / 'build/popup-tab-test.log'
        log.unlink(missing_ok=True)
        env = dict(os.environ, TL_WEBKIT_PROFILE_DIR=profile)
        subprocess.run(['open', '-n', '-W', '--env', f'TL_WEBKIT_PROFILE_DIR={profile}',
                        '--stdout', str(log), '--stderr', str(log), str(APP), '--args',
                        f'http://127.0.0.1:{server.server_port}', f'{profile}/test.sqlite', *(['--inspect'] if '--inspect' in sys.argv else [])],
                       env=env, check=True, timeout=50)
        output = log.read_text()
        print(output)
        assert 'BrowserPopupTabTests passed' in output and 'FAIL:' not in output
finally:
    server.shutdown()
