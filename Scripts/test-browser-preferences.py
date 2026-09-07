#!/usr/bin/env python3
"""Run the explicitly built desktop probe against a local fixture and isolated profile."""
import http.server
import os
from pathlib import Path
import subprocess
import tempfile
import threading

class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        download = self.path == '/download'
        body = (b'talaria download fixture' if download else b'''<!doctype html><title>scripts off</title><body>Browser settings fixture<script>
        document.title='scripts on:'+getComputedStyle(document.body).fontSize+':'+navigator.doNotTrack;
        document.cookie='talaria_fixture=yes; SameSite=Lax';
        window.talariaTicks = 0; setInterval(() => window.talariaTicks++, 25);
        </script></body>''')
        self.send_response(200)
        self.send_header('Content-Type', 'application/octet-stream' if download else 'text/html')
        if download:
            self.send_header('Content-Disposition', 'attachment; filename="fixture.txt"')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

with tempfile.TemporaryDirectory(prefix='talaria-native-browser-test-', dir='/tmp') as profile:
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = dict(os.environ, TL_CHROMIUM_PROFILE_DIR=profile,
               TL_BROWSER_TEST_URL=f'http://127.0.0.1:{server.server_port}')
    executable = Path('build/BrowserPreferencesProbe.app/Contents/MacOS/Talaria').resolve()
    try:
        subprocess.run([str(executable)], env=env, timeout=55, check=True)
        env['TL_BROWSER_TEST_REOPEN'] = '1'
        subprocess.run([str(executable)], env=env, timeout=55, check=True)
    finally:
        server.shutdown()
