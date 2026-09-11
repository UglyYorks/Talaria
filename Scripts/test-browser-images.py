#!/usr/bin/env python3
"""Exercise image menus, authenticated cached resources and native saves in WebKit."""
from browser_test_launcher import launch_browser_test_app
import http.server
import os
from pathlib import Path
import subprocess
import tempfile
import threading

PNG = Path('assets/browser-bookmarks/github.png').read_bytes()
GIF = bytes.fromhex('47494638396101000100800000000000ffffff21ff0b4e45545343415045322e300301000000' + '21f904000a0000002c0000000001000100000202440100' * 2 + '3b')
SVG = b'<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><circle cx="50" cy="50" r="40" fill="purple"/></svg>'
IMAGES = {'/image.png': ('image/png', PNG), '/animation.gif': ('image/gif', GIF), '/vector.svg': ('image/svg+xml', SVG)}

class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/movie.mov':
            mime, body = 'video/quicktime', Path(__file__).resolve().parents[1].joinpath('Tests/Fixtures/attachment-preview.mov').read_bytes()
        elif self.path in IMAGES:
            if 'image_test=yes' not in self.headers.get('Cookie', ''):
                self.send_error(403)
                return
            mime, body = IMAGES[self.path]
        else:
            mime, body = 'text/html', b'''<!doctype html><title>Image menu test</title><body>
            <h1>Right-click an image</h1><img src="/image.png" width="240"><img src="/animation.gif" width="120"><img src="/vector.svg"><img id="blob" width="120">
            <script>document.cookie='image_test=yes;path=/';
            (async()=>{const blob=await (await fetch('/image.png')).blob();document.getElementById('blob').src=URL.createObjectURL(blob);
            await Promise.all(Array.from(document.images).map(i=>i.decode().catch(()=>{})));document.title='images ready';})();</script></body>'''
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Set-Cookie', 'image_test=yes; Path=/; SameSite=Lax')
        self.send_header('Cache-Control', 'private, max-age=3600')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args): pass

if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='talaria-image-test-', dir='/tmp') as profile:
        for path, (_, data) in IMAGES.items(): Path(profile, path[1:]).write_bytes(data)
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        env = dict(os.environ, TL_WEBKIT_PROFILE_DIR=profile, TL_BROWSER_TEST_URL=f'http://127.0.0.1:{server.server_port}')
        try: launch_browser_test_app('build/BrowserImageProbe.app', env=env, timeout=50)
        finally: server.shutdown()
