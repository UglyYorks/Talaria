"""Install the user-only helper without replacing an already-approved binary."""
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys

source = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path.home() / "Library/Application Support/Talaria/CredentialHelper"
destination = root / "Talaria Credentials.app"
agent = pathlib.Path.home() / "Library/LaunchAgents/com.talaria.chat.credentials-helper.plist"
label = "com.talaria.chat.credentials-helper"
domain = f"gui/{os.getuid()}"

def verify(bundle):
    subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True)

def code_hash(bundle):
    output = subprocess.check_output(["codesign", "-d", "--verbose=4", str(bundle)], stderr=subprocess.STDOUT).decode()
    return next(line for line in output.splitlines() if line.startswith("CDHash="))

verify(source)
if destination.exists():
    verify(destination)
    if code_hash(source) != code_hash(destination):
        sys.exit("Installed helper differs. Leaving it untouched to preserve Keychain approval. Explicitly plan a helper upgrade before replacing it.")
else:
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    shutil.copytree(source, destination)
    verify(destination)

configuration = {
    "Label": label,
    "ProgramArguments": [str(destination / "Contents/MacOS/TalariaCredentials")],
    "MachServices": {label: True},
    "ProcessType": "Interactive",
    "LimitLoadToSessionType": "Aqua",
}
data = plistlib.dumps(configuration)
agent.parent.mkdir(parents=True, exist_ok=True)
if agent.exists() and agent.read_bytes() != data:
    sys.exit("An existing helper LaunchAgent has different settings; left unchanged.")
if not agent.exists():
    with agent.open("xb") as output:
        output.write(data)
    agent.chmod(0o600)
loaded = subprocess.run(["launchctl", "print", f"{domain}/{label}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
if loaded.returncode:
    subprocess.run(["launchctl", "bootstrap", domain, str(agent)], check=True)
print(f"Credential helper ready: {destination}")
