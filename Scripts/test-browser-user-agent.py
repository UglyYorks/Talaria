#!/usr/bin/env python3
"""Verify Safari identity in real native WebKit requests, frames and popups."""
import http.server
import json
import os
from pathlib import Path
import plistlib
import tempfile
import threading
from urllib.parse import urlsplit
from browser_test_launcher import launch_browser_test_app, require_unlocked_desktop

ROOT = Path(__file__).resolve().parents[1]
requests = []


class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        ua = self.headers.get('User-Agent')
        requests.append({'path': path, 'userAgent': ua})
        if path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/regular')
            self.end_headers()
            return
        kind = 'text/html'
        if path == '/echo':
            body, kind = json.dumps(ua), 'application/json'
        elif path == '/worker.js':
            body, kind = 'postMessage(navigator.userAgent);', 'text/javascript'
        elif path == '/frame':
            body = "<script>parent.postMessage({frameUA:navigator.userAgent,frameOrigin:location.origin},'*')</script>"
        elif path == '/popup':
            body = "<script>opener.postMessage({popupUA:navigator.userAgent},location.origin)</script>"
        elif path == '/baseline':
            body = '<!doctype html><title>Default WebKit identity</title>'
        else:
            body = '''<!doctype html><script>
            window.uaProbe={initialUA:navigator.userAgent,origin:location.origin};
            addEventListener('message',e=>{
              if(e.data.frameUA && e.source===document.querySelector('iframe').contentWindow)Object.assign(uaProbe,e.data);
              if(e.data.popupUA && e.source===window.testPopup)Object.assign(uaProbe,e.data);
            });
            </script><button style="position:absolute;left:10px;top:10px;width:140px;height:50px" onclick="
              window.testPopup=window.open('','ua-probe');
              uaProbe.blankPopupUA=testPopup.navigator.userAgent;testPopup.location='/popup';">Open popup</button>
            <iframe src="http://localhost:PORT/frame" style="position:absolute;top:100px"></iframe>
            <script>
            const worker=new Worker('/worker.js');worker.onmessage=e=>{uaProbe.workerUA=e.data;worker.terminate()};
            fetch('/echo').then(r=>r.json()).then(value=>uaProbe.fetchUA=value);
            const timer=setInterval(()=>{if(uaProbe.frameUA&&uaProbe.fetchUA&&uaProbe.workerUA){
              uaProbe.currentUA=navigator.userAgent;uaProbe.appVersion=navigator.appVersion;
              uaProbe.ready=true;clearInterval(timer);}},20);
            </script>'''.replace('PORT', str(self.server.server_port))
        data = body.encode()
        self.send_response(200)
        self.send_header('Content-Type', kind)
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    require_unlocked_desktop()
    safari = plistlib.loads(Path('/Applications/Safari.app/Contents/Info.plist').read_bytes())
    version = safari['CFBundleShortVersionString']
    expected = ('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                f'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/{version} Safari/605.1.15')
    with tempfile.TemporaryDirectory(prefix='talaria-user-agent-test-', dir='/tmp') as profile:
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            launch_browser_test_app('build/BrowserUserAgentProbe.app', env=dict(os.environ,
                TL_WEBKIT_PROFILE_DIR=profile,
                TL_BROWSER_TEST_URL=f'http://127.0.0.1:{server.server_port}',
                TL_BROWSER_TEST_EXPECTED_UA=expected), timeout=55)
            for path in ('/redirect', '/regular', '/private', '/frame', '/echo', '/worker.js', '/popup'):
                observed = [r for r in requests if r['path'] == path]
                assert observed and all(r['userAgent'] == expected for r in observed), (path, observed)
                print('PASS: Safari identity on every HTTP request to', path)
            (ROOT / 'build/BrowserUserAgentResults.json').write_text(json.dumps(requests, indent=2))
        finally:
            server.shutdown()
