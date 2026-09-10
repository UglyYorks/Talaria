#!/usr/bin/env python3
"""Desktop regression for bounded image reads and per-redirect cookie scope."""
import http.server
import json
from pathlib import Path
import plistlib
import subprocess
import threading
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/webkit-image-loader-tests'
APP=WORK/'ImageLoaderTests.app'
MACOS=APP/'Contents/MacOS'
MACOS.mkdir(parents=True,exist_ok=True)
with (APP/'Contents/Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleIdentifier':'com.talaria.tests.imageloader','CFBundleExecutable':'ImageLoaderTests','CFBundlePackageType':'APPL','LSUIElement':True},f)
subprocess.run(['xcrun','clang','-fobjc-arc','-ISource','Tests/WebKitImageLoaderTests.m','Source/WebKitImageLoader.m','-framework','Foundation','-framework','AppKit','-o',str(MACOS/'ImageLoaderTests')],cwd=ROOT,check=True)
subprocess.run(['codesign','--force','--sign','-',str(APP)],check=True)
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path=='/redirect':
            self.send_response(302);self.send_header('Location',f'http://localhost:{self.server.server_port}/direct');self.end_headers();return
        self.send_response(200)
        if self.path=='/too-large':self.send_header('Content-Length',str(128*1024*1024+1))
        self.end_headers()
        if self.path!='/too-large':self.wfile.write((self.headers.get('Cookie') or '').encode())
    def log_message(self,*_):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
result=WORK/'results.json';result.unlink(missing_ok=True)
try:subprocess.run(['open','-n','-W',str(APP),'--args',f'http://127.0.0.1:{server.server_port}',str(result)],check=True,timeout=45)
finally:server.shutdown()
rows=json.loads(result.read_text());by_path={row['path']:row for row in rows}
assert by_path['/direct']['data']=='source=fixture',rows
assert by_path['/redirect']['data']=='target=fixture',rows
assert by_path['/too-large']['failed'],rows
assert by_path['/unknown-length']['data']=='source=fixture',rows
assert not by_path['/unknown-length']['failed'],rows
print('WebKitImageLoaderTests passed')
