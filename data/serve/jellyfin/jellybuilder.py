#!/usr/bin/env python3
"""Build a Jellyfin-friendly media tree from the NAS media library."""

from __future__ import annotations

import argparse
import fnmatch
import logging
import os
import re
import runpy
import shutil
import sys
import types
import xml.etree.ElementTree as ET
from collections import defaultdict
from collections.abc import Iterable, Sequence
from pathlib import Path
from typing import Any

LOGGER = logging.getLogger("jellybuilder")
VIDEO_PATTERNS = ("*.mkv", "*.avi")
MOVIE_PATTERNS = (*VIDEO_PATTERNS, "*.mp4", "*.srt")


def natural_key(value: str | Path) -> tuple[tuple[int, int | str], ...]:
    """Return a case-insensitive key with digit runs compared numerically."""
    return tuple(
        (0, int(part)) if part.isdigit() else (1, part.casefold())
        for part in re.split(r"(\d+)", os.fspath(value))
        if part
    )


def natural_sorted(values: Iterable[Any]) -> list[Any]:
    return sorted(values, key=natural_key)


def esort(values: Iterable[Any], start: int = 1) -> enumerate:
    """Compatibility helper exposed to legacy jellylink.py files."""
    return enumerate(natural_sorted(values), start=start)


def chainglob(path: str | Path, patterns: Sequence[str]) -> Iterable[Path]:
    """Compatibility helper exposed to legacy jellylink.py files."""
    root = Path(path)
    for pattern in patterns:
        yield from root.glob(pattern)


def find_relative_files(root: str | Path, *patterns: str) -> list[Path]:
    """Find matching files recursively and return naturally sorted relative paths."""
    base = Path(root)
    if not base.is_dir():
        raise FileNotFoundError(f"Directory not found: {base}")
    if not patterns:
        raise ValueError("At least one file pattern is required")

    matches = {
        path.relative_to(base)
        for path in base.rglob("*")
        if path.is_file()
        and any(
            fnmatch.fnmatch(path.name.casefold(), pattern.casefold())
            for pattern in patterns
        )
    }
    return natural_sorted(matches)


def remove_dangling_symlinks(directory: str | Path) -> int:
    """Remove dangling symlinks below directory."""
    root = Path(directory)
    if not root.is_dir():
        raise FileNotFoundError(f"Directory not found: {root}")

    removed = 0
    for path in root.rglob("*"):
        if path.is_symlink() and not path.exists():
            LOGGER.debug("Removing dangling symlink: %s", path)
            path.unlink()
            removed += 1
    return removed


def _same_link(destination: Path, source: Path) -> bool:
    if not destination.is_symlink():
        return False
    return destination.resolve(strict=False) == source.resolve(strict=False)


def link_file(source: Path, destination: Path, overwrite: bool) -> None:
    """Create an absolute symlink, rejecting ambiguous name collisions."""
    if not source.is_file():
        raise FileNotFoundError(f"Source file not found: {source}")

    if _same_link(destination, source):
        LOGGER.debug("Link already correct: %s", destination)
        return

    if destination.is_symlink() or destination.exists():
        if not overwrite:
            raise FileExistsError(
                f"Destination collision: {destination} does not link to {source}; "
                "rerun with --overwrite to replace it"
            )
        if destination.is_dir() and not destination.is_symlink():
            raise IsADirectoryError(f"Refusing to replace directory: {destination}")
        destination.unlink()

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.symlink_to(source.resolve())
    LOGGER.debug("Linked %s -> %s", destination, source)


def link_directory(source: Path, destination: Path, overwrite: bool) -> None:
    if not source.is_dir():
        raise FileNotFoundError(f"Source directory not found: {source}")
    if _same_link(destination, source):
        LOGGER.debug("Directory link already correct: %s", destination)
        return
    if destination.is_symlink() or destination.exists():
        if not overwrite:
            LOGGER.info("Destination already exists; skipping: %s", destination)
            return
        if destination.is_dir() and not destination.is_symlink():
            raise IsADirectoryError(f"Refusing to replace directory: {destination}")
        destination.unlink()
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.symlink_to(source.resolve(), target_is_directory=True)
    LOGGER.debug("Linked %s -> %s", destination, source)


def _write_xml(path: Path, root: ET.Element) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(root, space="  ")
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def write_tvshow(
    file_path: Path,
    title: str,
    poster: str = "",
    studios: list[str] | None = None,
    genres: list[str] | None = None,
    tags: list[str] | None = None,
    originaltitle: str = "",
) -> None:
    root = ET.Element("tvshow")
    ET.SubElement(root, "title").text = title
    if originaltitle:
        ET.SubElement(root, "originaltitle").text = originaltitle
    if poster:
        ET.SubElement(root, "thumb", {"aspect": "poster"}).text = poster
    for studio in studios or []:
        ET.SubElement(root, "studio").text = studio
    for genre in genres or []:
        ET.SubElement(root, "genre").text = genre
    for tag in tags or []:
        ET.SubElement(root, "tag").text = tag
    _write_xml(file_path, root)


def write_season(
    file_path: Path,
    title: str,
    seasonnumber: int,
    originaltitle: str = "",
    sortname: str = "",
) -> None:
    root = ET.Element("season")
    ET.SubElement(root, "title").text = title
    if originaltitle:
        ET.SubElement(root, "originaltitle").text = originaltitle
    ET.SubElement(root, "seasonnumber").text = str(seasonnumber)
    if sortname:
        ET.SubElement(root, "sortname").text = sortname
    _write_xml(file_path, root)


def write_episode(
    file_path: Path,
    title: str,
    season: int,
    episode: int,
    originaltitle: str = "",
    sortname: str = "",
) -> None:
    root = ET.Element("episodedetails")
    ET.SubElement(root, "title").text = title
    if originaltitle:
        ET.SubElement(root, "originaltitle").text = originaltitle
    if sortname:
        ET.SubElement(root, "sortname").text = sortname
    ET.SubElement(root, "season").text = str(season)
    ET.SubElement(root, "episode").text = str(episode)
    _write_xml(file_path, root)


def _write_unless_present(
    path: Path, overwrite: bool, writer: Any, **kwargs: Any
) -> None:
    if path.exists() and not overwrite:
        LOGGER.debug("Metadata already exists; skipping: %s", path)
        return
    writer(file_path=path, **kwargs)
    LOGGER.debug("Wrote metadata: %s", path)


def _copy_tvshow_metadata(source: Path, destination: Path, overwrite: bool) -> None:
    if not source.is_file():
        return
    if destination.exists() and not overwrite:
        LOGGER.debug("TV show metadata already exists; skipping: %s", destination)
        return
    if destination.is_symlink() or destination.exists():
        destination.unlink()
    shutil.copy2(source, destination)
    LOGGER.debug("Copied metadata: %s", destination)


def _anime_season_title(relative_parent: Path) -> str:
    if relative_parent == Path("."):
        return "Root"
    return re.sub(r"^\d+\s+", "", relative_parent.as_posix()).replace("/", " - ")


def process_anime(source_root: Path, destination_root: Path, overwrite: bool) -> None:
    source = source_root / "Anime"
    destination = destination_root / "Anime"
    if not source.is_dir():
        raise FileNotFoundError(f"Anime source directory not found: {source}")
    destination.mkdir(parents=True, exist_ok=True)
    remove_dangling_symlinks(destination)

    for show_source in natural_sorted(
        path for path in source.iterdir() if path.is_dir()
    ):
        LOGGER.info("Processing anime: %s", show_source.name)
        show_destination = destination / show_source.name
        show_destination.mkdir(exist_ok=True)

        poster_source = show_source / "poster.jpg"
        poster_destination = show_destination / "poster.jpg"
        if poster_source.is_file():
            link_file(poster_source, poster_destination, overwrite)

        source_tvshow = show_source / "tvshow.nfo"
        destination_tvshow = show_destination / "tvshow.nfo"
        if source_tvshow.is_file():
            _copy_tvshow_metadata(source_tvshow, destination_tvshow, overwrite)
        else:
            _write_unless_present(
                destination_tvshow,
                overwrite,
                write_tvshow,
                title=show_source.name,
                poster="poster.jpg" if poster_destination.exists() else "",
            )

        episodes_by_parent: dict[Path, list[Path]] = defaultdict(list)
        for relative_episode in find_relative_files(show_source, *VIDEO_PATTERNS):
            episodes_by_parent[relative_episode.parent].append(relative_episode)

        for season_number, relative_parent in enumerate(
            natural_sorted(episodes_by_parent), start=1
        ):
            season_title = _anime_season_title(relative_parent)
            season_destination = show_destination / f"Season {season_number:02d}"
            season_destination.mkdir(exist_ok=True)
            _write_unless_present(
                season_destination / "season.nfo",
                overwrite,
                write_season,
                title=season_title,
                seasonnumber=season_number,
                sortname=f"{season_number:02d} {season_title}",
            )

            for episode_number, relative_episode in enumerate(
                natural_sorted(episodes_by_parent[relative_parent]), start=1
            ):
                episode_source = show_source / relative_episode
                episode_destination = season_destination / (
                    f"{show_source.name} - S{season_number:02d}E{episode_number:02d}"
                    f"{episode_source.suffix}"
                )
                _write_unless_present(
                    episode_destination.with_suffix(".nfo"),
                    overwrite,
                    write_episode,
                    title=episode_destination.name,
                    season=season_number,
                    episode=episode_number,
                    originaltitle=episode_source.name,
                    sortname=episode_destination.name,
                )
                link_file(episode_source, episode_destination, overwrite)


def process_movies(source_root: Path, destination_root: Path, overwrite: bool) -> None:
    source = source_root / "Movies"
    destination = destination_root / "Movies"
    if not source.is_dir():
        raise FileNotFoundError(f"Movie source directory not found: {source}")
    destination.mkdir(parents=True, exist_ok=True)
    remove_dangling_symlinks(destination)
    for relative_movie in find_relative_files(source, *MOVIE_PATTERNS):
        link_file(source / relative_movie, destination / relative_movie.name, overwrite)


def process_music(source_root: Path, destination_root: Path, overwrite: bool) -> None:
    link_directory(
        source_root / "Music" / "Library-squashed",
        destination_root / "Music",
        overwrite,
    )


def _legacy_nfo_module() -> types.ModuleType:
    module = types.ModuleType("nfo")
    module.write_tvshow = write_tvshow
    module.write_season = write_season
    module.write_episode = write_episode
    return module


def _legacy_common(source_root: Path, destination_root: Path) -> types.SimpleNamespace:
    return types.SimpleNamespace(
        PATH_NAS=source_root,
        PATH_LOCAL=destination_root,
        chainglob=chainglob,
        esort=esort,
        find_relative_files=find_relative_files,
        remove_dangling_symlinks=remove_dangling_symlinks,
    )


def _run_jellylink(
    script: Path,
    destination: Path,
    source_root: Path,
    destination_root: Path,
    overwrite: bool,
) -> None:
    LOGGER.info("Processing show rules: %s", script.parent)
    nfo_module = _legacy_nfo_module()
    previous_nfo = sys.modules.get("nfo")
    sys.modules["nfo"] = nfo_module
    try:
        namespace = runpy.run_path(
            script,
            init_globals={
                "common": _legacy_common(source_root, destination_root),
                "Path": Path,
                "nfo": nfo_module,
            },
        )
        process = namespace.get("process")
        if not callable(process):
            raise ValueError(f"No callable process function defined in {script}")
        process(script.parent, destination, overwrite)
    finally:
        if previous_nfo is None:
            del sys.modules["nfo"]
        else:
            sys.modules["nfo"] = previous_nfo


def process_shows(source_root: Path, destination_root: Path, overwrite: bool) -> None:
    source = source_root / "Shows"
    destination = destination_root / "Shows"
    if not source.is_dir():
        raise FileNotFoundError(f"Shows source directory not found: {source}")
    destination.mkdir(parents=True, exist_ok=True)
    remove_dangling_symlinks(destination)
    scripts = natural_sorted(source.rglob("jellylink.py"))
    LOGGER.debug("Found %d jellylink.py file(s) in %s", len(scripts), source)
    for script in scripts:
        _run_jellylink(script, destination, source_root, destination_root, overwrite)


PROCESSORS = {
    "anime": process_anime,
    "movies": process_movies,
    "shows": process_shows,
    "music": process_music,
}


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    source_default = os.environ.get("JELLYBUILDER_SOURCE")
    destination_default = os.environ.get("JELLYBUILDER_DESTINATION")
    parser = argparse.ArgumentParser(
        description="Build a Jellyfin-friendly alias tree from a media library.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--src",
        "--source",
        dest="source",
        type=Path,
        default=Path(source_default) if source_default else None,
        required=source_default is None,
        help="media source root",
    )
    parser.add_argument(
        "--dest",
        "--destination",
        dest="destination",
        type=Path,
        default=Path(destination_default) if destination_default else None,
        required=destination_default is None,
        help="Jellyfin alias-library root",
    )
    parser.add_argument(
        "--target",
        choices=("all", *PROCESSORS),
        default="all",
        help="media category to process",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="replace conflicting links and generated metadata",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="show each filesystem operation",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    source = args.source.expanduser()
    destination = args.destination.expanduser()
    if not source.is_dir():
        raise FileNotFoundError(f"Media source directory not found: {source}")
    destination.mkdir(parents=True, exist_ok=True)

    targets = (
        PROCESSORS if args.target == "all" else {args.target: PROCESSORS[args.target]}
    )
    LOGGER.info(
        "Building %s from %s into %s",
        ", ".join(targets),
        source,
        destination,
    )
    for processor in targets.values():
        processor(source, destination, args.overwrite)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, FileExistsError, IsADirectoryError, ValueError) as error:
        LOGGER.error("%s", error)
        raise SystemExit(1) from error
