#!/usr/bin/env python3
"""Run native link menus, downloads and tab groups against a local fixture."""
import http.server
import os
from pathlib import Path
import subprocess
import tempfile
import threading

class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/linked-image.svg':
            image = b'<svg xmlns="http://www.w3.org/2000/svg" width="240" height="160"><rect width="240" height="160" fill="teal"/><circle cx="120" cy="80" r="50" fill="coral"/></svg>'
            self.send_response(200)
            self.send_header('Content-Type', 'image/svg+xml')
            self.send_header('Content-Length', str(len(image)))
            self.end_headers()
            self.wfile.write(image)
            return
        download = self.path.startswith('/download')
        body = b'linked file fixture' if download else b'''<!doctype html><title>Link menu fixture</title>
        <h1>Right-click a link</h1><p><a href="/one">First link</a></p><p><a href="/two">Second link</a></p>
        <p><a href="/download">Downloadable file</a></p><p><a href="mailto:test@example.com">Mail link</a></p><a href="/one"><img src="/linked-image.svg" alt="Linked image"></a>'''
        self.send_response(200)
        self.send_header('Content-Type', 'application/octet-stream' if download else 'text/html')
        if download: self.send_header('Content-Disposition', 'attachment; filename="linked-file.txt"')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args): pass

if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='talaria-link-test-', dir='/tmp') as profile:
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        env = dict(os.environ, TL_CHROMIUM_PROFILE_DIR=profile, TL_BROWSER_TEST_URL=f'http://127.0.0.1:{server.server_port}')
        try: subprocess.run([str(Path('build/BrowserLinkProbe.app/Contents/MacOS/Talaria').resolve())], env=env, timeout=55, check=True)
        finally: server.shutdown()
