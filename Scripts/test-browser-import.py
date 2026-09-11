#!/usr/bin/env python3
"""Launch the signed desktop probe twice; never uses the user's browser profiles."""
import http.server
from pathlib import Path
import subprocess
import tempfile
import threading

cookies = []
class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        cookies.append(self.headers.get('Cookie', ''))
        body = b'<!doctype html><title>Browser import test</title><body>Disposable browser import fixture</body>'
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

with tempfile.TemporaryDirectory(prefix='talaria-import-webkit-', dir='/tmp') as profile:
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        for phase in ('import', 'verify', 'session-end'):
            result = Path(profile) / f'{phase}.txt'
            subprocess.run(['open', '-n', '-W', str(Path('build/BrowserImportProbe.app').resolve()),
                            '--args', profile, f'http://127.0.0.1:{server.server_port}', str(result), phase],
                           check=True, timeout=45)
            assert result.exists(), f'{phase}: desktop probe produced no result'
            assert result.read_text() == 'PASS', (result.read_text(), [str(p.relative_to(profile)) for p in Path(profile).rglob('*') if 'Local Storage' in str(p) or p.name == 'Cookies'])
            assert any('private=imported' in c and 'visible=imported' in c for c in cookies), 'HTTP-only and visible cookies reach the server'
            cookies.clear()
            print(f'PASS: {phase}: WebKit reads local storage and cookies; HTTP-only access and restart persistence verified')
    finally:
        server.shutdown()
