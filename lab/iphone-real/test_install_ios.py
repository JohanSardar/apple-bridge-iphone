import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class InstallIOSTest(unittest.TestCase):
    def test_installs_with_pymobiledevice3_on_remote_path(self):
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            bin_dir = home / "bin"
            bin_dir.mkdir()
            for name, body in {
                "scp": "exit 0",
                "ssh": 'shift; exec /bin/sh -c "$1"',
                "pymobiledevice3": 'printf "%s\\n" "$*"',
            }.items():
                stub = bin_dir / name
                stub.write_text(f"#!/bin/sh\n{body}\n")
                stub.chmod(0o755)
            ipa = home / "AppleBridge.ipa"
            ipa.touch()
            result = subprocess.run(
                [root / "packaging/dev/install-ios.sh", ipa],
                env=dict(os.environ, HOME=directory, PATH=f"{bin_dir}:/usr/bin:/bin",
                         APPLE_BRIDGE_INSTALL_HOST="test-mac"),
                text=True, capture_output=True,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "apps install /tmp/AppleBridge.ipa")
