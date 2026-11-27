---
name: agent-home-cleanup
description: Audit and clean the global AI-agent homes ~/.claude, ~/.codex and ~/.cursor down to "what a clean install of the latest Claude Code / Codex / Cursor would contain, plus the user's own customizations". Finds legacy files from older CLI versions, *.bak and other backup copies, uninstalled MCP servers and plugin remnants, orphaned plugin versions, stale SQLite duplicates, Claude Code transcripts idle 14+ days, leftover agent worktrees and plain junk; keeps newer transcripts, credentials and customizations (settings.json, config.toml, mcp.json, skills, agents, hooks, statusline). Stages deletions in the Trash with a restore manifest, lists risky items for a decision, then commits and pushes each home's git repo. Use whenever the user asks to clean up, tidy, slim down or free space in ~/.claude, ~/.codex or ~/.cursor, or says things like "クリーンアップして", "レガシーなファイルを消したい", ".bak を削除", "使っていない MCP / Plugin を整理", "クリーンインストール相当にしたい", "~/.codex が肥大化している" - even if only one of the three tools is named.
---

# Agent Home Cleanup

Bring `~/.claude`, `~/.codex` and `~/.cursor` back to the state a clean install of the current CLIs would create, without losing anything the user made or wants to keep. Being reversible matters more than being thorough here, because these directories hold credentials and months of transcripts, and the apps rewrite some files while running.

`SKILL_DIR=~/.agents/skills/agent-home-cleanup` (scripts are bash/python3: call them with `bash` / `python3` explicitly, because the user's shell may be fish).

## Codex Compatibility
In Codex, use `update_plan` instead of TodoWrite and ask questions in chat (or `request_user_input`). Paths and scripts are the same.

## Cursor Compatibility
In Cursor Agent, use `AskQuestion` for decisions and the built-in todo list. Paths and scripts are the same.

## What to never touch

Leave these alone: deleting them loses user data or breaks login, and a clean install would not remove them either.

- Transcripts and history: `~/.claude/projects/`, `history.jsonl`, `~/.codex/sessions/`, `archived_sessions/`, `thread_history_*.sqlite`, `~/.cursor/chats/`, `~/.cursor/projects/`. The one exception is Claude Code transcripts idle for 14 days or more (see "Transcript retention" below).
- Credentials: `~/.claude/.credentials.json`, `~/.codex/auth.json`
- User configuration and its content: `settings.json`, `config.toml`, `mcp.json`, `hooks.json`, `CLAUDE.md` / `AGENTS.md`, and everything in `skills/`, `agents/`, `commands/`, `rules/`. Do not edit entries inside these files unless the user explicitly says to.
- Official state the docs say to keep: `~/.claude/jobs/`, `daemon/`, `agent-memory/`; Codex `memories*`, `sqlite/codex-dev.db`, `.codex-global-state.json(.bak)`, migration markers (`.personality_migration`, `.sandbox_migration`)
- Anything referenced from `settings.json` hooks / statusLine, `config.toml` (`notify`, `mcp_servers`), `mcp.json`, shell rc files, LaunchAgents or crontab

`stage.sh` refuses the most important of these on its own, but that check is only a backstop, not permission to skip verification.

## Transcript retention (Claude Code only)

The user keeps Claude Code transcripts for 14 days. Claude Code's own sweep waits `cleanupPeriodDays` (default 30), so each cleanup run removes the ones in between. This is the same deletion that sweep does, so `claude --resume` simply stops listing them.

- **What counts as one session**: in `~/.claude/projects/<project>/`, the entries that share a session id: `<id>.jsonl`, `<id>/` (subagents, tool-results, mcp-tasks) and the set-aside copies `<id>.orphaned-*.jsonl` / `<id>.jsonl.superseded-*`. Stage the whole group or none of it.
- **Age**: the newest mtime anywhere in the group. Resuming a session can touch only its subdirectory, so the top-level mtime alone would make an active session look idle.
- **Never**: `projects/<project>/memory/` (auto memory), anything else in `projects/` (memory backups, audits, stray files go to HOLD), a session listed in `~/.claude/sessions/*.json` (running), and Codex or Cursor transcripts.
- `scan.py` reports these as SAFE (`TRANSCRIPT_MAX_AGE_DAYS`), and `stage.sh` re-checks age and running state (`TRANSCRIPT_MIN_AGE_DAYS`) so a hand-written list cannot stage a live transcript. Change both constants together.
- Do not change `cleanupPeriodDays` in `settings.json` unless the user asks: the user chose to apply the rule only when this skill runs.

## Backups and git (all tools)

The user keeps the agent homes' configuration in git (`~/.claude` pushes to a private GitHub repo), so git already holds every earlier version. Two rules follow, for every tool:

- **Backup copies are SAFE at any age**, including ones written today: names with `bak` / `backup` / `.orig` / `.old`, and date-stamped copies of a sibling (`settings.json.20261127-080453`). Do not hold them as "a repair in progress" or "an intentional backup with a README". `scan.py` already classifies them this way. The exception is a folder that only has "backup" in its name but is state an installed tool still reads (for example `settings.json.break-delegate-backups/`, which OpenClaw break-delegate restores from while its hooks are in `settings.json`). Keep that kind of folder.
- **Every run ends with a commit and push** of each home you cleaned (step 9). A home with no remote gets a new private GitHub repo first. Without this, the deleted backups would have no copy left outside this machine.

## Workflow

### 1. Preflight
- Record versions: `claude --version`, `codex --version`, `cursor-agent --version`.
- Run `git -C ~/.claude status --short` (and the same for `.codex` / `.cursor`). These homes are dotfile repos. Note the changes that were already pending: step 9 commits them together with the cleanup, so list them in the report.
- Note which apps are running (`pgrep -fl "Claude|Codex|ChatGPT|Cursor"`), so you know which files they may hold open.

### 2. Refresh official knowledge
The tools change monthly, so check the current docs before trusting the built-in lists:
- Claude Code: fetch `https://code.claude.com/docs/en/claude-directory.md` and read the "Application data" section ("Cleaned up automatically", "Kept until you delete them", "State files to keep", legacy dirs). For the plugin cache, read `https://code.claude.com/docs/en/plugins/loading.md` (cleanup of previous versions).
- Codex: read `https://developers.openai.com/codex/config-advanced` (config and state locations) and the DB filenames in `codex-rs/state/src/sqlite.rs` on `openai/codex` main.
- Cursor has no directory reference. Verify file names against the installed binaries instead (commands in `references/knowledge-base.md`).

If something changed, update `references/knowledge-base.md` and the `*_KNOWN` tables in `scripts/scan.py`, so the next run starts from correct data.

### 3. Scan (read-only)
```bash
python3 $SKILL_DIR/scripts/scan.py                # markdown: SAFE / HOLD / UNKNOWN
python3 $SKILL_DIR/scripts/scan.py --json > /tmp/agent-home-scan.json
```
The scanner classifies every top-level entry plus deep checks (plugin caches, orphaned versions, stale DBs, extensions, worktrees, unreferenced MCP or hook assets). Treat its output as leads, not verdicts.

### 4. Verify every non-KEEP item
For each SAFE and UNKNOWN item, find out what created it and whether anything still reads it:
- **Origin**: read the file or dir (README, first lines, timestamps). Several entries created at the same moment usually come from one installer, such as an uninstalled plugin that copied files.
- **References**: `grep -rl "<name>" ~/.claude/settings.json ~/.claude.json ~/.codex/config.toml ~/.cursor/mcp.json ~/.cursor/hooks.json ~/.config/fish ~/.zshrc ~/Library/LaunchAgents`, plus `crontab -l`.
- **Still used by the app?** `strings "$(readlink -f "$(which claude)")" | grep -c '<name>'`, or `rg -o '.{40}<name>.{40}'` over `~/.local/share/cursor-agent/versions/<v>/index.js` and Cursor.app (narrow the search to a single file, because greping the whole bundle can hang).
- **Open right now?** `lsof -- <file>`.
- **Symlinks pointing in**: `find ~/.agents ~/.claude/skills ~/.codex/skills ~/.cursor/skills -maxdepth 3 -type l` and resolve them.
- **Installed?** `claude plugin list`, the `[plugins]` entries in `config.toml`, `extensions/extensions.json`, `/Applications`.

Transcript findings (`session transcript idle …`) need no per-item origin research: check the count, the total size and that no `memory/` path is in the list.

Move an item to HOLD when it is user-authored, possibly secret (`.env*`, keys), a git worktree, or still unexplained after research. Backup copies are never held (see "Backups and git").

### 5. Stage the SAFE set (reversible)
Write the verified paths to a file, run a dry run, then stage:
```bash
bash $SKILL_DIR/scripts/stage.sh --dry-run /tmp/agent-home-safe.txt
bash $SKILL_DIR/scripts/stage.sh /tmp/agent-home-safe.txt
```
This moves the items to `~/.Trash/agent-home-cleanup-<stamp>/<path relative to ~>` and writes a `MANIFEST.tsv` (original path → trash path, size). Undo the whole set or part of it with `bash $SKILL_DIR/scripts/restore.sh <staging> [filter]`.

### 6. Verify nothing broke
- `claude --version`, `codex --version`, `cursor-agent --version`, and `claude plugin list` (should still show the installed plugins)
- Parse the configs: `python3 -c "import json;json.load(open('$HOME/.claude/settings.json'))"`, `python3 -c "import tomllib;tomllib.load(open('$HOME/.codex/config.toml','rb'))"`
- `git status --short` in each home, so you can report tracked deletions

If something fails, restore the related entries before doing anything else.

### 7. Report (in the user's language)
Use this structure:
```
# 🧹 Cleanup result
<N items / size> staged → <staging path> (restore: MANIFEST.tsv / restore.sh). Verified: <checks>.
## 🗑️ Staged
Grouped per tool and per reason (old transcripts: sessions / projects / size, backups, legacy, uninstalled plugin remnants, orphaned versions, junk).
## ⏸️ Hold (needs your decision)
One bullet per item: path (size) - what it is, why it is held, recommended action.
## Notes
What step 9 will commit per home (tracked deletions, changes that were already pending, new config files), what was intentionally kept (transcripts newer than 14 days, auto memory, jobs/daemon), what was not emptied yet.
```

### 8. After the user decides ("全て削除" or per item)
- Worktrees: `bash $SKILL_DIR/scripts/remove-worktrees.sh <paths>` prints what would be lost: uncommitted files, and whether HEAD is in any branch. Show that to the user if it is not trivial, then rerun with `--yes`. This removes the worktree through git and prunes the parent repos.
- Stale Codex trust entries: run `python3 $SKILL_DIR/scripts/prune_codex_projects.py` as a dry run, then `--apply`. It writes atomically and keeps a backup in `/tmp`.
- Other HOLD items: `rm -rf` the exact paths once they are approved.
- Purge the staging folder with `bash $SKILL_DIR/scripts/purge.sh <exact staging path>`. Pass the full path rather than a glob: macOS privacy controls can make globs under `~/.Trash` match nothing.
- Re-run step 6 and report the final sizes (`du -sh ~/.claude ~/.codex ~/.cursor`).

### 9. Commit and push (always, last)
Run this for each home you cleaned, plus `~/.agents` (the shared skills repo this skill lives in, so its own updates are pushed too), even when the cleanup moved only untracked files:
```bash
bash $SKILL_DIR/scripts/commit-homes.sh --dry-run ~/.claude ~/.agents   # add ~/.codex ~/.cursor when you cleaned them
bash $SKILL_DIR/scripts/commit-homes.sh ~/.claude ~/.agents
```
- **What it stages**: tracked changes (`git add -u`: cleanup deletions plus edits that were already pending) and new files under user-config paths only (`skills/`, `agents/`, `commands/`, `rules/`, `hooks/`, `CLAUDE.md`, `settings.json`, `config.toml`, `mcp.json`, …). Never `git add -A` by hand: `~/.cursor`'s Cursor-managed `.gitignore` un-ignores `projects/` (tens of thousands of agent files), and `~/.codex` has untracked sessions and logs.
- **No remote yet → it creates one**: a repo without an upstream gets a new **private** GitHub repo `<owner>/<home without the dot>-home` (`codex-home`, `cursor-home`, `agents-home`) as `origin`, then `push -u`. The owner is `$AGENT_HOME_GH_OWNER` or the active gh account. Check `gh auth status` first: the active account must be the one that should own these backups (see the user's CLAUDE.md). An existing repo with that name is reused only if it is private.
- **Safety it enforces**: it skips untracked files with secret-looking names, build artifacts or files over 5 MB. gitleaks scans the staged diff before every commit, and the **whole history** before a first push, because that push publishes every old commit. It pushes only to a PRIVATE remote and never force-pushes. When the remote is ahead, it rebases once and stops if that fails.
- **Secrets policy (user decision, 2026-11-28)**: low-value API keys in agent config are accepted, because the remotes are private. So ordinary findings (`generic-api-key`, `perplexity-api-key`, …) are listed as "accepted" and do not block. Only credentials that grant account access or spend money block that repo (`HIGH_IMPACT_RE`: GitHub/GitLab tokens, AWS/GCP/Azure, private keys, Stripe, Slack, OpenAI/Anthropic, npm/PyPI). List accepted findings in the report (file, rule, commit; never the value). Do not suggest moving keys to a secret manager or rewriting history for them. For a blocked one, report it and ask the user.
- Read the dry run before the real run. It also prints the history scan result for homes without a remote. If it would add something that is not configuration (generated eval outputs, caches), add that path to the home's `.gitignore` first, or ask the user.
- Report the commit hash, push result and any new repo URL for each home.

## Reference
- `references/knowledge-base.md`: per-tool keep/legacy lists with sources, binary-verified file names, past findings (useful patterns such as remnants of uninstalled plugin installers), and known pitfalls. Read it before classifying UNKNOWN items.
