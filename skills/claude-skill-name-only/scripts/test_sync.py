#!/usr/bin/env python3
"""Behavior tests for sync.py, run as a CLI against a throwaway Claude Code config dir.

Run with: python3 -I scripts/test_sync.py (scripts/check does this).
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SYNC = Path(__file__).resolve().parent / "sync.py"


def make_skill(config_dir: Path, folder: str, frontmatter_name: str | None = None) -> None:
    """Create ~/.claude/skills/<folder>/SKILL.md, optionally with a frontmatter name."""
    skill_dir = config_dir / "skills" / folder
    skill_dir.mkdir(parents=True)
    name_line = f"name: {frontmatter_name}\n" if frontmatter_name else ""
    (skill_dir / "SKILL.md").write_text(f"---\n{name_line}description: test skill\n---\n\n# Body\n")


def write_settings(config_dir: Path, settings: dict) -> None:
    (config_dir / "settings.json").write_text(json.dumps(settings, indent=2) + "\n")


def read_settings(config_dir: Path) -> dict:
    return json.loads((config_dir / "settings.json").read_text())


def run_sync(config_dir: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-I", str(SYNC), "--config-dir", str(config_dir), *args],
        capture_output=True,
        text=True,
        check=True,
    )


class SyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.config_dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_newly_installed_user_skill_becomes_name_only(self) -> None:
        # Arrange
        make_skill(self.config_dir, "old-skill")
        make_skill(self.config_dir, "new-skill")
        write_settings(self.config_dir, {"skillOverrides": {"old-skill": "name-only"}})

        # Act
        run_sync(self.config_dir, "--apply")

        # Assert
        self.assertEqual(
            read_settings(self.config_dir)["skillOverrides"],
            {"new-skill": "name-only", "old-skill": "name-only"},
        )

    def test_skill_is_listed_under_its_frontmatter_name_not_its_folder(self) -> None:
        # Arrange
        make_skill(self.config_dir, "folder-name", frontmatter_name="real-name")
        write_settings(self.config_dir, {})

        # Act
        run_sync(self.config_dir, "--apply")

        # Assert
        self.assertEqual(read_settings(self.config_dir)["skillOverrides"], {"real-name": "name-only"})

    def test_name_only_entry_of_a_deleted_skill_is_removed(self) -> None:
        # Arrange
        make_skill(self.config_dir, "still-here")
        write_settings(
            self.config_dir,
            {"skillOverrides": {"deleted-skill": "name-only", "still-here": "name-only"}},
        )

        # Act
        run_sync(self.config_dir, "--apply")

        # Assert
        self.assertEqual(read_settings(self.config_dir)["skillOverrides"], {"still-here": "name-only"})

    def test_bundled_skill_passed_with_keep_stays_name_only(self) -> None:
        # Arrange
        write_settings(self.config_dir, {"skillOverrides": {"code-review": "name-only"}})

        # Act
        run_sync(self.config_dir, "--apply", "--keep", "code-review")

        # Assert
        self.assertEqual(read_settings(self.config_dir)["skillOverrides"], {"code-review": "name-only"})

    def test_entries_the_user_set_to_another_value_are_never_changed(self) -> None:
        # Arrange
        make_skill(self.config_dir, "turned-off")
        make_skill(self.config_dir, "slash-only")
        write_settings(
            self.config_dir,
            {"skillOverrides": {"turned-off": "off", "slash-only": "user-invocable-only", "gone": "off"}},
        )

        # Act
        run_sync(self.config_dir, "--apply")

        # Assert
        self.assertEqual(
            read_settings(self.config_dir)["skillOverrides"],
            {"turned-off": "off", "slash-only": "user-invocable-only", "gone": "off"},
        )

    def test_command_in_a_subfolder_is_added_as_folder_colon_name(self) -> None:
        # Arrange
        (self.config_dir / "commands" / "sc").mkdir(parents=True)
        (self.config_dir / "commands" / "sc" / "research.md").write_text("Research a topic\n")
        (self.config_dir / "commands" / "recap.md").write_text("Recap the session\n")
        write_settings(self.config_dir, {})

        # Act
        run_sync(self.config_dir, "--apply")

        # Assert
        self.assertEqual(
            read_settings(self.config_dir)["skillOverrides"],
            {"recap": "name-only", "sc:research": "name-only"},
        )

    def test_folders_without_skill_md_and_broken_links_are_not_skills(self) -> None:
        # Arrange
        (self.config_dir / "skills" / "notes-only").mkdir(parents=True)
        (self.config_dir / "skills" / "notes-only" / "README.md").write_text("not a skill\n")
        (self.config_dir / "skills" / "broken-link").symlink_to(self.config_dir / "missing")
        make_skill(self.config_dir, "real-skill")
        write_settings(self.config_dir, {})

        # Act
        run_sync(self.config_dir, "--apply")

        # Assert
        self.assertEqual(read_settings(self.config_dir)["skillOverrides"], {"real-skill": "name-only"})

    def test_dry_run_reports_the_plan_without_touching_settings_json(self) -> None:
        # Arrange
        make_skill(self.config_dir, "new-skill")
        write_settings(self.config_dir, {"skillOverrides": {"deleted-skill": "name-only"}})
        before = (self.config_dir / "settings.json").read_text()

        # Act
        result = run_sync(self.config_dir)

        # Assert
        self.assertIn("+ new-skill\n", result.stdout)
        self.assertIn("- deleted-skill\n", result.stdout)
        self.assertEqual(result.stdout.splitlines()[-1], "DRY RUN: rerun with --apply to write these changes")
        self.assertEqual((self.config_dir / "settings.json").read_text(), before)

    def test_other_settings_survive_the_rewrite(self) -> None:
        # Arrange
        make_skill(self.config_dir, "new-skill")
        write_settings(
            self.config_dir,
            {"model": "opus", "env": {"FOO": "日本語"}, "skillOverrides": {}, "theme": "dark"},
        )

        # Act
        run_sync(self.config_dir, "--apply")

        # Assert
        self.assertEqual(
            (self.config_dir / "settings.json").read_text(),
            '{\n  "model": "opus",\n  "env": {\n    "FOO": "日本語"\n  },\n'
            '  "skillOverrides": {\n    "new-skill": "name-only"\n  },\n  "theme": "dark"\n}\n',
        )

    def test_invalid_settings_json_stops_without_writing(self) -> None:
        # Arrange
        make_skill(self.config_dir, "new-skill")
        (self.config_dir / "settings.json").write_text('{"model": "opus",}\n')

        # Act
        result = subprocess.run(
            [sys.executable, "-I", str(SYNC), "--config-dir", str(self.config_dir), "--apply"],
            capture_output=True,
            text=True,
        )

        # Assert
        self.assertEqual(result.returncode, 1)
        self.assertIn("is not valid JSON", result.stderr)
        self.assertEqual((self.config_dir / "settings.json").read_text(), '{"model": "opus",}\n')


if __name__ == "__main__":
    unittest.main()
