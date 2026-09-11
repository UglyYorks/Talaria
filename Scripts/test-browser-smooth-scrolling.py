#!/usr/bin/env python3
"""Production smoothing through AppKit's local monitor and the WebKit process."""
import http.server
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import threading
from browser_test_launcher import launch_browser_test_app, require_unlocked_desktop

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('wheel_fixture', Path(__file__).with_name('test-browser-wheel-routing.py'))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


def verify(records):
    checks = 0

    def check(condition, message):
        nonlocal checks
        if not condition:
            raise AssertionError(message)
        checks += 1
        print('PASS:', message)

    def wheel(name):
        return [e for e in records[name]['wheel'] if e['x'] or e['y']]

    for name, expected in [('smooth-long', 120), ('smooth-repeated', 360), ('smooth-reversal', 0)]:
        r = records[name]
        check(r['y'] == expected and sum(e['y'] for e in wheel(name)) == expected,
              name + ' preserves the requested distance in native page events and final position')
    check(len(wheel('smooth-long')) > 1 and any(0 < f['y'] < 120 for f in records['smooth-long']['frames']),
          'one coarse tick produces intermediate rendered positions')
    for name in ('smooth-horizontal', 'smooth-shift'):
        check(records[name]['x'] == 120 and records[name]['y'] == 0,
              name + ' preserves horizontal distance without vertical motion')
    check(all(e['shift'] for e in wheel('smooth-shift')), 'Shift is preserved on the native gesture')
    for name in ('smooth-panel', 'smooth-moving-panel'):
        check(records[name]['panel'] == 120 and records[name]['y'] == 0,
              name + ' stays latched to the intended nested scroller')
    check(records['smooth-panel-horizontal']['panelX'] == 120 and records['smooth-panel-horizontal']['x'] == 0,
          'horizontal input stays inside its nested panel')
    check(records['smooth-frame']['frame']['y'] == 120 and records['smooth-frame']['y'] == 0,
          'cross-origin iframe receives all input and the parent remains stationary')
    check(records['smooth-consumer']['y'] == 0 and sum(e['y'] for e in wheel('smooth-consumer')) == 120,
          'wheel-consuming content receives native input and preventDefault prevents scrolling')
    for name in ('bypass-control', 'bypass-command', 'bypass-option'):
        check(records[name]['actions'] == 1 and len(wheel(name)) == 1 and records[name]['y'] == 0,
              name + ' preserves one native site action')
    for name in ('bypass-precise', 'bypass-phased', 'bypass-disabled', 'bypass-reduce-motion'):
        check(records[name]['y'] == 120 and len(wheel(name)) == 1,
              name + ' preserves original native input')
    check(records['bypass-diagonal']['x'] == 120 and records['bypass-diagonal']['y'] == 120,
          'diagonal wheel bypass avoids gesture axis locking')
    # The native fixture asserts pointer identity at NSWindow.sendEvent: for
    # momentum too. AppKit may discard standalone fabricated momentum; this
    # cannot validate a physical trackpad's system-managed momentum sequence.
    print('HARDWARE CHECK REMAINS: momentum is forwarded unchanged at NSWindow; physical trackpad momentum is not synthesized faithfully by this fixture')
    check(all(e['trusted'] for r in records.values() for e in r['wheel']), 'all observed wheel events came through native WebKit input')
    for name in ('cancel-disable', 'cancel-hidden', 'cancel-detached', 'cancel-window', 'cancel-key', 'cancel-motion', 'cancel-stalled', 'cancel-same-document', 'cancel-close'):
        distance = sum(e['y'] for e in wheel(name))
        check(0 < distance < 120, name + ' discards the pending tail')
    for name in ('smooth-boundary', 'smooth-near-boundary'):
        r = records[name]
        check(r['panel'] == r['panelMax'], name + ' settles at the nested boundary')
        print('COMPATIBILITY:', name, 'parent scroll =', r['y'], 'maximum nested overshoot =',
              max(0, max(f['panel'] for f in r['frames']) - r['panelMax']))
    print('COMPATIBILITY: threshold-based consumer actions =', records['smooth-consumer']['actions'],
          '; subdividing a wheel tick changes its per-event semantics')
    print(f'PASS: {checks} native page contracts')


if __name__ == '__main__':
    require_unlocked_desktop()
    with tempfile.TemporaryDirectory(prefix='talaria-smoothing-', dir='/tmp') as profile:
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), fixture.Fixture)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        output = ROOT / 'build/BrowserSmoothScrollingResults.json'
        try:
            launch_browser_test_app('build/BrowserSmoothScrollingProbe.app', env=dict(os.environ,
                TL_WEBKIT_PROFILE_DIR=profile, TL_BROWSER_TEST_URL=f'http://127.0.0.1:{server.server_port}/',
                TL_BROWSER_TEST_RESULTS=str(output)), timeout=60)
            records = {r['name']: r for r in json.loads(output.read_text())}
            verify(records)
            print(f'Completed {len(records)} native scenarios. Full traces: {output}')
        finally:
            server.shutdown()
