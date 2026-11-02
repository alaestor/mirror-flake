from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


SCRIPT = Path(
    os.environ.get(
        "JELLYBUILDER_SCRIPT",
        Path(__file__).parents[2] / "data/serve/jellyfin/jellybuilder.py",
    )
)
SPEC = importlib.util.spec_from_file_location("jellybuilder", SCRIPT)
assert SPEC and SPEC.loader
jellybuilder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(jellybuilder)


class JellybuilderTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        root = Path(self.temporary_directory.name)
        self.source = root / "source"
        self.destination = root / "destination"
        self.source.mkdir()
        self.destination.mkdir()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def touch(self, relative_path: str, content: str = "") -> Path:
        path = self.source / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_anime_generates_natural_episode_order_and_metadata(self) -> None:
        episode_10 = self.touch("Anime/Example/01 First/episode 10.mp4")
        episode_2 = self.touch("Anime/Example/01 First/episode 2.mkv")
        poster = self.touch("Anime/Example/poster.jpg")

        jellybuilder.process_anime(self.source, self.destination, overwrite=False)

        season = self.destination / "Anime/Example/Season 01"
        self.assertEqual(
            (season / "Example - S01E01.mkv").resolve(), episode_2.resolve()
        )
        self.assertEqual(
            (season / "Example - S01E02.mp4").resolve(), episode_10.resolve()
        )
        self.assertEqual(
            (self.destination / "Anime/Example/poster.jpg").resolve(), poster.resolve()
        )
        self.assertEqual(ET.parse(season / "season.nfo").findtext("title"), "First")
        episode_nfo = ET.parse(season / "Example - S01E01.nfo")
        self.assertEqual(episode_nfo.findtext("episode"), "1")
        self.assertEqual(episode_nfo.findtext("originaltitle"), "episode 2.mkv")

    def test_source_tvshow_metadata_is_preserved(self) -> None:
        source_nfo = self.touch("Anime/Example/tvshow.nfo", "<tvshow />")
        self.touch("Anime/Example/episode.mkv")

        jellybuilder.process_anime(self.source, self.destination, overwrite=False)

        destination_nfo = self.destination / "Anime/Example/tvshow.nfo"
        self.assertFalse(destination_nfo.is_symlink())
        self.assertEqual(destination_nfo.read_bytes(), source_nfo.read_bytes())

    def test_music_alias_is_idempotent(self) -> None:
        music = self.source / "Music/Library-squashed"
        music.mkdir(parents=True)

        jellybuilder.process_music(self.source, self.destination, overwrite=False)
        jellybuilder.process_music(self.source, self.destination, overwrite=False)

        alias = self.destination / "Music"
        self.assertTrue(alias.is_symlink())
        self.assertEqual(alias.resolve(), music.resolve())

    def test_legacy_show_rule_receives_common_and_nfo_modules(self) -> None:
        episode = self.touch("Shows/Example/episode.mkv")
        self.touch(
            "Shows/Example/jellylink.py",
            """
import nfo

def process(here, output_root, overwrite):
    output = output_root / "Example"
    output.mkdir(parents=True)
    common.esort(["episode 10", "episode 2"])
    (output / "episode.mkv").symlink_to(here / "episode.mkv")
    nfo.write_episode(output / "episode.nfo", "Episode", 1, 1)
""",
        )
        jellybuilder.process_shows(self.source, self.destination, overwrite=False)

        show = self.destination / "Shows/Example"
        self.assertEqual((show / "episode.mkv").resolve(), episode.resolve())
        self.assertEqual(ET.parse(show / "episode.nfo").findtext("title"), "Episode")

    def test_legacy_show_rule_can_import_jellybuilder_common(self) -> None:
        episode = self.touch("Shows/Example/episode.mkv")
        self.touch(
            "Shows/Example/jellylink.py",
            """
from jellybuilder_common import PATH_NAS, PATH_LOCAL, esort

def process(here, output_root, overwrite):
    assert PATH_NAS.name == "source"
    assert PATH_LOCAL.name == "destination"
    assert [value for _, value in esort(["episode 10", "episode 2"])] == ["episode 2", "episode 10"]
    output = output_root / "Example"
    output.mkdir()
    (output / "episode.mkv").symlink_to(here / "episode.mkv")
""",
        )

        jellybuilder.process_shows(self.source, self.destination, overwrite=False)

        self.assertEqual(
            (self.destination / "Shows/Example/episode.mkv").resolve(), episode.resolve()
        )
        self.assertFalse((self.destination / "Shows/Shows").exists())

    def test_link_collision_requires_explicit_overwrite(self) -> None:
        source = self.touch("episode.mkv", "media")
        destination = self.destination / "episode.mkv"
        destination.write_text("keep me")

        with self.assertRaises(FileExistsError):
            jellybuilder.link_file(source, destination, overwrite=False)
        self.assertEqual(destination.read_text(), "keep me")

        jellybuilder.link_file(source, destination, overwrite=True)
        self.assertTrue(destination.is_symlink())
        self.assertEqual(destination.resolve(), source)
        self.assertEqual(source.read_text(), "media")

    def test_overwrite_cannot_remove_real_directories(self) -> None:
        source = self.touch("episode.mkv")
        destination = self.destination / "episode.mkv"
        destination.mkdir()
        protected = destination / "keep.txt"
        protected.write_text("keep me")

        with self.assertRaises(IsADirectoryError):
            jellybuilder.link_file(source, destination, overwrite=True)
        self.assertEqual(protected.read_text(), "keep me")

    def test_cleanup_removes_only_dangling_links(self) -> None:
        source = self.touch("episode.mkv")
        live = self.destination / "live.mkv"
        live.symlink_to(source)
        stale = self.destination / "stale.mkv"
        stale.symlink_to(self.source / "missing.mkv")
        ordinary = self.destination / "keep.txt"
        ordinary.write_text("keep me")

        self.assertEqual(jellybuilder.remove_dangling_symlinks(self.destination), 1)
        self.assertFalse(stale.is_symlink())
        self.assertEqual(live.resolve(), source)
        self.assertEqual(ordinary.read_text(), "keep me")


if __name__ == "__main__":
    unittest.main()
