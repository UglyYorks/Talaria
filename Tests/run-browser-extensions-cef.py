#!/usr/bin/env python3
"""Desktop extension persistence/management tests; isolated app and profile."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--skip-build", action="store_true")
args = parser.parse_args()
os.chdir(ROOT)
if not args.skip_build:
    subprocess.run(["make", "build"], check=True)
work = Path(tempfile.mkdtemp(prefix="extension-tests-", dir=ROOT / "build"))
try:
    cef = next((ROOT / "build/deps").glob("cef_binary_*"))
    object_dir = ROOT / "build/app-objects"
    objects = sorted(str(p) for p in object_dir.rglob("*.o")
                     if p.name != "main.mm.o" and
                     (ROOT / "Source" / p.relative_to(object_dir).with_suffix("")).exists())
    frameworks = ["QuickLookThumbnailing", "UniformTypeIdentifiers", "AppKit", "Foundation", "QuartzCore",
                  "SceneKit", "CoreText", "Cocoa", "IOSurface", "WebKit", "Virtualization", "Security"]
    binary = work / "Test"
    subprocess.run([
        "xcrun", "clang++", "-fobjc-arc", "-std=c++20", "-fno-exceptions", "-fno-rtti",
        "-mmacosx-version-min=13.0", "-I" + str(cef), "-ISource", "Tests/BrowserExtensionsCEFTests.mm",
        *objects, "build/libcef_dll_wrapper.a",
        *[arg for framework in frameworks for arg in ("-framework", framework)],
        "-lsqlite3", "-lpthread", "-o", str(binary)], check=True)
    app = work / "Talaria.app"
    subprocess.run(["cp", "-cRp", "build/Talaria.app", str(app)], check=True)
    shutil.copy2(binary, app / "Contents/MacOS/Talaria")
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleIdentifier"] = "com.talaria.integration." + work.name
    info_path.write_bytes(plistlib.dumps(info))
    subprocess.run(["codesign", "--force", "--sign",
                    os.environ.get("CODE_SIGN_IDENTITY", "Talaria Local Development"),
                    "--entitlements", "Entitlements.plist", str(app)], check=True)
    subprocess.run(["node", "Tests/BrowserExtensionsTests.mjs", str(work)], check=True)
finally:
    dialog = work / "control.dialog"
    if dialog.exists(): print("Test installer chooser:", dialog.read_text())
    shutil.rmtree(work, ignore_errors=True)
