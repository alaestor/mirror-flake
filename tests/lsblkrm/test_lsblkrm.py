import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class RemovableDevicesTests(unittest.TestCase):
    def run_lsblkrm(self, devices, *args, fail=False, nushell=False):
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary) / "devices.json"
            fixture.write_text(json.dumps({"blockdevices": devices}))
            command = (["nu", "--no-config-file", "-c",
                        f"source {os.environ['NU_SHORTCUTS']}; lsblkrm | to json"] if nushell
                       else [os.environ["LSBLKRM"], *args])
            return subprocess.run(
                command, capture_output=True, text=True, timeout=10,
                env={**os.environ, "LSBLK_FIXTURE": str(fixture), "LSBLK_FAIL": str(int(fail)),
                     "PATH": str(Path(os.environ["LSBLKRM"]).parent) + os.pathsep + os.environ["PATH"]},
            )

    def test_filter_and_output(self):
        removable = {"name": "sdb", "size": "8G", "model": "USB Drive", "tran": "usb", "rm": True, "ro": False}
        fixed = {**removable, "name": "sda", "rm": False}
        missing_transport = {**removable, "name": "mmcblk0", "model": None, "tran": None, "ro": True}
        result = self.run_lsblkrm([fixed, removable, missing_transport], "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"blockdevices": [removable, missing_transport]})
        result = self.run_lsblkrm([fixed, removable, missing_transport])
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0].split(), ["NAME", "SIZE", "MODEL", "TRAN", "RM", "RO"])
        self.assertEqual(len(lines), 3)
        self.assertIn("USB Drive", lines[1])
        self.assertIn("mmcblk0", lines[2])
        self.assertNotIn("sda", result.stdout)

    def test_empty_list(self):
        result = self.run_lsblkrm([], "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"blockdevices": []})
        result = self.run_lsblkrm([])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 1)

    def test_failure(self):
        result = self.run_lsblkrm([], fail=True)
        self.assertEqual(result.returncode, 17)
        self.assertEqual(result.stdout, "")

    def test_arguments(self):
        for args in [("unexpected",), ("--json", "--json"), ("",)]:
            with self.subTest(args=args):
                result = self.run_lsblkrm([], *args)
                self.assertEqual(result.returncode, 2)
                self.assertIn("Usage:", result.stderr)
        result = self.run_lsblkrm([], "--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stdout)

    def test_nushell_adapter(self):
        removable = {"name": "sdb", "size": "8G", "model": None, "tran": "usb", "rm": True, "ro": False}
        fixed = {**removable, "name": "sda", "rm": False}
        for devices, expected in [([fixed, removable], [removable]), ([], [])]:
            with self.subTest(empty=not devices):
                result = self.run_lsblkrm(devices, nushell=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), expected)
        result = self.run_lsblkrm([], nushell=True, fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("lsblkrm failed", result.stderr)


if __name__ == "__main__":
    unittest.main()
