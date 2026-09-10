#!/usr/bin/env python3
"""Run the signed IncognitoBrowserProbe against loopback fixtures and inspect disk residue."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import subprocess
import tempfile
import threading

class Fixture(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(b'<html><title>Privacy fixture</title><body>Privacy fixture</body></html>')

root = Path(__file__).resolve().parents[1]
server = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='talaria-native-browser-test-', dir='/tmp') as profile:
        env = dict(os.environ, TL_CHROMIUM_PROFILE_DIR=profile, TL_BROWSER_TEST_URL=f'http://127.0.0.1:{server.server_port}')
        subprocess.run([str(root/'build/IncognitoBrowserProbe.app/Contents/MacOS/Talaria')], env=env, check=True, timeout=50)
        for file in Path(profile).rglob('*'):
            if file.is_file() and not file.is_symlink():
                assert b'TALARIA_INCOGNITO_MARKER' not in file.read_bytes(), f'Private data written to {file.name}'
        print('PASS: no private cookie/localStorage marker persisted to disk')
finally:
    server.shutdown()
