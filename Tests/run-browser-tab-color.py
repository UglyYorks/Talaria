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
APP = ROOT / 'build/BrowserTabColorTests.app'
resources = APP / 'Contents/Resources'
macos = APP / 'Contents/MacOS'
resources.mkdir(parents=True, exist_ok=True)
macos.mkdir(parents=True, exist_ok=True)
shutil.copy2(ROOT / 'build/BrowserTabColorTests', macos)
for name in ['BrowserOverlayProbe', 'BrowserDocumentFooter', 'BrowserFooterColor', 'BrowserWebKitBridge']:
    shutil.copy2(ROOT / 'Source' / f'{name}.js', resources)
shutil.copy2(ROOT / 'Vendor/readability/Readability.js', resources)
with (APP / 'Contents/Info.plist').open('wb') as file:
    plistlib.dump({'CFBundleIdentifier': 'com.talaria.tests.tabcolor',
                  'CFBundleExecutable': 'BrowserTabColorTests', 'CFBundlePackageType': 'APPL'}, file)
subprocess.run(['codesign', '--force', '--sign', '-', str(APP)], check=True)
class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        data = b'''<!doctype html><title>Tab color fixture</title><style>
        html,body{margin:0}body{height:3000px;background:repeating-linear-gradient(90deg,#064a88 0 6px,#39b9b0 6px 12px)}
        h1{margin:0;padding:60px;color:white}p{background:white;padding:40px}</style>
        <h1>Page edge color fixture</h1><p>Scroll this page to inspect the tab color.</p>'''
        if '--white' in sys.argv:
            data = data.replace(b'repeating-linear-gradient(90deg,#064a88 0 6px,#39b9b0 6px 12px)', b'rgb(248,248,244)')
        if self.path.startswith('/large-canvas'):
            data = b'''<!doctype html><title>Large canvas color fixture</title>
            <style>html,body{margin:0}canvas{position:fixed;inset:0;width:100%;height:100%}</style><canvas></canvas>
            <script>const c=document.querySelector('canvas');c.width=innerWidth*devicePixelRatio;c.height=innerHeight*devicePixelRatio;
            const ctx=c.getContext('2d'),pixels=ctx.createImageData(c.width,c.height),bytes=new Uint8Array(pixels.data.buffer);
            for(let i=0;i<bytes.length;i+=65536)crypto.getRandomValues(bytes.subarray(i,Math.min(i+65536,bytes.length)));
            for(let i=3;i<bytes.length;i+=4)bytes[i]=255;
            ctx.putImageData(pixels,0,0);ctx.fillStyle='rgb(14,47,126)';ctx.fillRect(0,0,c.width,32);</script>'''
        self.send_response(200); self.send_header('Content-Type', 'text/html'); self.end_headers(); self.wfile.write(data)
    def log_message(self, *_): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='talaria-tab-color-', dir='/tmp') as profile:
        log = ROOT / 'build/tab-color-test.log'
        log.unlink(missing_ok=True)
        env = dict(os.environ, TL_WEBKIT_PROFILE_DIR=profile)
        subprocess.run(['open', '-n', '-W', '--env', f'TL_WEBKIT_PROFILE_DIR={profile}',
                        '--stdout', str(log), '--stderr', str(log), str(APP), '--args',
                        f'http://127.0.0.1:{server.server_port}', f'{profile}/test.sqlite', *(['--inspect'] if '--inspect' in sys.argv else [])],
                       env=env, check=True, timeout=50)
        output = log.read_text()
        print(output)
        assert 'BrowserTabColorTests passed' in output and 'FAIL:' not in output
finally:
    server.shutdown()
