#!/usr/bin/env python3
"""Repeatable foreground WebKit frame-cadence comparison; no external websites."""
import argparse
import http.server
import json
import os
import subprocess
from pathlib import Path
import tempfile
import threading
from browser_test_launcher import launch_browser_test_app, require_unlocked_desktop

ROOT = Path(__file__).resolve().parents[1]
PAGE = r'''<!doctype html><meta charset="utf-8"><title>Browser frame fixture</title>
<style>body{margin:0;background:#f4f4f4;color:#222}article{padding:12px;min-height:42px;border-bottom:1px solid #ddd}
canvas{position:fixed;right:20px;top:20px;width:500px;height:300px;pointer-events:none}</style>
<main></main><script>
const kind=location.pathname.slice(1),main=document.querySelector('main');
main.innerHTML=Array.from({length:kind==='dense'||kind==='churn'?3000:300},(_,i)=>`<article><b>Row ${i}</b> Browser rendering fixture <span>text content</span></article>`).join('');
if(kind==='color-sections')Array.from(main.children).forEach((e,i)=>{e.style.background=Math.floor(i/8)%2?'rgb(18,46,87)':'rgb(244,229,202)';e.style.color=Math.floor(i/8)%2?'white':'black'});
if(kind==='gradient')document.body.style.background='linear-gradient(120deg,#1d528d,#c96a4e)';
let canvas,ctx;if(kind==='canvas'||kind==='canvas-edge'){canvas=document.createElement('canvas');canvas.width=1000;canvas.height=600;if(kind==='canvas-edge')canvas.style.cssText='position:fixed;inset:0;width:100%;height:100%;pointer-events:auto';document.body.append(canvas);ctx=canvas.getContext('2d')}
let intervals=[],running=false,last=0,raf=0,scrollEvents=0,frames=0,visibility=[];
addEventListener('scroll',()=>{if(running)scrollEvents++},{passive:true});
document.addEventListener('visibilitychange',()=>visibility.push(document.visibilityState));
function frame(t){if(!running)return;if(last)intervals.push(t-last);last=t;frames++;
 if(kind==='churn'){for(let i=0;i<30;i++){const el=main.children[(frames*31+i)%main.children.length];el.lastElementChild.textContent='update '+frames;}}
 if(kind==='color-pulse' && frames%45===0)document.body.style.background=frames%90===0?'rgb(245,245,245)':'rgb(16,36,76)';
 if(ctx){ctx.fillStyle=`hsl(${Math.floor(t/700)*45},55%,45%)`;ctx.fillRect(0,0,1000,600);for(let i=0;i<150;i++){ctx.fillStyle=`hsl(${i*7},60%,50%)`;ctx.fillRect((i*43+t/4)%1000,(i*23)%600,30,30);}}
 raf=requestAnimationFrame(frame);}
function startProfile(){intervals=[];frames=scrollEvents=0;visibility=[];last=0;running=true;raf=requestAnimationFrame(frame);return true}
function stopProfile(){running=false;cancelAnimationFrame(raf);return {intervalsMS:intervals,frames,scrollEvents,visibility,visibilityState:document.visibilityState,scrollY,devicePixelRatio,viewport:[innerWidth,innerHeight]}}
</script>'''

class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = PAGE.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

def summarize(data):
    rows = []
    for case in data['cases']:
        values = sorted(case['page']['intervalsMS'])
        if (not values or case['page']['visibilityState'] != 'visible' or 'hidden' in case['page']['visibility']
                or not case['visible'] or not case['active']):
            raise RuntimeError(f'Invalid visible-window measurement: {case["mode"]}/{case["workload"]}')
        if case['workload'] not in ('idle','resize','gradient','color-pulse','canvas-edge') and case['page']['scrollEvents'] < 1:
            raise RuntimeError(f'No scrolling observed: {case["mode"]}/{case["workload"]}')
        # WebKit rAF is a cadence proxy, not a count of presented compositor frames.
        budget = 1000 / 60
        rows.append(dict(mode=case['mode'], workload=case['workload'], repeat=case['repeat'],
                         frames=len(values), p95_ms=round(values[int((len(values)-1)*.95)], 2),
                         max_ms=round(max(values), 2), gaps_over_25ms=sum(v>budget*1.5 for v in values),
                         estimated_missed_intervals=sum(max(0,round(v/budget)-1) for v in values),
                         native_max_ms=round(max(case['nativeIntervalsMS']),2),
                         native_cpu_seconds=round(case['nativeCPUSeconds'],3)))
    return rows

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--delay', type=float, default=0)
    parser.add_argument('--modes', default='workspace')
    parser.add_argument('--workloads', default='simple,dense,churn,canvas,resize,color-sections,gradient,color-pulse,canvas-edge')
    parser.add_argument('--width', type=int, default=1200)
    parser.add_argument('--height', type=int, default=850)
    parser.add_argument('--dark', action='store_true')
    parser.add_argument('--instrument-color', action='store_true', help='Time color probes in the disposable bundle; includes page warm-up')
    parser.add_argument('--skip-scroll-color', action='store_true', help='Experimental ablation in the disposable bundle only')
    parser.add_argument('--no-blur', action='store_true', help='Hide native bottom blur in the probe only')
    parser.add_argument('--no-color-wave', action='store_true', help='Disconnect the native tab-color display callback in the probe only; keep sampling')
    parser.add_argument('--output', type=Path, default=ROOT/'build/profiling/frames.json')
    parser.add_argument('--app', type=Path, default=ROOT/'build/TalariaPerformance.app', help='Desktop probe bundle inside this worktree')
    args=parser.parse_args()
    if args.repeats < 1 or args.repeats > 10:
        parser.error('--repeats must be between 1 and 10')
    if not set(args.modes.split(',')) <= {'raw','session','tab','workspace'}:
        parser.error('unknown mode')
    if not set(args.workloads.split(',')) <= {'idle','simple','dense','churn','canvas','resize','color-sections','gradient','color-pulse','canvas-edge'}:
        parser.error('unknown workload')
    require_unlocked_desktop()
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.unlink(missing_ok=True)
    args.output.with_suffix('.pid').unlink(missing_ok=True)
    app=args.app.resolve()
    app.relative_to(ROOT)
    resources=app/'Contents/Resources'
    originals={name:(resources/name).read_text() for name in ('BrowserWebKitBridge.js','BrowserFooterColor.js')}
    modified=args.instrument_color or args.skip_scroll_color
    def sign():
        subprocess.run(['codesign','--force','--sign',os.environ.get('CODE_SIGN_IDENTITY','Talaria Local Development'),
                        '--entitlements',str(ROOT/'Entitlements.plist'),str(app)],check=True)
    if args.instrument_color:
        source=originals['BrowserFooterColor.js']
        (resources/'BrowserFooterColor.js').write_text('((original)=>function(...args){const t=performance.now();try{return original(...args)}finally{const elapsed=performance.now()-t;const p=globalThis.__frameColorProfile ||= {calls:0,totalMS:0,maxMS:0,over3MS:0};p.calls++;p.totalMS+=elapsed;p.maxMS=Math.max(p.maxMS,elapsed);if(elapsed>3)p.over3MS++;}})('+source+')')
    if args.skip_scroll_color:
        source=originals['BrowserWebKitBridge.js']
        needle='const rgb=colorProbe?.(null,true,globalThis.__talariaTabColorRange)?.rgb;'
        assert needle in source
        (resources/'BrowserWebKitBridge.js').write_text(source.replace(needle,'const rgb=null;'))
    if modified:
        sign()
    with tempfile.TemporaryDirectory(prefix='talaria-frame-',dir='/tmp') as profile:
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Fixture)
        threading.Thread(target=server.serve_forever,daemon=True).start()
        try:
            launch_browser_test_app(app,env=dict(os.environ,
                TL_WEBKIT_PROFILE_DIR=profile,TL_BROWSER_TEST_URL=f'http://127.0.0.1:{server.server_port}',
                TL_BROWSER_TEST_RESULTS=str(args.output.resolve()),TL_PROFILE_REPEATS=str(args.repeats),
                TL_PROFILE_MODES=args.modes,TL_PROFILE_WORKLOADS=args.workloads,
                TL_PROFILE_NO_BLUR=str(int(args.no_blur)),
                TL_PROFILE_NO_COLOR_WAVE=str(int(args.no_color_wave)),
                TL_PROFILE_WIDTH=str(args.width),TL_PROFILE_HEIGHT=str(args.height),TL_PROFILE_DARK=str(int(args.dark)),
                TL_PROFILE_DELAY=str(args.delay),TL_PROFILE_PID=str(args.output.with_suffix('.pid').resolve())),
                timeout=args.repeats*110+args.delay+30)
        finally:
            server.shutdown()
            if modified:
                for name,source in originals.items():
                    (resources/name).write_text(source)
                sign()
    data=json.loads(args.output.read_text())
    data['configuration']={'instrumentColor':args.instrument_color,'skipScrollColor':args.skip_scroll_color,'noBlur':args.no_blur,'noColorWave':args.no_color_wave,'dark':args.dark}
    args.output.write_text(json.dumps(data,indent=2)+'\n')
    rows=summarize(data)
    args.output.with_suffix('.summary.json').write_text(json.dumps(rows,indent=2)+'\n')
    for row in rows:
        print(row)
