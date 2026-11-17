from pathlib import Path
import subprocess
import unittest


class PublicHandoffTest(unittest.TestCase):
    def test_qualification_has_no_owner_machine_or_private_script(self):
        root = Path(__file__).resolve().parents[2]
        result = subprocess.run(
            ["git", "grep", "-niE", "the (Air|Pro)([^[:alpha:]]|$)|~/bin/ab-real",
             "--", "lab/iphone-real/README.md", "ios/App/RealQualification.swift",
             "ios/App/ShellDeliveryQualification.swift"],
            cwd=root, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
