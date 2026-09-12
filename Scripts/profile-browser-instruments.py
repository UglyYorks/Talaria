#!/usr/bin/env python3
"""Attach Instruments to a desktop-launched, disposable full-workspace probe.

Timing output from this run includes profiler overhead; use profile-browser-frames.py
without Instruments for comparative frame-cadence measurements.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--template', default='Time Profiler')
parser.add_argument('--name', default='native-time-profile')
parser.add_argument('--instrument', action='append', default=[])
parser.add_argument('--seconds', type=int, default=45)
args = parser.parse_args()
if not 5 <= args.seconds <= 70:
    parser.error('--seconds must be between 5 and 70')
if not args.name or Path(args.name).name != args.name:
    parser.error('--name must be a single filename component')
directory = ROOT / 'build/profiling'
directory.mkdir(parents=True, exist_ok=True)
trace = directory / (args.name + '.trace')
output = directory / (args.name + '.json')
pidfile = output.with_suffix('.pid')
if trace.exists():
    parser.error('trace already exists; use a different --name')
pidfile.unlink(missing_ok=True)
command = [sys.executable, str(ROOT / 'Scripts/profile-browser-frames.py'),
           '--modes', 'workspace', '--workloads', 'resize,churn,color-pulse,gradient,canvas-edge,idle',
           '--width', '2600', '--height', '1400', '--repeats', '2', '--delay', '10', '--output', str(output)]
with (directory / (args.name + '.log')).open('w') as log:
    process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 45
    while not pidfile.exists() and process.poll() is None and time.monotonic() < deadline:
        time.sleep(.1)
    if not pidfile.exists():
        process.terminate()
        raise RuntimeError('Desktop probe did not publish its PID; inspect its log')
    pid = int(pidfile.read_text())
    record_command=['xcrun','xctrace','record','--template',args.template,
                    '--attach',str(pid),'--time-limit',f'{args.seconds}s','--output',str(trace),'--no-prompt']
    for instrument in args.instrument:
        record_command += ['--instrument',instrument]
    try:
        record = subprocess.run(record_command, timeout=args.seconds+45)
        profiler_status=record.returncode
    except subprocess.TimeoutExpired:
        profiler_status=124
    try:
        status = process.wait(timeout=100)
    except subprocess.TimeoutExpired:
        process.terminate()
        raise
    (directory / (args.name + '.status.json')).write_text(json.dumps(
        {'profilerExit': profiler_status, 'probeExit': status, 'pid': pid,
         'template': args.template, 'trace': str(trace)}, indent=2) + '\n')
    if profiler_status or status:
        raise SystemExit(1)
print(trace)
