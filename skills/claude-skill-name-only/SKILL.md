---
name: claude-skill-name-only
description: |
  Set every user skill in ~/.claude/skills and every command in ~/.claude/commands to "name-only" in the skillOverrides of ~/.claude/settings.json, and drop name-only entries whose skill no longer exists.
  Use when: skills were installed or removed and the name-only list needs refreshing, or the user wants skill descriptions hidden from the listing to save context.
  Keywords: name-only, skillOverrides, sync skill overrides, スキルをname-onlyに, name-onlyを最新に, skillOverridesを更新, スキルの説明を隠す.
argument-hint: "[--keep <name> ...]"
---

# Claude Skill Name-Only

`SYNC=~/.claude/skills/claude-skill-name-only/scripts/sync.py`

`skillOverrides` matches entries by skill name against user skills, commands and bundled skills; `name-only` lists the name without the description. Plugin skills (`plugin:skill`) ignore it, so an entry for one does nothing.

## Steps

1. **Preview**: `python3 -I $SYNC`. `+` lines are skills to add, `-` lines are name-only entries with no user skill or command of that name, `=` lines are entries set to another value, which the script never changes.
2. **Sort the `-` lines.** Keep a bundled skill: it is in this session's skill list without a plugin prefix and has no folder in `~/.claude/skills` (for example `code-review`). Every other `-` entry is a deleted skill or a plugin skill; let it go.
3. **Write**: `python3 -I $SYNC --apply --keep <bundled name> ...`. Only `skillOverrides` changes; it is sorted by name and every other setting stays as it was.
4. **Report** how many entries were added and removed, with the removed names. A new session shows the shorter skill list.
