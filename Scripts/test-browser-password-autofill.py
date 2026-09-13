#!/usr/bin/env python3
"""Run the system AutoFill integration as a desktop app with synthetic credentials."""
import os
from pathlib import Path
from browser_test_launcher import launch_browser_test_app, require_unlocked_desktop

require_unlocked_desktop()
root = Path(__file__).resolve().parents[1]
launch_browser_test_app('build/BrowserPasswordAutofillProbe.app', env=dict(os.environ,
    TL_AUTOFILL_OUTPUT=str(root / 'build')), timeout=95)
