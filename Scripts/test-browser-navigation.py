#!/usr/bin/env python3
"""Exercise a real desktop link navigation while the new document cannot paint."""
from collections import Counter
from browser_test_launcher import launch_browser_test_app
import http.server
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time

requests = Counter()

class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        requests[self.path] += 1
        kind = 'text/html'
        if self.path == '/next':
            time.sleep(.3)
            body = b'<!doctype html><link rel="stylesheet" href="/delayed.css"><title>Destination</title><body>Destination page</body>'
        elif self.path == '/delayed.css':
            time.sleep(1.2)
            body = b'body { background: #1b5944; color: white; }'
            kind = 'text/css'
        elif self.path == '/slow':
            time.sleep(2)
            body = b'<!doctype html><body>Slow page</body>'
        elif self.path == '/blank':
            body = b'<!doctype html><html></html>'
        else:
            body = (f'<!doctype html><title>Source</title><style>body{{background:#153d70;color:white}}'
                    f'a{{position:absolute;left:16px;top:16px;padding:24px;color:white}}</style>'
                    f'<a href="http://localhost:{self.server.server_port}/next">Next page</a>').encode()
        self.send_response(200)
        self.send_header('Content-Type', kind)
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Closing the tab deliberately cancels /slow.

    def log_message(self, *args):
        pass

with tempfile.TemporaryDirectory(prefix='talaria-native-navigation-test-', dir='/tmp') as profile:
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    env = dict(os.environ, TL_WEBKIT_PROFILE_DIR=profile,
               TL_BROWSER_TEST_URL=f'http://127.0.0.1:{server.server_port}')
    app = 'build/BrowserNavigationProbe.app'
    try:
        launch_browser_test_app(app, env=env, timeout=25)
        assert requests['/start'] == 1, requests
        assert requests['/next'] == 1, requests
        print('PASS: the source and destination each receive one page request')
    finally:
        server.shutdown()
