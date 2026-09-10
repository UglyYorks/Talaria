#!/usr/bin/env python3
"""Prepare a desktop WebKit integration bundle with the application's resources."""
from pathlib import Path
import plistlib
import shutil
import sys
source = Path(sys.argv[1]).resolve() / 'Contents'
target = Path(sys.argv[2]).resolve() / 'Contents'
# WebKit is supplied by macOS. Remove stale embedded-engine bundles when a
# previously built probe is reused.
frameworks = target / 'Frameworks'
if frameworks.is_symlink():
    frameworks.unlink()
elif frameworks.exists():
    shutil.rmtree(frameworks)

# Exercise the same browser document hooks as the desktop application.
resources = target / 'Resources'
resources.mkdir(exist_ok=True)
for name in ('BrowserDocumentFooter.js', 'BrowserFooterColor.js', 'BrowserOverlayProbe.js', 'Readability.js', 'BrowserWebKitBridge.js'):
    shutil.copy2(source / 'Resources' / name, resources / name)

info = Path(sys.argv[2]).resolve() / 'Contents/Info.plist'
metadata = plistlib.loads(info.read_bytes())
metadata['CFBundleIdentifier'] = 'com.talaria.browser-preferences-probe'
metadata['CFBundleDisplayName'] = 'Talaria Browser Test'
info.write_bytes(plistlib.dumps(metadata))
