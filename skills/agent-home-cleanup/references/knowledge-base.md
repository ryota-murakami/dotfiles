# Agent home knowledge base

Last verified: 2026-11-28 with Claude Code 2.1.332 (Claude only); Codex / Cursor last verified 2026-10-24 with
codex-cli 0.164.0, Cursor 3.27.12 / cursor-agent 2026.10.22.
Update this file (and the `*_KNOWN` tables in `scripts/scan.py`) whenever a run finds the docs or binaries changed.

## Contents
1. Claude Code (`~/.claude`)
2. Codex (`~/.codex`)
3. Cursor (`~/.cursor`)
4. Verification commands
5. Pitfalls
6. Findings log

---

## 1. Claude Code (`~/.claude`)

Source: https://code.claude.com/docs/en/claude-directory.md ("Application data") and
https://code.claude.com/docs/en/plugins/loading.md.

**Auto-cleaned by Claude Code** (after `cleanupPeriodDays`, default 30): `projects/<p>/<session>.jsonl`, `subagents/`,
`tool-results/`, `file-history/`, `plans/`, `debug/`, `paste-cache/`, `image-cache/`, `uploads/`, `session-env/`,
`tasks/`, `shell-snapshots/`, `backups/` (keeps the 5 newest `~/.claude.json` copies), `feedback-bundles/`, `feedback/drafts/`,
`usage-data/`, `dev-mods/<session>/`, `skills/.trash/`, `plugins/.trash/`, `plugins/data/.set-aside/`, `plugins/mcpb/`,
`plugins/installed_plugins.{set-aside,unreadable}.*`. `sessions/` and `seed-admin/` are removed when the session or upload
ends (crash leftovers on the next launch). You do not need to clean these by hand.
Also auto-swept (docs, 2026-11): `projects/<p>/<session>/mcp-tasks/`, `projects/<p>/<session>.orphaned-<ts>-<suffix>.jsonl`,
`projects/<p>/<session>.jsonl.superseded-<ts>`. Auto memory `projects/<p>/memory/` is never swept.

**User retention rule (2026-11-28)**: transcripts idle >= 14 days are staged by this skill (`scan.py`
`TRANSCRIPT_MAX_AGE_DAYS`, re-checked by `stage.sh` `TRANSCRIPT_MIN_AGE_DAYS`). A session is the group `<id>.jsonl` +
`<id>/` + set-aside copies; age is the newest mtime in the group; `memory/`, other files and running sessions
(`sessions/*.json` → `sessionId`) are excluded. Claude Code only; `cleanupPeriodDays` stays unset on purpose.

**Legacy, no longer written** (docs): `todos/`, `statsig/`, `logs/`, and `image-cache/` (only written by <= 2.1.274), so delete them if present. **`downloads/` is not legacy**:
2.1.330 still uses it (`R="downloads"` beside `x-download-token`) and recreates it (verified 2026-11-22).

**Kept until you delete them**: `history.jsonl`, `stats-cache.json`, `remote-settings.json`, `cache/changelog.md`,
`policy-limits.json(.stamp.json)`.

**State files to keep** (docs): `.credentials.json`, `agent-memory/`, `jobs/`, `daemon/`.

**Binary-verified runtime files** (strings on the claude binary): `.sidecar/`, `.last-cleanup`, `.last-update-result.json`,
`mcp-needs-auth-cache.json`, `gh-pr-status-cache.json`, `state/mcp-discover-verdicts.json`, `daemon.log`,
`plugins/plugin-catalog-cache.json`, `plugins/plugin-directory-cache-v2.json`, `plugins/.last_inuse_sweep`, `plugins/blocklist.json`,
`plugins/plugin-directory-bindings.json`, `plugins/store/` (2.1.332, per-plugin key/value store; keep).
Docs-listed plugin files: `known_marketplaces_claudeai.json`, `flagged-plugins.json`.

**Plugins**: `plugins/installed_plugins.json` is the install record. After an update or uninstall, the old version dir gets
`.orphaned_at` (epoch ms) and is swept 14 days later, but only while at least one plugin is installed. You may
delete orphaned dirs by hand (the docs say so), but keep ones orphaned in the last ~48h, because a running session may still
have them loaded. `plugins/data/<id>/` is `${CLAUDE_PLUGIN_DATA}`. If its plugin is gone, the data dir is a remnant.
`claude plugin prune` removes orphaned plugin *dependencies*.
Each version dir has an `.in_use/` directory holding one file per PID of a session that loaded it (binary constant
`Ay=".in_use"`). An orphaned version whose `.in_use/` is empty is not loaded anywhere, so it is safe even inside 48h.

**User customizations** (keep): `CLAUDE.md`, `settings.json`, `settings.local.json`, `rules/`, `skills/`, `commands/`,
`agents/`, `output-styles/`, `workflows/`, `themes/`, `keybindings.json`, hooks and statusline scripts referenced by `settings.json`.

## 2. Codex (`~/.codex`)

Sources: https://developers.openai.com/codex/config-advanced (config and state locations),
https://learn.chatgpt.com/docs/config-file/environment-variables.md (`CODEX_HOME`, `CODEX_SQLITE_HOME`),
`openai/codex` `codex-rs/state/src/sqlite.rs` (DB filenames).

**Core runtime DBs** live at the `CODEX_HOME` root: `state_N`, `logs_N`, `goals_N`, `memories_N`, `thread_history_N`
(+ `queue_N`, `memories_v2_N`), each with `-shm`/`-wal`. The number changes with migrations, so a lower number than the
current one is superseded. Copies of these under `sqlite/` are stale duplicates (an older Desktop build used a second
SQLite home). The Desktop app itself only uses `sqlite/codex-dev.db` (and `codex-thread-summaries-dev.db`).

**Plaintext logs**: `codex-tui.log` is opt-in via `log_dir`, so a `log/` dir from older versions or old notify scripts is legacy.

**App-maintained, keep**: `.codex-global-state.json` **and** `.codex-global-state.json.bak` (rewritten on every save),
`chrome-native-hosts-v2.json` (the v1 `chrome-native-hosts.json` is superseded), `.tmp/` (marketplaces, locks),
`tmp/arg0*` (the older `tmp/path/` is legacy), `packages/`, `vendor_imports/`, `plugins/cache/{openai-bundled,
openai-curated-remote,openai-primary-runtime,created-by-me-remote}` (managed by the app).

**Plugins**: config entries look like `[plugins."<name>@<marketplace>"] enabled = true|false`. A cache dir with no entry
is a probable remnant (HOLD, because the app may manage it). A disabled plugin with an entry is the user's choice, so keep it.

**Worktrees**: Codex app worktrees live at `worktrees/<id>/<repo>/`. After the checkout is removed, `<id>/.codex-worktree-name`
can remain; the app may use it for restore, so HOLD it.

**config.toml**: every directory Codex runs in gets `[projects."<path>"] trust_level = ...`. Temp workspaces
(`/private/var/folders/.../T/...`) pile up; `prune_codex_projects.py` removes the ones whose dir no longer exists.
Profiles live in `<name>.config.toml` (since 0.134 `[profiles.x]` in config.toml is ignored, so treat it as legacy if found).

## 3. Cursor (`~/.cursor`)

No official directory reference exists, so verify against the binaries.

- `.gitignore` has a `CURSOR MANAGED BLOCK` written by Cursor (it controls what the agent can read); do not edit it.
- Extensions: `extensions/extensions.json` lists the installed ones; `extensions/.obsolete` lists dirs pending removal.
  A dir that is in `.obsolete` is safe to delete. A dir in neither is a sideload or dev install, so HOLD it.
- Plugins (2026-10): the current cache is `plugins/cache/cursor-public`; cursor-agent reads `plugins/local-marketplaces.json`.
  The old January-2026 format (`plugins/installed.json`, `plugins/marketplaces.json`, `plugins/marketplaces/`, and caches named
  after Claude marketplaces) is not referenced by Cursor or cursor-agent, so it is legacy.
- `worktrees/<repo>/<3-letter id>/` holds parallel-agent worktrees. Check whether each one is still registered in the parent repo.
- `snapshots/` (bare git repos, early 2026) was not referenced by current builds and was removed in the 2026-10 run.

## 4. Verification commands

```bash
# Is a filename still used by the Claude binary?
strings "$(readlink -f "$(which claude)")" | grep -c '<name>'
# cursor-agent (single bundle file; keep the search narrow so it can't hang)
rg -o --max-count 3 '.{50}<name>.{50}' ~/.local/share/cursor-agent/versions/*/index.js
# Cursor IDE: search one file at a time with a timeout
timeout 90 rg -o --max-count 3 '.{60}"<name>".{40}' /Applications/Cursor.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js
# Who has it open?
lsof -- <file>        # or: lsof +D <dir>
# What does git know?
git -C ~/.claude ls-files <path>; git -C <parent> worktree list
```

## 5. Pitfalls

- **fish shell**: no heredocs and no `$(...)` substitution in fish (fish uses `(...)`). Run helpers as `bash script.sh` / `python3 -c`.
  An unmatched glob is an error in fish, so quote globs or run them inside `bash -c`.
- **~/.Trash and TCC**: macOS privacy controls can make globbing `~/.Trash/*` return nothing from a terminal. Always pass the exact
  staging path to `purge.sh`.
- **Live apps rewrite files**: Codex rewrites `config.toml` and `.codex-global-state.json*`, and Claude rewrites `~/.claude.json`.
  Edit `config.toml` only through the atomic `prune_codex_projects.py` (it aborts if the file changed meanwhile).
- **Tracked files in dotfile repos**: deleting them shows up as `D` in `git status`; step 9 (`commit-homes.sh`) commits them.
- **Git layout (2026-11-28)**: `~/.claude` already has a private GitHub remote (see `git -C ~/.claude remote -v`;
  its `.gitignore` is a `/*` + `!/...` allowlist). `~/.codex`, `~/.cursor` and `~/.agents` are local repos with no remote
  yet; step 9 creates `<owner>/{codex,cursor,agents}-home` (private) on the next run that cleans them.
  History scans before those first pushes found only low-value API keys in config files, which the user accepts, so
  they are listed as accepted and the push proceeds.
  `~/.cursor` has ~44k untracked, not-ignored files (Cursor's managed block un-ignores `projects/`) and `~/.codex` ~137,
  so never `git add -A` there. `~/.claude/.husky/pre-commit` (`pnpm lint-staged`) is inactive: `core.hooksPath` is unset
  and there is no `package.json`.
- **Don't trust "untracked = disposable"**: user-authored files can be untracked, and remnants can be tracked.

## 6. Findings log

### 2026-11-28 (Claude Code only, 2.1.332; transcript, backup and commit rules added)
- **User rules added this run**: Claude transcripts idle >= 14 days are SAFE; backup copies are SAFE at any age (config
  is in git); every run ends with `commit-homes.sh` (commit + push to a private remote). The last two apply to all tools.
- **Same unknown backup writer in Codex**: `~/.codex/hooks.json.bak.<ts>.<pid>.<rand>` + `hooks.json.bak-latest` follow
  the exact pattern of Claude's `settings.json.bak.*`, so it is one tool that installs hooks into both homes. Lead (not
  verified): `~/.codex/config.toml.rea.backup` points at the REA installer.
- **Transcripts >= 14 days**: 39 paths / 3.87 GB in 8 projects (idle 15-24 days); 7.7 GB of `projects/` is newer.
- **`syntax-cmd/runners.json`** is now a remnant: `claude-syntax-cmd` was replaced by `syntax-highlight@laststance`, whose
  README says the old file "is not read any more". Its own state is `syntax-highlight/runners.json` (keep).
- **`settings.json.bak-latest`** is a 74-byte pointer to the newest `settings.json.bak.<ts>.<pid>.<rand>`; both are written
  together (same minute), so it is the same unknown writer. Still not found in OpenClaw, the skills or the plugin caches.
- **`tools/agent-proxy/`** is user-authored and tracked (payload audit proxy), keep.
- Stray files directly in `projects/` (`x.diff`) or beside sessions (`memory-backup-*.tgz`, `memory-audit-*/`,
  `vercel-plugin/`) are not session artifacts; never stage them under the transcript rule.

### 2026-11-22 (Claude Code only, 2.5 MB; 8.1 of 8.4 GB is `projects/`)
- **`plugins/cache/temp_git_<epoch ms>_<id>/`**: clones (here `mattpocock/skills`) left by a marketplace add that did not finish,
  not in `known_marketplaces.json`. Stage the whole dir; the scanner used to list its children as plugins.
- **A plugin dir not in `installed_plugins.json` can hold a version orphaned < 48h ago**: staging the dir takes that version too.
  The scanner now holds such a dir.
- **Third-party state beside `settings.json`**: `settings.json.break-delegate-backups/` + `settings.json.break-delegate-owner.sqlite`
  belong to the OpenClaw `break-delegate` extension (`~/.openclaw/extensions/break-delegate/dist/settings.js`), whose hooks are in
  `settings.json`; `syntax-cmd/runners.json` belongs to the `claude-syntax-cmd` plugin. Keep both while installed.
- **`settings.json.bak.<YYYYMMDD-HHMMSS>.<pid>.<random>`**: full copies of `settings.json`, many per day; the tool that writes
  them was not found (not the Claude binary, the skills, OpenClaw or the laststance plugins). The ones under a day old are held.

### 2026-10-24 (first run, ~1.4 GB + 15 GB worktrees)
- **ECC (Everything Claude Code) remnants** after the plugin was uninstalled: `~/.claude/{.agents,.codex,.cursor,.opencode}/`,
  `homunculus/`, `mcp-configs/`, `metrics/`, `session-data/`, `scripts/{hooks,lib,setup-package-manager.js}`, `README.md`,
  `PLUGIN_SCHEMA_NOTES.md`, `hooks/README.md`, `.env.crosspost`. Signature: all created at the same minute (Mar 25).
- **Uninstalled plugin data**: `~/.claude/security/` (security-guidance Python venv, 266 MB), `context-mode/`,
  `vercel-plugin-device-id`, `vercel-plugin-telemetry-preference`, `plugins/data/<disabled-plugin>/`.
- **Backups**: `settings.json.bak*` / `.cm-setup-bak-*` (a setup tool backs up Claude + Codex configs together),
  `config.toml.{backup,cm-setup-bak,cua-backup,nogic.bak}*`, `mcp.json.cua-backup-*`, `hooks.json.bak`,
  `skills.directory-migration-*.json` + `skills.symlink-backup-*`.
- **Third-party leftovers**: `config/notification_states.json` (Claude-Code-Usage-Monitor, Python timestamps), `.nogic/`
  (Nogic extension uninstalled), `openclaw-repair-<date>/` (OpenClaw repair backup, unrelated to Claude).
- **Codex**: stale `sqlite/{state_5,logs_2,goals_1,memories_1}.sqlite*` (191 MB, untouched for 4 months), unreferenced `mcp/xmcp`,
  `mcp/elevenlabs` (160 MB), `log/`, `tmp/path/`, `.tmp/git-*`, `chrome-native-hosts.json` v1, 94 temp `[projects]` entries,
  15 GB of worktrees (all HEADs were contained in branches; one had a 1-line `AGENTS.md` diff).
- **Cursor**: Jan-2026 plugin format (`plugins/installed.json`, `marketplaces/`, Claude marketplace caches), `snapshots/`,
  orphaned `worktrees/daykey/*`, `-l` (empty file from a mistyped `touch -l`-style command), `.DS_Store`.
