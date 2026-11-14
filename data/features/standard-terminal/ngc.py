"""Prune Nix profile history, then collect unreachable store paths."""

import argparse
import os
from pathlib import Path
import pwd
import re
import subprocess
import sys
import time

ELEVATE = "@elevate@"
GENERATION = re.compile(r"(.+)-(\d+)-link")


def duration(value):
    match = re.fullmatch(r"(\d+)([smhdw])", value)
    if not match:
        raise argparse.ArgumentTypeError("use an integer followed by s, m, h, d, or w")
    return int(match[1]) * dict(s=1, m=60, h=3600, d=86400, w=604800)[match[2]]


def keep_count(value):
    if not re.fullmatch(r"[0-9]+", value) or int(value) < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return int(value)


def arguments(argv):
    parser = argparse.ArgumentParser(
        description="Prune profile generations, then run nix-store --gc. "
        "Always previews removals and asks for confirmation. "
        "Store GC collects ALL unreachable paths, regardless of age.",
    )
    parser.add_argument("--older-than", type=duration, default="14d", metavar="AGE",
                        help="remove generations older than AGE, e.g. 12h or 14d (default: 14d)")
    parser.add_argument("--keep-last", type=keep_count, default=5, metavar="N",
                        help="keep at least the newest N generations per profile (default: 5)")
    parser.add_argument("--clean-roots", action="store_true",
                        help="also unregister build-result and direnv roots older than AGE; "
                        "does not remove project symlinks or manual roots")
    return parser.parse_args(argv)


def entries(directory):
    try:
        return sorted(directory.iterdir())
    except FileNotFoundError:
        return []


def profile_directories(state):
    directories = {state / "profiles"}
    homes = {Path.home()}
    if os.geteuid() == 0:
        directories.update(p for p in entries(state / "profiles/per-user") if p.is_dir())
        homes.update(Path(user.pw_dir) for user in pwd.getpwall() if user.pw_dir.startswith("/"))
    else:
        directories.add(state / "profiles/per-user" / pwd.getpwuid(os.geteuid()).pw_name)
    # Inspect only known profile directories, never recursively search homes.
    directories.update(home / ".local/state/nix/profiles" for home in homes)
    if os.environ.get("XDG_STATE_HOME"):
        directories.add(Path(os.environ["XDG_STATE_HOME"]) / "nix/profiles")
    return sorted(directories)


def generations_to_remove(directory, cutoff, keep):
    groups = {}
    for path in entries(directory):
        match = GENERATION.fullmatch(path.name)
        if match and path.is_symlink():
            groups.setdefault(match[1], []).append((int(match[2]), path))
    plan = {}
    for name, generations in groups.items():
        profile = directory / name
        if not profile.is_symlink():
            continue
        selected = Path(os.readlink(profile)).name
        generations.sort(reverse=True)
        removable = [number for number, path in generations[keep:]
                     if path.name != selected and path.lstat().st_mtime < cutoff]
        if removable:
            plan[profile] = removable
    return plan


def root_is_old(registration, cutoff):
    if not registration.is_symlink():
        return False
    target = Path(os.readlink(registration))
    if not target.is_absolute():
        target = registration.parent / target
    if not target.is_symlink() or target.lstat().st_mtime >= cutoff:
        return False
    # Match nh's ephemeral root classes, not current-home or current-system.
    direnv = re.search(r"/(?:\.direnv|direnv/layouts)/", str(target))
    destination = Path(os.readlink(target))
    result = re.fullmatch(r"result(?:-.*)?", target.name)
    return bool(direnv or (result and destination.parent == Path("/nix/store")))


def cleanup(args, state):
    cutoff = time.time() - args.older_than
    plans = {}
    for directory in profile_directories(state):
        plans.update(generations_to_remove(directory, cutoff, args.keep_last))
    roots = [p for p in entries(state / "gcroots/auto") if root_is_old(p, cutoff)] if args.clean_roots else []
    print(f"Keep newest {args.keep_last} generations per profile, all generations "
          f"within {args.older_than} seconds, and each selected generation.")
    for profile, numbers in plans.items():
        print(f"Prune {profile}: {', '.join(map(str, numbers))}")
    for root in roots:
        print(f"Unregister {root} -> {os.readlink(root)}")
    print("Then collect ALL unreachable store paths. Collected paths may need to be rebuilt or downloaded.")
    try:
        confirmed = input("Proceed? [y/N] ").strip().lower() in {"y", "yes"}
    except EOFError:
        confirmed = False
    if not confirmed:
        print("Cancelled.")
        return 1
    for profile, numbers in plans.items():
        # Refresh after confirmation. Nix also locks the profile and refuses to
        # delete its selected generation if activation races with this command.
        refreshed = generations_to_remove(profile.parent, cutoff, args.keep_last)
        numbers = sorted(set(numbers) & set(refreshed.get(profile, [])))
        if numbers:
            subprocess.run(["nix-env", "--profile", str(profile), "--delete-generations",
                            *map(str, numbers)], check=True)
    for root in roots:
        if root_is_old(root, cutoff):
            root.unlink()
    subprocess.run(["nix-store", "--gc"], check=True)
    return 0


def main(argv=None):
    args = arguments(argv)
    if ELEVATE and os.geteuid() != 0:
        # Preserve a custom caller profile directory across elevation.
        return subprocess.run([ELEVATE, "--preserve-env=XDG_STATE_HOME,NIX_STATE_DIR",
                               sys.executable, __file__, *sys.argv[1:]]).returncode
    return cleanup(args, Path(os.environ.get("NIX_STATE_DIR", "/nix/var/nix")))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"ngc: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
