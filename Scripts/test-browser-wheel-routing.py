#!/usr/bin/env python3
"""Native macOS WebKit wheel contract probe, using only disposable local pages."""
import http.server
import json
import os
from pathlib import Path
import tempfile
import threading
from browser_test_launcher import launch_browser_test_app, require_unlocked_desktop

ROOT = Path(__file__).resolve().parents[1]


def verify(records):
    """Assert native contracts; report experimental failures without shipping them."""
    def check(condition, message):
        if not condition:
            raise AssertionError(message)
        print('PASS:', message)

    def wheel(name):
        return records[name]['wheel']

    check(records['native-long']['y'] == 120, 'one native wheel step scrolls 120 pixels')
    check(records['native-repeated']['y'] == 360 and len(wheel('native-repeated')) == 3,
          'three native wheel steps preserve their combined distance')
    check(records['native-reversal']['y'] == 0 and len(wheel('native-reversal')) == 2,
          'opposite native wheel steps return to the initial position')
    check(records['native-horizontal']['x'] == 120 and records['native-horizontal']['y'] == 0,
          'native horizontal input preserves its axis and distance')
    check(records['native-shift-wheel']['x'] == 120 and wheel('native-shift-wheel')[0]['shift'],
          'WebKit converts native Shift-wheel to horizontal input')
    check(records['native-panel']['panel'] == 120 and records['native-panel']['y'] == 0,
          'native input scrolls the nested panel without scrolling its parent')
    check(records['native-iframe']['frame']['y'] == 120 and records['native-iframe']['y'] == 0,
          'native input scrolls the cross-origin frame without scrolling its parent')
    for name in ('native-consumer', 'native-control-consumer'):
        check(records[name]['actions'] == 1 and records[name]['y'] == 0 and len(wheel(name)) == 1,
              name + ' receives one action and prevents default scrolling')
    check(wheel('native-control-consumer')[0]['control'], 'Control modifier reaches the consuming site')
    for name in ('native-precise', 'native-momentum'):
        check(records[name]['y'] == 120 and sum(e['y'] for e in wheel(name)) == 120,
              name + ' reaches WebKit with the original total distance')
    check(all(e['trusted'] for r in records.values() for e in r['wheel']),
          'page events came through the native input path')

    # These are observed incompatibilities, not successful smoothing tests.
    for name in ('subdivided-consumer', 'phased-consumer'):
        r = records[name]
        equivalent = r['actions'] == records['native-consumer']['actions'] and len(r['wheel']) == 1
        print('EXPERIMENT:', name, 'site behavior preserved =', equivalent,
              f"({r['actions']} actions, {len(r['wheel'])} events)")
    for name in ('native-moving-panel', 'subdivided-moving-panel', 'phased-moving-panel',
                 'native-boundary', 'subdivided-boundary', 'phased-boundary',
                 'native-near-boundary', 'subdivided-near-boundary', 'phased-near-boundary'):
        r = records[name]
        overshoot = max(f['panel'] for f in r['frames']) - r['panelMax']
        print('EXPERIMENT:', name, f"page={r['y']}, panel={r['panel']}, "
              f"panel overshoot={max(0, overshoot)}, wheel events={len(r['wheel'])}")
    animator = records['native-animator-enabled']
    intermediate = any(0 < f['y'] < 120 for f in animator['frames'])
    print('EXPERIMENT: native animator available =', animator['animatorFeatureAvailable'],
          '; intermediate scroll positions observed =', intermediate)


class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/frame':
            body = '''<!doctype html><style>body{margin:0;height:2400px;background:#dde}</style>Frame
            <script>let count=0;function report(){parent.postMessage({frame:true,y:scrollY,count},'*')}
            addEventListener('wheel',()=>{count++;setTimeout(report,40)});addEventListener('scroll',report);
            addEventListener('message',()=>{scrollTo(0,0);count=0;report()});report();</script>'''
        else:
            body = '''<!doctype html><style>body{margin:0;height:6000px;width:1800px;background:#eee}
            #panel,#consumer,iframe{position:absolute;top:40px;width:220px;height:180px;border:0}
            #panel{left:40px;overflow:auto;background:#ddf}#inside{height:1600px;width:1200px}
            #consumer{left:330px;background:#fdd}iframe{left:620px;width:200px}</style>
            <div id=panel><div id=inside>Nested panel</div></div><div id=consumer>Wheel consumer</div>
            <iframe src="http://localhost:PORT/frame"></iframe><script>
            let wheel=[],frames=[],actions=0,moving=false,frameState={},frameReady=false;
            const panel=document.querySelector('#panel'),consumer=document.querySelector('#consumer');
            addEventListener('message',e=>{if(e.data.frame){frameState=e.data;frameReady=true}});
            addEventListener('wheel',e=>{wheel.push({x:e.deltaX,y:e.deltaY,mode:e.deltaMode,
              target:e.target.id,cancelable:e.cancelable,trusted:e.isTrusted,shift:e.shiftKey,control:e.ctrlKey,time:performance.now()});
              if(moving && e.target.closest('#panel'))panel.style.left='1200px';},{capture:true});
            consumer.addEventListener('wheel',e=>{e.preventDefault();if(Math.abs(e.deltaY)>=40)actions++},{passive:false});
            function trace(){frames.push({time:performance.now(),x:scrollX,y:scrollY,panel:panel.scrollTop});requestAnimationFrame(trace)}
            requestAnimationFrame(trace);
            function resetProbe(move,boundary,nearBoundary){scrollTo(0,0);panel.style.left='40px';
              panel.scrollTop=boundary?panel.scrollHeight-panel.clientHeight:nearBoundary?panel.scrollHeight-panel.clientHeight-16:0;
              panel.scrollLeft=0;document.querySelector('iframe').contentWindow.postMessage('reset','*');
              wheel=[];frames=[];actions=0;moving=move;}
            function readProbe(){return {x:scrollX,y:scrollY,panel:panel.scrollTop,panelX:panel.scrollLeft,panelMax:panel.scrollHeight-panel.clientHeight,frame:frameState,actions,wheel,frames};}
            </script>'''.replace('PORT',str(self.server.server_port))
        encoded=body.encode()
        self.send_response(200)
        self.send_header('Content-Type','text/html')
        self.send_header('Content-Length',str(len(encoded)))
        self.end_headers();self.wfile.write(encoded)
    def log_message(self,*args): pass

if __name__ == '__main__':
    require_unlocked_desktop()
    with tempfile.TemporaryDirectory(prefix='talaria-wheel-test-',dir='/tmp') as profile:
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Fixture)
        threading.Thread(target=server.serve_forever,daemon=True).start()
        output=ROOT/'build/BrowserWheelRoutingWebKitResults.json'
        try:
            launch_browser_test_app('build/BrowserWheelRoutingProbe.app',env=dict(os.environ,
                TL_WEBKIT_PROFILE_DIR=profile,TL_BROWSER_TEST_URL=f'http://127.0.0.1:{server.server_port}/',
                TL_BROWSER_TEST_RESULTS=str(output)),timeout=50)
            records={r['name']:r for r in json.loads(output.read_text())}
            verify(records)
            print(f'Completed {len(records)} native scenarios. Full traces: {output}')
        finally: server.shutdown()
