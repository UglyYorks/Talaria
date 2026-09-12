#!/usr/bin/env python3
"""Run the desktop WebKit backdrop fixture; --inspect pauses for compositor QA."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
app = root / 'build/BrowserBackdropTests.app'
executable = app / 'Contents/MacOS/BrowserBackdropTests'
executable.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(root / 'build/BrowserBackdropTests', executable)
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'com.talaria.tests.backdrop',
    'CFBundleExecutable': 'BrowserBackdropTests', 'CFBundlePackageType': 'APPL',
}))
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
log = root / 'build/browser-backdrop-test.log'
log.unlink(missing_ok=True)
command = ['open', '-n', '-W']
if '--inspect' in sys.argv:
    command += ['--env', 'TL_BLUR_INSPECT=1']
command += ['--stdout', str(log), '--stderr', str(log), str(app), '--args',
            str(root / 'Source/BrowserDocumentFooter.js')]
subprocess.run(command, check=True, timeout=70)
output = log.read_text()
print(output)
assert 'BrowserBackdropTests passed' in output and 'FAIL:' not in output
