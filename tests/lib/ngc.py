import argparse
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("ngc", os.environ["NGC_SOURCE"])
ngc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ngc)


class CleanupTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.state = Path(self.temporary.name)
        self.profiles = self.state / "profiles"
        self.profiles.mkdir()
        self.profile = self.profiles / "system"
        self.profile.symlink_to("system-1-link")
        for number in [1, 2, 3, 8, 9, 10]:
            path = self.profiles / f"system-{number}-link"
            path.symlink_to("/nix/store/example")
            os.utime(path, (100, 100), follow_symlinks=False)
        os.utime(self.profiles / "system-3-link", (950, 950), follow_symlinks=False)

    def test_arguments(self):
        args = ngc.arguments([])
        self.assertEqual((args.older_than, args.keep_last, args.clean_roots), (14 * 86400, 5, False))
        args = ngc.arguments(["--older-than=2w", "--keep-last", "2", "--clean-roots"])
        self.assertEqual((args.older_than, args.keep_last, args.clean_roots), (14 * 86400, 2, True))
        self.assertEqual(ngc.duration("0d"), 0)
        for value in ["", "-1d", "1.5d", "tomorrow", "1"]:
            with self.assertRaises(argparse.ArgumentTypeError):
                ngc.duration(value)
        for value in ["0", "-1", "1.2", "foo"]:
            with self.assertRaises(argparse.ArgumentTypeError):
                ngc.keep_count(value)
        for argv in [["--unknown"], ["--older-than"], ["--keep-last"]]:
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                ngc.arguments(argv)

    def test_retention_is_union_of_age_newest_and_selected(self):
        self.assertEqual(ngc.generations_to_remove(self.profiles, 900, 2), {self.profile: [8, 2]})
        self.assertEqual(ngc.generations_to_remove(self.profiles, 900, 20), {})
        # Exact cutoff and future timestamps are retained.
        self.assertEqual(ngc.generations_to_remove(self.profiles, 100, 1), {})
        other = self.profiles / "other-20-link"
        other.symlink_to("/nix/store/example")
        self.assertNotIn(self.profiles / "other", ngc.generations_to_remove(self.profiles, 900, 2))

    def test_profile_discovery(self):
        user = SimpleNamespace(pw_dir="/home/example", pw_name="example")
        per_user = self.profiles / "per-user/example"
        per_user.mkdir(parents=True)
        with patch.object(ngc.os, "geteuid", return_value=0), \
             patch.object(ngc.pwd, "getpwall", return_value=[user]), \
             patch.object(ngc.Path, "home", return_value=Path("/root")), \
             patch.dict(os.environ, {"XDG_STATE_HOME": "/custom/state"}):
            directories = ngc.profile_directories(self.state)
            for directory in [self.profiles, per_user, Path("/home/example/.local/state/nix/profiles"),
                              Path("/root/.local/state/nix/profiles"), Path("/custom/state/nix/profiles")]:
                self.assertIn(directory, directories)
        with patch.object(ngc.os, "geteuid", return_value=1000), \
             patch.object(ngc.pwd, "getpwuid", return_value=user), \
             patch.object(ngc.pwd, "getpwall") as all_users:
            self.assertIn(per_user, ngc.profile_directories(self.state))
            all_users.assert_not_called()

    def run_cleanup(self, answer="y", roots=False, fail=False):
        with patch.object(ngc, "profile_directories", return_value=[self.profiles]), \
             patch.object(ngc.time, "time", return_value=1000), \
             patch("builtins.input", side_effect=answer if callable(answer) else lambda _: answer), \
             patch.object(ngc.subprocess, "run") as run, \
             contextlib.redirect_stdout(io.StringIO()):
            self.subprocess_run = run
            if fail:
                def fail_pruning(command, **kwargs):
                    if command[0] == "nix-env":
                        raise subprocess.CalledProcessError(1, command)
                    return subprocess.CompletedProcess(command, 0)
                run.side_effect = fail_pruning
            result = ngc.cleanup(ngc.arguments(["--older-than", "100s", "--keep-last", "2"]
                                             + (["--clean-roots"] if roots else [])), self.state)
        return result, run.call_args_list

    def test_confirmed_cleanup_and_gc(self):
        result, calls = self.run_cleanup()
        self.assertEqual(result, 0)
        self.assertEqual(calls[0].args[0], ["nix-env", "--profile", str(self.profile),
                                          "--delete-generations", "2", "8"])
        self.assertEqual(calls[1].args[0], ["nix-store", "--gc"])
        self.assertTrue(all(call.kwargs["check"] for call in calls))

    def test_cancel_and_eof_do_nothing(self):
        for answer in ["", "n", "no"]:
            result, calls = self.run_cleanup(answer)
            self.assertEqual(result, 1)
            self.assertEqual(calls, [])
        def eof(_):
            raise EOFError
        self.assertEqual(self.run_cleanup(eof), (1, []))

    def test_profile_failure_prevents_gc(self):
        root, target = self.root("result-dev")
        for clean_roots in [False, True]:
            with self.subTest(clean_roots=clean_roots):
                with self.assertRaises(subprocess.CalledProcessError) as failure:
                    self.run_cleanup(roots=clean_roots, fail=True)
                command = ["nix-env", "--profile", str(self.profile),
                           "--delete-generations", "2", "8"]
                self.assertEqual(failure.exception.cmd, command)
                self.subprocess_run.assert_called_once_with(command, check=True)
                self.assertTrue(root.is_symlink())
                self.assertTrue(target.is_symlink())

    def test_selected_generation_changed_during_confirmation(self):
        def select(_):
            self.profile.unlink()
            self.profile.symlink_to("system-2-link")
            return "yes"
        _, calls = self.run_cleanup(select)
        self.assertEqual(calls[0].args[0][-1:], ["8"])

    def root(self, name, destination="/nix/store/example"):
        target = self.state / "project" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.symlink_to(destination)
        os.utime(target, (100, 100), follow_symlinks=False)
        registrations = self.state / "gcroots/auto"
        registrations.mkdir(parents=True, exist_ok=True)
        root = registrations / str(len(list(registrations.iterdir())))
        root.symlink_to(target)
        return root, target

    def test_roots_require_opt_in_and_preserve_project_links(self):
        root, target = self.root("result-dev")
        direnv, _ = self.root(".direnv/flake-profile-1-link")
        for name in ["current-home", "current-system", "manual"]:
            registration, _ = self.root(name)
            self.assertFalse(ngc.root_is_old(registration, 900))
        self.run_cleanup()
        self.assertTrue(root.is_symlink())
        self.run_cleanup(roots=True)
        self.assertFalse(root.is_symlink())
        self.assertFalse(direnv.is_symlink())
        self.assertTrue(target.is_symlink())

    def test_recent_and_unrelated_roots_survive(self):
        root, target = self.root("result", "/tmp/not-a-store-path")
        self.assertFalse(ngc.root_is_old(root, 900))
        recent, target = self.root("result-bin")
        os.utime(target, (950, 950), follow_symlinks=False)
        self.assertFalse(ngc.root_is_old(recent, 900))
        missing = self.state / "gcroots/auto/missing"
        missing.symlink_to(self.state / "absent")
        self.assertFalse(ngc.root_is_old(missing, 900))


unittest.main()
