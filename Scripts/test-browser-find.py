#!/usr/bin/env python3
"""Launch the find integration probe as a desktop app with an isolated profile."""
import http.server
import json
from pathlib import Path
import subprocess
import tempfile
import threading

class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'<!doctype html><title>Find fixture</title><p>needle NEEDLE needle unique</p>'
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

with tempfile.TemporaryDirectory(prefix='talaria-find-', dir='/tmp') as directory:
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    result = Path(directory) / 'results.json'
    try:
        subprocess.run(['open', '-n', '-W', str(Path('build/BrowserFindProbe.app').resolve()), '--stderr', str(Path(directory) / 'stderr.log'), '--args',
                        f'http://127.0.0.1:{server.server_port}', str(Path(directory) / 'profile'), str(result)],
                       timeout=60, check=True)
        results = json.loads(result.read_text())
        if not all(entry['passed'] for entry in results):
            print((Path(directory) / 'stderr.log').read_text()[-8000:])
        for entry in results:
            print(('PASS: ' if entry['passed'] else 'FAIL: ') + entry['name'])
        assert results and all(entry['passed'] for entry in results)
    finally:
        server.shutdown()
