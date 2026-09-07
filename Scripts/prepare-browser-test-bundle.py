#!/usr/bin/env python3
"""CEF's sandbox requires real framework paths inside its application bundle."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
source = Path(sys.argv[1]).resolve() / 'Contents/Frameworks'
target = Path(sys.argv[2]).resolve() / 'Contents/Frameworks'
if target.is_symlink():
    target.unlink()
elif target.exists():
    shutil.rmtree(target)
# APFS clones stay independent and keep helpers in sync with the tested build.
subprocess.run(['/bin/cp', '-cR', str(source), str(target)], check=True)

# Exercise the same browser document hooks as the desktop application.
resources = target.parent / 'Resources'
resources.mkdir(exist_ok=True)
for name in ('BrowserDocumentFooter.js', 'BrowserFooterColor.js', 'BrowserOverlayProbe.js'):
    shutil.copy2(source.parent / 'Resources' / name, resources / name)

info = Path(sys.argv[2]).resolve() / 'Contents/Info.plist'
metadata = plistlib.loads(info.read_bytes())
metadata['CFBundleIdentifier'] = 'com.talaria.browser-preferences-probe'
metadata['CFBundleDisplayName'] = 'Talaria Browser Test'
info.write_bytes(plistlib.dumps(metadata))
