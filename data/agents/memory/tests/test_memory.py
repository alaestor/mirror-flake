#!/usr/bin/env python3
"""Exercise the public CLI with isolated stores, including refusal paths."""

import concurrent.futures
import contextlib
import importlib.util
import io
import json
import os
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

CLI = Path(
    os.environ.get(
        "MEMORY_CLI", Path(__file__).resolve().parents[1] / "src" / "memory.py"
    )
)
COMMAND = [str(CLI)] if os.environ.get("MEMORY_CLI") else [sys.executable, str(CLI)]


class MemoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "project"
        self.project.mkdir()
        self.store = self.project / ".agents" / "memory"
        self.global_root = self.root / "global"
        self.settings = self.root / "settings.json"
        defaults = Path(__file__).resolve().parents[1] / "settings.json"
        self.defaults = json.loads(defaults.read_text())
        self.settings.write_text(json.dumps(self.defaults))
        self.env = {**os.environ, "AGENT_MEMORY_CONFIG": str(self.settings)}

    def run_cli(self, *args, ok=True, body=None, machine=True):
        command = COMMAND + [
            "--project-root",
            str(self.project),
            "--global-root",
            str(self.global_root),
        ]
        if machine:
            command.append("--json")
        result = subprocess.run(
            command + list(args),
            env=self.env,
            input=body,
            text=True,
            check=False,
            capture_output=True,
            timeout=10,
        )
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertEqual(result.returncode, 2, result.stderr)
        return result

    def data(self, *args, **kwargs):
        return json.loads(self.run_cli(*args, **kwargs).stdout)

    def add(self, ident="project:lesson", body="A surprising constraint.\n"):
        return self.data(
            "add",
            ident,
            "--trigger",
            "When packaging",
            "--file",
            "-",
            body=body,
        )

    def configure(self, **values):
        self.settings.write_text(json.dumps({**self.defaults, **values}))

    def source_module(self):
        source = Path(
            os.environ.get(
                "MEMORY_SOURCE",
                Path(__file__).resolve().parents[1] / "src" / "memory.py",
            )
        )
        spec = importlib.util.spec_from_file_location("memory_under_test", source)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_crlf_is_preserved_and_counted_for_stdin_and_files(self):
        body = "A café constraint.\r\nSecond line.\r\n"
        for name, source in (("stdin", "-"), ("file", str(self.root / "input.md"))):
            if source != "-":
                Path(source).write_bytes(body.encode("utf-8"))
            result = self.data(
                "add", f"project:{name}", "--trigger", "When needed", "--file", source,
                body=body if source == "-" else None,
            )
            self.assertEqual(self.data("show", f"project:{name}")["content"], body)
            self.assertEqual(
                (Path(result["path"]) / "README.md").read_bytes(), body.encode("utf-8")
            )
            self.data(
                "edit", f"project:{name}", "--expect", result["revision"],
                "--file", "-", body=body,
            )
        self.assertEqual(
            self.data("status")[0]["usage"]["content_bytes"], 2 * len(body.encode("utf-8"))
        )

    def test_corrupt_sibling_does_not_hide_results_or_double_feedback(self):
        healthy = self.add()
        broken = self.add("project:broken")
        (Path(broken["path"]) / "README.md").write_text("Changed externally")
        result = self.data("feedback", "project:lesson", "useful")
        self.assertEqual(result["outcome"], "feedback")
        shown = self.data("show", "project:lesson")
        self.assertEqual(shown["feedback"]["useful"], 1)
        self.assertEqual(len(self.data("index")), 2)
        self.assertEqual(len(self.data("search", "constraint")), 1)
        self.assertEqual(len(self.data("search", "broken")), 1)
        (self.store / ".notice.json").unlink()
        self.assertIn("article-damaged", self.run_cli("session", machine=False).stdout)
        self.data(
            "edit", "project:lesson", "--expect", healthy["revision"],
            "--file", "-", body="Healthy replacement.",
        )
        self.data("remove", "project:broken", "--expect", broken["revision"])
        self.assertEqual(self.data("status")[0]["findings"], [])

    def test_failed_notification_preserves_committed_result(self):
        self.add()
        module = self.source_module()
        output, diagnostics = io.StringIO(), io.StringIO()
        with (
            mock.patch.dict(os.environ, self.env),
            mock.patch.object(module.Store, "notify", side_effect=OSError("No space")),
            contextlib.redirect_stdout(output),
            contextlib.redirect_stderr(diagnostics),
        ):
            result = module.main([
                "--project-root", str(self.project), "--json",
                "feedback", "project:lesson", "useful",
            ])
        self.assertEqual(result, 0)
        self.assertEqual(json.loads(output.getvalue())["outcome"], "feedback")
        self.assertIn("maintenance warning failed", diagnostics.getvalue())
        self.assertEqual(self.data("show", "project:lesson")["feedback"]["useful"], 1)

    def test_feedback_rejects_stale_revision_without_changes(self):
        original = self.add()["revision"]
        current = self.data(
            "edit", "project:lesson", "--expect", original, "--file", "-",
            body="Replacement.",
        )["revision"]
        self.run_cli(
            "feedback", "project:lesson", "off-base", "--expect", original,
            ok=False,
        )
        shown = self.data("show", "project:lesson")
        self.assertEqual(shown["feedback"]["off-base"], 0)
        self.assertEqual(shown["events"], [])
        self.data("feedback", "project:lesson", "off-base", "--expect", current)
        self.data("feedback", "project:lesson", "off-base")
        events = self.data("show", "project:lesson")["events"]
        self.assertEqual([event["revision"] for event in events], [current, None])

    def test_missing_stores_are_not_created_by_discovery(self):
        self.assertEqual(self.data("index"), [])
        self.assertFalse(self.store.exists())
        self.assertFalse(self.global_root.exists())

    def test_scopes_do_not_shadow_and_index_is_complete(self):
        self.add()
        self.add("global:lesson")
        self.assertEqual(
            [e["id"] for e in self.data("index")], ["project:lesson", "global:lesson"]
        )
        self.configure(articles=50)
        for i in range(32):
            self.add(f"project:item-{i}")
        self.assertEqual(len(self.data("index")), 34)

    def test_body_search_does_not_count_as_read(self):
        self.add(body="Unique rediscovery.\n")
        self.assertEqual(len(self.data("search", "REDISCOVERY")), 1)
        self.assertEqual(len(self.data("search", "LESSON")), 1)
        self.assertEqual(len(self.data("search", "PACKAGING")), 1)
        self.assertEqual(self.data("usage")[0]["reads"], 0)
        article = self.data("show", "project:lesson")
        self.assertEqual(article["content"], "Unique rediscovery.\n")
        self.assertEqual(article["reads"], 1)
        self.assertEqual(sum(article["feedback"].values()), 0)

    def test_identifier_and_trigger_replace_display_title(self):
        original = self.add()["revision"]
        self.data(
            "edit",
            "project:lesson",
            "--expect",
            original,
            "--trigger",
            "When packaging café",
            "--file",
            "-",
            body="Claim.\n",
        )
        expected = "project:lesson\n  When packaging café\n"
        self.assertEqual(self.run_cli("index", machine=False).stdout, expected)
        self.assertEqual(
            self.data("status")[0]["usage"]["index_bytes"], len(expected.encode())
        )
        self.assertEqual(
            self.data("index"),
            [{"id": "project:lesson", "trigger": "When packaging café"}],
        )
        metadata = self.store / "articles" / "lesson" / "metadata.json"
        self.assertNotIn("title", json.loads(metadata.read_text()))
        self.assertNotIn("title", self.data("show", "project:lesson"))
        self.run_cli(
            "add",
            "project:other",
            "--title",
            "Obsolete",
            "--trigger",
            "When needed",
            "--file",
            "-",
            body="Claim.",
            ok=False,
        )

    def test_edit_is_revision_checked(self):
        original = self.add()["revision"]
        updated = self.data(
            "edit",
            "project:lesson",
            "--expect",
            original,
            "--file",
            "-",
            body="Corrected claim.\n",
        )["revision"]
        self.assertNotEqual(updated, original)
        error = self.run_cli(
            "edit",
            "project:lesson",
            "--expect",
            original,
            "--file",
            "-",
            body="Bad overwrite",
            ok=False,
        )
        self.assertIn("Stale revision", error.stderr)
        self.assertEqual(
            self.data("show", "project:lesson")["content"], "Corrected claim.\n"
        )

    def test_quota_refusal_preserves_stdin_and_store(self):
        original = self.add()["revision"]
        self.configure(content_bytes=30)
        refused = self.run_cli(
            "edit",
            "project:lesson",
            "--expect",
            original,
            "--file",
            "-",
            body="x" * 100,
            ok=False,
        )
        draft = refused.stderr.split("Draft: ", 1)[1].split(
            ". Run memory maintain.", 1
        )[0]
        try:
            self.assertEqual(
                json.loads(Path(draft).read_text()),
                {"trigger": "When packaging", "content": "x" * 100},
            )
            self.assertEqual(Path(draft).stat().st_mode & 0o777, 0o600)
        finally:
            Path(draft).unlink()
        self.assertEqual(self.data("show", "project:lesson")["revision"], original)
        # Shrinking remains possible even if the store is already over budget.
        self.configure(content_bytes=5)
        shorter = self.data(
            "edit",
            "project:lesson",
            "--expect",
            original,
            "--file",
            "-",
            body="Shorter but still over.",
        )
        self.assertNotEqual(shorter["revision"], original)
        self.assertTrue(self.data("status")[0]["findings"])

    def test_article_and_index_limits_are_independent(self):
        self.configure(articles=1)
        self.add()
        refused = self.run_cli(
            "add",
            "project:second",
            "--trigger",
            "When needed",
            "--file",
            "-",
            body="Claim",
            ok=False,
        )
        draft = refused.stderr.split("Draft: ", 1)[1].split(
            ". Run memory maintain.", 1
        )[0]
        Path(draft).unlink()
        self.assertIn("articles", refused.stderr)
        self.configure(index_bytes=1)
        original = self.data("show", "project:lesson")["revision"]
        self.data(
            "edit",
            "project:lesson",
            "--expect",
            original,
            "--trigger",
            "W",
            "--file",
            "-",
            body="Claim",
        )

    def test_feedback_reviews_and_promotions(self):
        self.add()
        self.data(
            "feedback",
            "project:lesson",
            "off-base",
            "--comment",
            "Trigger mismatched the task",
        )
        article = self.data("show", "project:lesson")
        self.assertEqual(article["feedback"]["off-base"], 1)
        self.assertNotIn("confirmed", article)
        self.assertTrue(
            any(f["kind"] == "review" for f in self.data("status")[0]["findings"])
        )
        self.data(
            "resolve",
            "project:lesson",
            article["events"][0]["id"],
            "--note",
            "Trigger corrected",
        )
        self.assertFalse(
            any(f["kind"] == "review" for f in self.data("status")[0]["findings"])
        )
        self.data(
            "propose",
            "project:lesson",
            "--proposal",
            "Add validation to wrapper",
            "--evidence",
            "Same failure reproduced twice",
        )
        self.assertEqual(len(self.data("promotions")), 1)
        self.data(
            "promotion-close",
            "project:lesson",
            "--note",
            "User approved and fixture passes",
        )
        self.assertEqual(self.data("promotions"), [])

    def test_open_review_queue_cannot_grow_unbounded(self):
        self.add()
        for i in range(20):
            self.data(
                "feedback", "project:lesson", "off-base", "--comment", f"Finding {i}"
            )
        self.run_cli("feedback", "project:lesson", "off-base", ok=False)
        article = self.data("show", "project:lesson")
        self.assertEqual(len(article["events"]), 20)
        self.assertEqual(article["feedback"]["off-base"], 20)

    def test_warnings_are_suppressed_but_remain_in_status(self):
        self.configure(article_bytes=5)
        self.add(body="Machine path /home/example/project/source.py")
        result = self.run_cli("show", "project:lesson")
        self.assertEqual(result.stderr, "")
        kinds = {f["kind"] for f in self.data("status")[0]["findings"]}
        self.assertTrue({"article-large", "absolute-path"} <= kinds)
        self.assertIn("fresh-context", self.run_cli("maintain", machine=False).stdout)

    def test_session_injects_findings_without_corrupting_json(self):
        self.add()
        self.configure(article_bytes=5)
        output = self.run_cli("session", machine=False).stdout
        self.assertIn("article-large", output)
        self.assertIn("project:lesson", output)
        self.assertIn("When packaging", self.run_cli("session").stdout)

    def test_invalid_names_config_and_symlinks(self):
        self.run_cli(
            "add",
            "project:../../escape",
            "--trigger",
            "x",
            "--file",
            "-",
            body="x",
            ok=False,
        )
        self.assertFalse(self.store.exists())
        self.configure(articles=0)
        self.run_cli("index", ok=False)
        self.configure()
        self.store.mkdir(parents=True, exist_ok=True)
        outside = self.root / "outside"
        outside.write_text("untouched")
        (self.store / ".notice.json").symlink_to(outside)
        self.run_cli("index", ok=False)
        self.assertEqual(outside.read_text(), "untouched")

    def test_invalid_empty_and_multiline_input(self):
        self.run_cli(
            "add",
            "project:lesson",
            "--trigger",
            "x\ninstruction",
            "--file",
            "-",
            body="x",
            ok=False,
        )
        self.run_cli(
            "add",
            "project:lesson",
            "--trigger",
            "x",
            "--file",
            "-",
            body="  ",
            ok=False,
        )
        self.assertEqual(self.data("index"), [])

    def test_concurrent_edits_allow_exactly_one_winner(self):
        original = self.add()["revision"]

        def edit(i):
            return subprocess.run(
                COMMAND
                + [
                    "--project-root",
                    str(self.project),
                    "--json",
                    "edit",
                    "project:lesson",
                    "--expect",
                    original,
                    "--file",
                    "-",
                ],
                env=self.env,
                input=f"Claim {i}",
                text=True,
                check=False,
                capture_output=True,
            )

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(edit, range(2)))
        self.assertEqual(sorted(r.returncode for r in results), [0, 2])
        self.assertIn(
            self.data("show", "project:lesson")["content"], ["Claim 0", "Claim 1"]
        )

    def test_external_readme_changes_are_detected(self):
        self.add()
        (self.store / "articles" / "lesson" / "README.md").write_text("Changed content")
        failure = self.run_cli("show", "project:lesson", ok=False)
        self.assertIn("Incomplete or externally changed", failure.stderr)

    def test_malformed_metadata_is_rejected_without_traceback(self):
        self.add()
        path = self.store / "articles" / "lesson" / "metadata.json"
        original = json.loads(path.read_text())
        for invalid in ([1], {"version": True}, {}):
            path.write_text(json.dumps(invalid))
            status = self.data("status")[0]
            self.assertEqual(status["findings"][0]["kind"], "article-damaged")
            self.assertEqual(self.data("index")[0]["id"], "project:lesson")
            failure = self.run_cli("show", "project:lesson", ok=False)
            self.assertNotIn("Traceback", failure.stderr)
            self.assertIn("Damaged metadata", failure.stderr)
        original["reads"] = -1
        path.write_text(json.dumps(original))
        self.assertEqual(self.data("usage"), [])
        self.assertEqual(self.data("path", "project:lesson"), str(path.parent))

    def test_orphaned_publication_does_not_block_healthy_articles(self):
        healthy = self.add()
        orphan = self.store / "articles" / "orphan"
        orphan.mkdir()
        (orphan / "README.md").write_bytes(b"Incomplete.")
        staged = self.store / ".publication-orphan" / "article"
        staged.mkdir(parents=True)
        (staged / "README.md").write_bytes(b"Not published.")
        self.assertEqual(len(self.data("index")), 2)
        status = self.data("status")[0]
        self.assertEqual(status["usage"]["articles"], 2)
        self.assertEqual(
            status["usage"]["content_bytes"], len(b"A surprising constraint.\nIncomplete.")
        )
        self.assertEqual(status["findings"][0]["id"], "project:orphan")
        self.assertEqual(self.data("path", "project:orphan"), str(orphan))
        self.add("project:new")
        self.data("remove", "project:lesson", "--expect", healthy["revision"])
        # Recover without deleting evidence or requiring valid metadata.
        orphan.rename(self.root / "recovered-orphan")
        self.assertEqual(self.data("status")[0]["findings"], [])

    def test_interrupted_initial_publication_is_not_discovered(self):
        self.add("project:healthy")
        module = self.source_module()
        atomic = module.atomic

        def fail_metadata(path, data):
            if path.name == "metadata.json":
                raise OSError("Simulated interrupted initial publication")
            atomic(path, data)

        with (
            mock.patch.dict(os.environ, self.env),
            mock.patch.object(module, "atomic", side_effect=fail_metadata),
            mock.patch.object(module, "read_input", return_value="New article."),
        ):
            with self.assertRaises(OSError):
                module.main([
                    "--project-root", str(self.project),
                    "add", "project:lesson", "--trigger", "When needed", "--file", "-",
                ])
        self.assertEqual([entry["id"] for entry in self.data("index")], ["project:healthy"])
        self.assertFalse((self.store / "articles" / "lesson").exists())
        self.assertEqual(list(self.store.glob(".publication-*")), [])
        self.add()

    def test_damaged_notice_does_not_block_discovery(self):
        self.add()
        (self.store / ".notice.json").write_text("{broken")
        result = self.run_cli("index")
        self.assertEqual(len(json.loads(result.stdout)), 1)
        self.assertIn("ignoring damaged warning cooldown", result.stderr)

    def test_interrupted_pair_is_detected_and_can_be_discarded(self):
        original = self.add()["revision"]
        module = self.source_module()
        atomic = module.atomic

        def fail_metadata(path, data):
            if path.name == "metadata.json":
                raise OSError("Simulated interrupted publication")
            atomic(path, data)

        store = module.Store(self.store, "project")
        with (
            store.locked(),
            mock.patch.object(module, "atomic", side_effect=fail_metadata),
        ):
            record = store.entry("lesson").copy()
            store.state["articles"]["lesson"] = record
            with self.assertRaises(OSError):
                store.revision(record, "Uncommitted replacement")
        self.run_cli("show", "project:lesson", ok=False)
        self.data("remove", "project:lesson", "--expect", original)
        self.assertEqual(self.data("index"), [])
        self.add()
        self.assertEqual(len(list((self.store / "articles" / "lesson").iterdir())), 2)

    def test_edits_overwrite_and_removal_reclaims_space(self):
        revision = self.add()["revision"]
        for i in range(3):
            revision = self.data(
                "edit",
                "project:lesson",
                "--expect",
                revision,
                "--file",
                "-",
                body=f"Claim {i}",
            )["revision"]
        self.assertEqual(len(list((self.store / "articles" / "lesson").iterdir())), 2)
        self.run_cli("remove", "project:lesson", "--expect", "stale", ok=False)
        self.data("remove", "project:lesson", "--expect", revision)
        self.assertEqual(list((self.store / "articles").iterdir()), [])
        self.assertEqual(self.data("status")[0]["usage"]["content_bytes"], 0)
        self.add()

    def test_path_and_human_reports(self):
        created = self.add()
        directory = self.store / "articles" / "lesson"
        self.assertEqual(created["path"], str(directory))
        self.assertEqual(self.data("path", "project:lesson"), str(directory))
        self.assertEqual(
            self.run_cli("path", "project:lesson", machine=False).stdout.strip(),
            str(directory),
        )
        self.assertEqual(self.data("usage")[0]["reads"], 0)
        self.assertEqual(self.data("show", "project:lesson")["path"], str(directory))
        self.assertIn(
            str(directory), self.run_cli("show", "project:lesson", machine=False).stdout
        )
        self.assertIn("content_bytes:", self.run_cli("status", machine=False).stdout)
        self.assertIn("reads=", self.run_cli("usage", machine=False).stdout)
        self.assertEqual(self.data("status")[0]["findings"], [])
        self.run_cli("confirm", "project:lesson", ok=False)
        self.run_cli("verify", "project:lesson", ok=False)

    def test_attachments_are_counted_and_survive_readme_edits(self):
        original = self.add()["revision"]
        directory = self.store / "articles" / "lesson"
        supporting = directory / "supporting"
        supporting.mkdir()
        notes = supporting / "notes.md"
        notes.write_bytes(b"Supporting evidence.")
        body = (directory / "README.md").read_bytes()
        total = len(body) + notes.stat().st_size
        self.assertEqual(self.data("status")[0]["usage"]["content_bytes"], total)
        self.configure(content_bytes=total - 1)
        self.assertIn("budget-exceeded", self.run_cli("show", "project:lesson").stderr)
        failure = self.run_cli(
            "edit",
            "project:lesson",
            "--expect",
            original,
            "--file",
            "-",
            body="x" * total,
            ok=False,
        )
        draft = failure.stderr.split("Draft: ", 1)[1].split(
            ". Run memory maintain.", 1
        )[0]
        Path(draft).unlink()
        self.data(
            "edit",
            "project:lesson",
            "--expect",
            original,
            "--file",
            "-",
            body="Shorter.",
        )
        self.assertEqual(notes.read_bytes(), b"Supporting evidence.")

    def test_supporting_scripts_are_never_run_implicitly(self):
        self.add()
        directory = self.store / "articles" / "lesson"
        marker = self.root / "executed"
        verifier = directory / "verify.sh"
        verifier.write_text(
            f"#!/bin/sh\n: > {shlex.quote(str(marker))}\nsh ./checks/first.sh\nsh ./checks/second.sh\n"
        )
        checks = directory / "checks"
        checks.mkdir()
        (checks / "first.sh").write_text("exit 0\n")
        (checks / "second.sh").write_text("exit 7\n")
        for command in (
            "index",
            "session",
            "search",
            "show",
            "path",
            "status",
            "maintain",
            "usage",
        ):
            args = (
                ["project:lesson"]
                if command in ("show", "path")
                else ["claim"]
                if command == "search"
                else []
            )
            self.run_cli(command, *args)
        self.assertFalse(marker.exists())
        # Explicit execution remains an ordinary shell operation, not a CLI protocol.
        result = subprocess.run(["sh", "./verify.sh"], cwd=directory, check=False)
        self.assertEqual(result.returncode, 7)
        self.assertTrue(marker.exists())
        self.data(
            "feedback",
            "project:lesson",
            "off-base",
            "--comment",
            "First assumption holds; second check failed and needs review",
        )
        self.assertTrue(directory.is_dir())
        self.assertEqual(
            self.data("show", "project:lesson")["content"], "A surprising constraint.\n"
        )
        self.assertTrue(
            any(f["kind"] == "review" for f in self.data("status")[0]["findings"])
        )

    def test_removal_deletes_the_directory_without_following_attached_symlinks(self):
        revision = self.add()["revision"]
        self.add("project:sibling")
        directory = self.store / "articles" / "lesson"
        outside = self.root / "outside"
        outside.mkdir()
        sentinel = outside / "keep.txt"
        sentinel.write_text("Do not remove")
        link = directory / "external"
        link.symlink_to(outside, target_is_directory=True)
        nested = directory / "nested"
        nested.mkdir()
        (nested / "helper.sh").write_text("exit 0\n")
        expected = (
            len(b"A surprising constraint.\n") * 2
            + link.lstat().st_size
            + len("exit 0\n")
        )
        self.assertEqual(self.data("status")[0]["usage"]["content_bytes"], expected)
        self.data("remove", "project:lesson", "--expect", revision)
        self.assertFalse(directory.exists())
        self.assertEqual(sentinel.read_text(), "Do not remove")
        self.assertEqual(len(self.data("index")), 1)

    def test_symlinked_memory_directory_and_managed_files_are_refused(self):
        revision = self.add()["revision"]
        directory = self.store / "articles" / "lesson"
        outside = self.root / "outside"
        directory.rename(outside)
        directory.symlink_to(outside, target_is_directory=True)
        self.run_cli("index", ok=False)
        self.run_cli("remove", "project:lesson", "--expect", revision, ok=False)
        self.assertTrue((outside / "README.md").exists())
        directory.unlink()
        outside.rename(directory)
        readme = directory / "README.md"
        readme.unlink()
        readme.symlink_to(self.settings)
        self.run_cli("show", "project:lesson", ok=False)
        self.assertEqual(json.loads(self.settings.read_text()), self.defaults)

    def test_store_local_settings_are_not_consulted(self):
        self.add()
        (self.store / "config.json").write_text('{"articles": 1}')
        self.add("project:second")
        self.assertEqual(
            self.data("status")[0]["limits"]["articles"], self.defaults["articles"]
        )

    def test_prompts_are_readable_without_store(self):
        for topic in (
            "session-start",
            "authoring",
            "curation",
            "feedback",
            "verification",
            "promotion",
            "warnings/open-review",
            "warnings/budget-near",
            "warnings/budget-exceeded",
            "warnings/article-large",
            "warnings/article-damaged",
            "warnings/absolute-path",
        ):
            self.assertTrue(
                self.run_cli("explain", topic, machine=False).stdout.strip()
            )
        self.assertFalse(self.store.exists())
        self.run_cli("explain", "../outside", ok=False)


if __name__ == "__main__":
    unittest.main()
