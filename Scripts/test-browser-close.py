#!/usr/bin/env python3
"""Close retained and unresponsive desktop pages playing synthetic audio."""
from browser_test_launcher import launch_browser_test_app
import http.server
import io
import math
import os
import struct
import tempfile
import threading
import wave

buffer = io.BytesIO()
with wave.open(buffer, 'wb') as audio:
    audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(8000)
    audio.writeframes(b''.join(struct.pack('<h', int(100 * math.sin(2 * math.pi * 180 * i / 8000))) for i in range(8000)))
class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/tone.wav':
            body, kind = buffer.getvalue(), 'audio/wav'
        elif self.path == '/survivor':
            body, kind = b'<!doctype html><title>Survivor</title><p>Other open tab</p>', 'text/html'
        else:
            kind = 'text/html'
            body = b'''<!doctype html><title>Close audio regression</title><audio id="audio" src="/tone.wav" loop></audio>
            <script>(async()=>{await audio.play();window.context=new AudioContext();const oscillator=context.createOscillator();
            const gain=context.createGain();gain.gain.value=.003;oscillator.connect(gain).connect(context.destination);
            oscillator.start();await context.resume();window.audioReady=true;})();</script>'''
        self.send_response(200); self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *_): pass
with tempfile.TemporaryDirectory(prefix='talaria-close-test-', dir='/tmp') as profile:
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        launch_browser_test_app('build/BrowserCloseProbe.app', env=dict(os.environ,
            TL_WEBKIT_PROFILE_DIR=profile, TL_BROWSER_TEST_URL=f'http://127.0.0.1:{server.server_port}/'), timeout=50)
    finally:
        server.shutdown()
