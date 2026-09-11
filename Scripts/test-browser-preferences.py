#!/usr/bin/env python3
"""Run the explicitly built desktop probe against a local fixture and isolated profile."""
from browser_test_launcher import launch_browser_test_app
import http.server
import os
import re
from pathlib import Path
import subprocess
import tempfile
import threading
import time

PAYLOAD = bytes((index * 37 + index // 251) % 256 for index in range(64 * 65536))
ETAG = '"talaria-slow-fixture-v1"'
LAST_MODIFIED = 'Sat, 01 Jan 2000 00:00:00 GMT'
REQUESTS = []
REQUEST_LOCK = threading.Lock()

class Fixture(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def do_HEAD(self):
        self.do_GET()
    def do_GET(self):
        if self.path.startswith(('/slow?', '/slow-no-range?')):
            supports_range = self.path.startswith('/slow?')
            start, end = 0, len(PAYLOAD) - 1
            ranged = False
            if supports_range and self.headers.get('Range') and self.headers.get('If-Range', ETAG) in (ETAG, LAST_MODIFIED):
                match = re.fullmatch(r'bytes=(\d+)-(\d*)', self.headers['Range'])
                if not match or int(match[1]) >= len(PAYLOAD) or (match[2] and int(match[2]) < int(match[1])):
                    self.send_response(416)
                    self.send_header('Content-Range', f'bytes */{len(PAYLOAD)}')
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                    return
                start = int(match[1])
                if match[2]: end = min(int(match[2]), end)
                ranged = True
            if self.command == 'GET':
                with REQUEST_LOCK:
                    REQUESTS.append((self.path, start, ranged))
            self.send_response(206 if ranged else 200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="slow.bin"' if supports_range else 'attachment; filename="restart.bin"')
            self.send_header('Content-Length', str(end - start + 1))
            if supports_range:
                self.send_header('Accept-Ranges', 'bytes')
                self.send_header('ETag', ETAG)
                self.send_header('Last-Modified', LAST_MODIFIED)
                if ranged: self.send_header('Content-Range', f'bytes {start}-{end}/{len(PAYLOAD)}')
            self.end_headers()
            if self.command == 'HEAD': return
            try:
                for offset in range(start, end + 1, 65536):
                    self.wfile.write(PAYLOAD[offset:min(offset + 65536, end + 1)])
                    self.wfile.flush()
                    time.sleep(0.05)
            except (BrokenPipeError, ConnectionResetError):
                pass  # Cancelling a download is part of the integration test.
            return
        download = self.path == '/download'
        body = (b'talaria download fixture' if download else b'''<!doctype html><title>scripts off</title><body>Browser settings fixture<script>
        document.title='scripts on:'+getComputedStyle(document.body).fontSize;
        document.cookie='talaria_fixture=yes; SameSite=Lax';
        window.talariaTicks = 0; setInterval(() => window.talariaTicks++, 25);
        </script></body>''')
        self.send_response(200)
        self.send_header('Content-Type', 'application/octet-stream' if download else 'text/html')
        if download:
            self.send_header('Content-Disposition', 'attachment; filename="fixture.txt"')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if self.command != 'HEAD': self.wfile.write(body)
    def log_message(self, *args):
        pass

with tempfile.TemporaryDirectory(prefix='talaria-native-browser-test-', dir='/tmp') as profile:
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = dict(os.environ, TL_WEBKIT_PROFILE_DIR=profile,
               TL_BROWSER_TEST_URL=f'http://127.0.0.1:{server.server_port}')
    app = 'build/BrowserPreferencesProbe.app'
    try:
        launch_browser_test_app(app, env=env, timeout=55)
        with REQUEST_LOCK:
            requests = REQUESTS.copy()
        assert any(path == '/slow?one' and start > 0 and ranged for path, start, ranged in requests), f'Resume must use a nonzero byte Range: {requests}'
        assert sum(path == '/slow-no-range?restart' and start == 0 and not ranged for path, start, ranged in requests) >= 2, f'Nonresumable GET must restart from zero: {requests}'
        print('PASS: native resume requested a byte range; nonresumable GET restarted from zero', flush=True)
        env['TL_BROWSER_TEST_REOPEN'] = '1'
        launch_browser_test_app(app, env=env, timeout=55)
    finally:
        server.shutdown()
