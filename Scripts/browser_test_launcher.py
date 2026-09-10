"""Launch browser probes through LaunchServices, from this checkout only."""
from pathlib import Path
import os
import re
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def require_unlocked_desktop():
    state = subprocess.run(['ioreg', '-l', '-n', 'Root', '-d1'], capture_output=True, text=True, check=True).stdout
    if re.search(r'"CGSSessionScreenIsLocked"\s*=\s*Yes', state):
        raise RuntimeError('This native browser test requires an unlocked desktop. macOS marks WebKit pages hidden and blocks trusted input while the screen is locked.')

def launch_browser_test_app(app, *, env, timeout):
    app = Path(app)
    if not app.is_absolute():
        app = ROOT / app
    app = app.resolve()
    app.relative_to(ROOT)
    assert app.suffix == '.app' and app.is_dir(), app
    with tempfile.TemporaryDirectory(prefix='talaria-webkit-launch-', dir='/tmp') as directory:
        log = Path(directory) / 'application.log'
        command = ['open', '-n', '-W', '--stdout', str(log), '--stderr', str(log)]
        for key, value in env.items():
            if key.startswith(('TL_', 'TALARIA_')):
                command += ['--env', f'{key}={value}']
        command.append(str(app))
        try:
            subprocess.run(command, env=env, timeout=timeout, check=True)
        except subprocess.TimeoutExpired:
            # Scope cleanup to this worktree's test executable, never user Talaria.
            executable = str(app / 'Contents/MacOS/Talaria')
            rows = subprocess.run(['ps', '-axo', 'pid=,comm='], capture_output=True, text=True, check=True).stdout
            for row in rows.splitlines():
                columns = row.strip().split(None, 1)
                if len(columns) == 2 and columns[1] == executable:
                    os.kill(int(columns[0]), signal.SIGTERM)
            raise
        finally:
            output = log.read_text(errors='replace') if log.exists() else ''
            print(output, end='')
        assert 'FAIL:' not in output, 'Browser probe reported a failed assertion'
        assert 'TALARIA_BROWSER_TEST_COMPLETE' in output, 'Browser probe did not complete normally'
