import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


HELPERS = Path(os.environ.get(
    "FLAKE_HELPERS", Path(__file__).resolve().parents[2] / "data/programs/nushell/flake-helpers.nu"
))
OLD = "sha256-" + "A" * 43 + "="
NEW = "sha256-" + "B" * 43 + "="
TARGET = ".#nixosConfigurations.lanser.config.services.caddy.package.src"

STUB = r'''
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
scenario = os.environ["SCENARIO"]
with open("calls.jsonl", "a") as calls:
    calls.write(json.dumps(args) + "\n")
if args[:2] == ["flake", "update"]:
    if scenario == "update-failure":
        sys.exit(1)
    Path("flake.lock").write_text("updated")
elif args[0] == "eval":
    if scenario == "eval-failure":
        sys.exit(1)
    print("/nix/store/test-caddy-src.drv", end="")
elif args[0] == "build":
    counter = Path("build-count")
    count = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(count))
    if scenario == "cached" or count == 2 and scenario != "verify-failure":
        sys.exit(0)
    if scenario in ("build-failure", "verify-failure") and (count == 2 or scenario == "build-failure"):
        print("error: network unavailable", file=sys.stderr)
        sys.exit(1)
    drv = "/nix/store/dependency.drv" if scenario == "wrong-drv" else "/nix/store/test-caddy-src.drv"
    old = "sha256-" + ("C" if scenario == "wrong-specified" else "A") * 43 + "="
    new = "sha256-" + "B" * 43 + "="
    if scenario == "invalid-hash":
        new = "not-a-hash"
    diagnostic = f"error: hash mismatch in fixed-output derivation '{drv}':\n         specified: {old}\n            got:    {new}\n"
    print(diagnostic * (2 if scenario == "ambiguous" else 1), file=sys.stderr)
    sys.exit(1)
else:
    sys.exit("Unexpected nix invocation")
'''


class NupTests(unittest.TestCase):
    def test_update_workflow(self):
        cases = [
            ("cached", True, OLD, 1),
            ("mismatch", True, NEW, 2),
            ("update-failure", False, OLD, 0),
            ("eval-failure", False, OLD, 0),
            ("build-failure", False, OLD, 1),
            ("wrong-drv", False, OLD, 1),
            ("wrong-specified", False, OLD, 1),
            ("invalid-hash", False, OLD, 1),
            ("ambiguous", False, OLD, 1),
            ("verify-failure", False, OLD, 2),
        ]
        for scenario, success, expected_hash, builds in cases:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary) / "flake with spaces"
                root.mkdir()
                source = root / "data/serve/caddy/source.json"
                source.parent.mkdir(parents=True)
                original = json.dumps({"hash": OLD}) + "\n"
                source.write_text(original)
                (root / "flake.lock").write_text("original")
                binary = root / "bin"
                binary.mkdir()
                nix = binary / "nix"
                nix.write_text(f"#!{sys.executable}\n" + STUB)
                nix.chmod(0o755)
                helper = root / "helpers.nu"
                helper.write_text(HELPERS.read_text().replace("@LOCAL_FLAKE@", str(root)) + "\nnup\n")
                result = subprocess.run(
                    ["nu", "--no-config-file", str(helper)],
                    cwd=temporary,
                    env={**os.environ, "PATH": str(binary) + os.pathsep + os.environ["PATH"], "SCENARIO": scenario},
                    capture_output=True, text=True, timeout=15,
                )
                self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
                self.assertEqual(json.loads(source.read_text())["hash"], expected_hash)
                if expected_hash == OLD:
                    self.assertEqual(source.read_text(), original)
                calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
                self.assertEqual(calls[0], ["flake", "update"])
                self.assertEqual([call for call in calls if call[0] == "build"], [["build", "--no-link", TARGET]] * builds)
                self.assertEqual((root / "flake.lock").read_text(), "original" if scenario == "update-failure" else "updated")


if __name__ == "__main__":
    unittest.main()
