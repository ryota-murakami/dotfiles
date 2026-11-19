#!/usr/bin/env python3
"""Set every user skill and command to "name-only" in Claude Code's skillOverrides.

Why it exists: a skill installed after the last sync shows its full description in every
session's skill listing, and entries for removed skills pile up in settings.json. Doing this
by hand misses skills, so this script compares the folders on disk with the settings file.
Called by the claude-skill-name-only SKILL.md procedure and by scripts/test_sync.py.

Usage:
  sync.py [--apply] [--keep NAME ...] [--config-dir DIR]

Without --apply it only prints the plan. Result line (last line of output):
  UP TO DATE   nothing to add or remove
  DRY RUN      changes are listed above; rerun with --apply to write them
  APPLIED      settings.json was rewritten with the changes listed above
Exit status 1, with a message on stderr, when settings.json is missing or is not a JSON object.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path

NAME_ONLY = "name-only"


def skill_name(skill_md: Path) -> str:
    """Return the name Claude Code lists a skill under, which skillOverrides keys must match.

    Called by find_user_skills for each SKILL.md it finds.

    Args:
        skill_md: Path to a skill's SKILL.md.

    Returns:
        The frontmatter `name`, or the folder name when the frontmatter has none.
    """
    text = skill_md.read_text(encoding="utf-8", errors="replace")
    frontmatter = re.match(r"---\s*\n(.*?)\n---", text, re.S)
    # Only the YAML block at the top names the skill; a "name:" further down is body text
    if frontmatter:
        name = re.search(r"^name:\s*(.+?)\s*$", frontmatter.group(1), re.M)
        if name:
            return name.group(1).strip("'\"")
    return skill_md.parent.name


def find_user_skills(skills_dir: Path) -> set[str]:
    """List the user skills Claude Code loads from the skills folder.

    Called by main to know which skills should be name-only.

    Args:
        skills_dir: The `skills` folder of the Claude Code config dir.

    Returns:
        Names of the folders (or links to folders) that hold a SKILL.md.
    """
    names: set[str] = set()
    if not skills_dir.is_dir():
        return names
    for entry in skills_dir.iterdir():
        # Skip hidden entries, loose files, and folders or broken links without a SKILL.md
        if entry.name.startswith(".") or not (entry / "SKILL.md").is_file():
            continue
        names.add(skill_name(entry / "SKILL.md"))
    return names


def find_commands(commands_dir: Path) -> set[str]:
    """List the user commands, which Claude Code lists among skills and skillOverrides also hides.

    Called by main next to find_user_skills.

    Args:
        commands_dir: The `commands` folder of the Claude Code config dir.

    Returns:
        Command names; a command in a subfolder is "folder:name" (sc/research.md -> sc:research).
    """
    names: set[str] = set()
    if not commands_dir.is_dir():
        return names
    for md in commands_dir.rglob("*.md"):
        parts = md.relative_to(commands_dir).with_suffix("").parts
        # Hidden files and folders are not commands
        if any(part.startswith(".") for part in parts):
            continue
        names.add(":".join(parts))
    return names


def load_settings(path: Path) -> dict:
    """Read settings.json, stopping the run before anything is written when it cannot be used.

    Called once by main.

    Args:
        path: Path to settings.json.

    Returns:
        The parsed settings object.

    Raises:
        SystemExit: The file is missing, is not valid JSON, or is not a JSON object.
    """
    try:
        settings = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        sys.exit(f"sync.py: {path} does not exist")
    except json.JSONDecodeError as error:
        sys.exit(f"sync.py: {path} is not valid JSON ({error}); fix it first, nothing was written")
    if not isinstance(settings, dict):
        sys.exit(f"sync.py: {path} does not hold a JSON object; nothing was written")
    return settings


def write_atomically(path: Path, text: str) -> None:
    """Replace a file in one step so a running Claude Code never reads half a settings.json.

    Called by main with --apply. A symlinked settings.json is written through to its target.

    Args:
        path: The file to replace.
        text: The new content.
    """
    target = Path(os.path.realpath(path))
    mode = target.stat().st_mode & 0o777
    fd, tmp = tempfile.mkstemp(dir=target.parent, prefix=".settings.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, target)
    except BaseException:
        # Leave no temp file behind when the write fails
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def print_section(mark: str, title: str, lines: list[str]) -> None:
    """Print one group of the plan, one entry per line, so it is easy to read and to grep."""
    print(f"{mark} {title} ({len(lines)})")
    for line in lines:
        print(f"{mark} {line}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description='Set every user skill and command to "name-only" in skillOverrides.'
    )
    parser.add_argument("--apply", action="store_true", help="write the changes (default: only print them)")
    parser.add_argument(
        "--keep",
        action="append",
        default=[],
        metavar="NAME",
        help="keep this name-only entry although no user skill or command has the name (bundled skills); repeatable",
    )
    parser.add_argument(
        "--config-dir",
        type=Path,
        default=Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude"),
        help="Claude Code config dir (default: $CLAUDE_CONFIG_DIR or ~/.claude)",
    )
    args = parser.parse_args(argv)

    settings_path = args.config_dir / "settings.json"
    settings = load_settings(settings_path)
    overrides = settings.get("skillOverrides") or {}
    user_skills = find_user_skills(args.config_dir / "skills")
    commands = find_commands(args.config_dir / "commands")
    existing = user_skills | commands

    to_add = sorted(existing - overrides.keys())
    to_remove = sorted(
        name
        for name, value in overrides.items()
        if value == NAME_ONLY and name not in existing and name not in args.keep
    )
    left_as_set = sorted(f"{name}: {value}" for name, value in overrides.items() if value != NAME_ONLY)

    print(f"user skills: {len(user_skills)}, commands: {len(commands)}, skillOverrides entries: {len(overrides)}")
    print_section("+", "add as name-only", to_add)
    print_section("-", "remove: name-only entries with no user skill or command of that name", to_remove)
    print_section("=", "left as set: entries with another value", left_as_set)

    # Nothing to change: leave the file alone, even its formatting
    if not to_add and not to_remove:
        print("UP TO DATE")
        return 0
    if not args.apply:
        print("DRY RUN: rerun with --apply to write these changes")
        return 0

    updated = {name: value for name, value in overrides.items() if name not in to_remove}
    updated.update({name: NAME_ONLY for name in to_add})
    settings["skillOverrides"] = dict(sorted(updated.items()))
    write_atomically(settings_path, json.dumps(settings, indent=2, ensure_ascii=False) + "\n")
    print(f"APPLIED: {settings_path} now has {len(updated)} skillOverrides entries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
