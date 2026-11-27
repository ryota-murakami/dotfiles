#!/usr/bin/env python3
"""
Read-only scanner for the global AI-agent homes (~/.claude, ~/.codex, ~/.cursor).

Exists so every cleanup run starts from the same evidence instead of ad-hoc `ls`.
Triggered by the agent-home-cleanup skill (step "Scan"); nothing else calls it.
It never modifies the filesystem - it only classifies entries:

  KEEP     official app state, user customizations, transcripts, repo files
  SAFE     verified legacy / backup / orphan / junk, plus Claude Code transcripts idle for
           TRANSCRIPT_MAX_AGE_DAYS (14) - stage these to the Trash
  HOLD     probably removable but needs a human decision (worktrees, secrets, user assets)
  UNKNOWN  not in the knowledge base - research before deciding

@example
    python3 scan.py                      # markdown report (KEEP rows hidden)
    python3 scan.py --all                # include KEEP rows
    python3 scan.py --json > scan.json   # machine-readable
    python3 scan.py --list SAFE > safe.txt   # absolute paths, one per line, for stage.sh
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

HOME = Path.home()
NOW = time.time()

# --------------------------------------------------------------------------------------
# Knowledge base: top-level entries per tool. Values: (class, note).
# Keep in sync with references/knowledge-base.md when official docs change.
# --------------------------------------------------------------------------------------
K, S = "KEEP", "SAFE"
REPO = (K, "dotfiles repo / editor metadata")

CLAUDE_KNOWN: dict[str, tuple[str, str]] = {
    # user-authored config (docs: claude-directory "File reference")
    "CLAUDE.md": (K, "user instructions"), "AGENTS.md": (K, "user instructions"),
    "settings.json": (K, "user settings"), "settings.local.json": (K, "user settings"),
    "keybindings.json": (K, "user keybindings"), "themes": (K, "user themes"),
    "rules": (K, "user rules"), "skills": (K, "user skills"), "commands": (K, "user commands"),
    "agents": (K, "user subagents"), "output-styles": (K, "user output styles"),
    "workflows": (K, "user workflows"), "agent-memory": (K, "subagent memory (docs: keep)"),
    "hooks": (K, "user hooks (deep-checked separately)"),
    # application data (docs: "Application data")
    "projects": (K, "transcripts + auto memory"), "history.jsonl": (K, "prompt history"),
    "file-history": (K, "checkpoints (auto-swept)"), "plans": (K, "plan mode files (auto-swept)"),
    "debug": (K, "debug logs (auto-swept)"), "paste-cache": (K, "auto-swept"),
    "image-cache": (S, "legacy dir, only written by <= 2.1.274 (official docs)"), "uploads": (K, "auto-swept"), "session-env": (K, "auto-swept"),
    "tasks": (K, "auto-swept"), "shell-snapshots": (K, "auto-swept"),
    "backups": (K, "~/.claude.json rotation (keeps 5)"), "feedback-bundles": (K, "official"),
    "feedback": (K, "official drafts queue"), "usage-data": (K, "/insights data"),
    "stats-cache.json": (K, "/usage totals"), "remote-settings.json": (K, "managed settings cache"),
    "cache": (K, "official cache"), "policy-limits.json": (K, "official cache"),
    "policy-limits.json.stamp.json": (K, "official cache"),
    ".credentials.json": (K, "credentials (docs: keep)"), "jobs": (K, "background sessions (docs: keep)"),
    "daemon": (K, "background sessions (docs: keep)"), "daemon.log": (K, "daemon log"),
    "sessions": (K, "running-session markers"), "ide": (K, "IDE lock files"),
    "telemetry": (K, "official"), "plugins": (K, "plugins (deep-checked separately)"),
    "chrome": (K, "Claude in Chrome native host"), "state": (K, "mcp-discover-verdicts (binary-verified)"),
    ".sidecar": (K, "used by Claude binary"), ".last-cleanup": (K, "retention sweep marker"),
    ".last-update-result.json": (K, "auto-update result"), "mcp-needs-auth-cache.json": (K, "cache"),
    "gh-pr-status-cache.json": (K, "PR status cache (binary-verified)"),
    "claude-devtools-config.json": (K, "claude-devtools.app config (third-party, keep if app installed)"),
    "downloads": (K, "file downloads (binary-verified 2.1.330: x-download-token), not legacy"),
    "dev-mods": (K, "mods written during a session (docs: auto-swept)"),
    "seed-admin": (K, "ultrareview / cloud upload scratch (docs: removed when the upload ends)"),
    # third-party state that lives beside settings.json; keep while the tool is installed
    "tools": (K, "user-authored tools (agent-proxy payload audit), tracked in the dotfiles repo"),
    "syntax-highlight": (K, "syntax-highlight@laststance plugin state (runners.json, copied on first use)"),
    "syntax-cmd": (S, "state of the uninstalled claude-syntax-cmd plugin; its successor syntax-highlight no longer reads it"),
    "settings.json.break-delegate-backups": (K, "openclaw break-delegate extension state (its hooks are in settings.json)"),
    "settings.json.break-delegate-owner.sqlite": (K, "openclaw break-delegate extension lock (its hooks are in settings.json)"),
    # legacy (docs: "Legacy directories from older versions. No longer written.")
    "todos": (S, "legacy dir, no longer written (official docs)"),
    "statsig": (S, "legacy dir, no longer written (official docs)"),
    "logs": (S, "legacy dir, no longer written (official docs)"),
    # repo / editor metadata
    ".git": REPO, ".gitignore": REPO, ".husky": REPO, ".prettierrc": REPO, ".prettierignore": REPO,
    ".idea": REPO, ".vscode": REPO, ".serena": (K, "Serena MCP project memories"),
    ".claude": (K, "project-scope settings for sessions run inside ~/.claude itself"),
}

CODEX_KNOWN: dict[str, tuple[str, str]] = {
    "config.toml": (K, "user config"), "AGENTS.md": (K, "user instructions"),
    "AGENTS.override.md": (K, "user instructions"), "auth.json": (K, "credentials"),
    "hooks.json": (K, "user hooks"), "rules": (K, "user rules"), "prompts": (K, "user prompts"),
    "skills": (K, "user + .system skills"), "agents": (K, "user agent roles"),
    "keybindings.json": (K, "user keybindings"),
    "history.jsonl": (K, "prompt history"), "sessions": (K, "transcripts"),
    "archived_sessions": (K, "transcripts"), "session_index.jsonl": (K, "session index"),
    "models_cache.json": (K, "cache"), "version.json": (K, "update check"),
    "installation_id": (K, "id"), "internal_storage.json": (K, "state"),
    "memories": (K, "memories"), "memories_v2": (K, "memories"), "plans": (K, "Codex app plan files"),
    "shell_snapshots": (K, "runtime"), "cache": (K, "cache"), "plugins": (K, "plugins (deep-checked)"),
    "packages": (K, "app-server-daemon releases"), "vendor_imports": (K, "curated skills import"),
    ".tmp": (K, "runtime temp (deep-checked)"), "tmp": (K, "arg0 shims (deep-checked)"),
    "sqlite": (K, "Desktop codex-dev.db (deep-checked)"),
    ".codex-global-state.json": (K, "Desktop state"),
    ".codex-global-state.json.bak": (K, "rewritten by the Desktop app on every save"),
    "worktrees": (K, "Codex app worktrees (deep-checked)"), "automations": (K, "app automations"),
    "attachments": (K, "app attachments"), "generated_images": (K, "user outputs"),
    "visualizations": (K, "user outputs"), "browser": (K, "browser plugin"),
    "computer-use": (K, "computer-use plugin (notify target)"), "ambient-suggestions": (K, "app"),
    "app-server-control": (K, "app"), "app-server-daemon": (K, "app"), "ipc": (K, "app"),
    "thread-writer-locks": (K, "locks"), "project-metadata-locks": (K, "locks"),
    "mcp-oauth-locks": (K, "locks"), "tui-thread-reference-capabilities": (K, "TUI markers"),
    "rollout-migrations": (K, "app"), "node_repl": (K, "app"), "process_manager": (K, "app"),
    "skysight": (K, "app"), "code-review-plugin": (K, "code-review plugin db"), "pets": (K, "app"),
    "dictation-history": (K, "app"), "transcription-history.jsonl": (K, "app"),
    "realtime-voice-continuity.json": (K, "app"), "external_agent_session_imports.json": (K, "app"),
    "chrome-native-hosts-v2.json": (K, "Chrome native host registry"),
    "state": (K, "plugin state"), ".personality_migration": (K, "migration marker"),
    ".sandbox_migration": (K, "migration marker"), ".app-server-state-reconciled-v1": (K, "marker"),
    ".sqlite-maintenance.lock": (K, "lock"), "log": (S, "legacy plaintext logs (codex-tui.log is opt-in via log_dir)"),
    ".git": REPO, ".gitignore": REPO, ".idea": REPO, ".vscode": REPO, ".cursor": REPO,
    ".serena": (K, "Serena MCP project memories"),
}
CODEX_DB_RE = re.compile(r"^(state|logs|goals|memories|memories_v2|queue|thread_history)_(\d+)\.sqlite(-shm|-wal)?$")
CODEX_APP_MANAGED_MKTS = {"openai-bundled", "openai-curated-remote", "openai-primary-runtime", "created-by-me-remote"}

CURSOR_KNOWN: dict[str, tuple[str, str]] = {
    "AGENTS.md": (K, "user instructions"), "argv.json": (K, "runtime args"),
    "cli-config.json": (K, "cursor-agent config"), "mcp.json": (K, "user MCP"), "hooks.json": (K, "user hooks"),
    "ide_state.json": (K, "app"), "agent-cli-state.json": (K, "app"), "acp-config.json": (K, "app"),
    "acp-sessions": (K, "ACP sessions"), "ai-tracking": (K, "app"), "browser-logs": (K, "browser tool logs"),
    "chats": (K, "transcripts"), "projects": (K, "agent transcripts / terminals"),
    "commands": (K, "user commands"), "rules": (K, "user rules"), "skills": (K, "user skills"),
    "skills-cursor": (K, "built-in skills"), "agents": (K, "user subagents"), "subagents": (K, "app"),
    "plans": (K, "user plans"), "plugins": (K, "plugins (deep-checked)"), "extensions": (K, "extensions (deep-checked)"),
    "computer-use-sidecar": (K, "app"), "statsig-cache.json": (K, "cache"), "prompt_history.json": (K, "history"),
    "sandbox-policies": (K, "app"), "worktrees": (K, "worktrees (deep-checked)"),
    "worktrees.json": (K, "worktree setup config"), "scripts": (K, "user scripts"), "workers": (K, "app (empty)"),
    ".git": REPO, ".gitignore": (K, "contains CURSOR MANAGED BLOCK"), ".cursor": REPO,
}

TOOLS = {
    "claude": (HOME / ".claude", CLAUDE_KNOWN),
    "codex": (HOME / ".codex", CODEX_KNOWN),
    "cursor": (HOME / ".cursor", CURSOR_KNOWN),
}

BACKUP_GLOBS = ["*.bak", "*.bak.*", "*.bak-*", "*.backup", "*.backup.*", "*.backup-*", "*-bak-*", "*.cm-setup-bak-*",
                "*-backup-*", "*.cua-backup-*", "*.orig", "*.old", "*.tmp-*", "..*.tmp-*"]
# A date-stamped copy of a sibling, e.g. settings.json.20261127-080453 or config.toml-2026-11-27
DATED_COPY_RE = re.compile(r"^(.+?)[._-](?:19|20)\d{2}-?\d{2}-?\d{2}")
SECRET_RE = re.compile(r"(^\.env|secret|token|credential|password|\.key$|-key$|\.pem$)", re.I)

# The user keeps Claude Code transcripts for 14 days (rule added 2026-11-28). Claude's own sweep waits
# cleanupPeriodDays (default 30), so cleanup runs tighten it; stage.sh re-checks the same threshold.
TRANSCRIPT_MAX_AGE_DAYS = 14
# Session artifacts in projects/<project>/: <id>.jsonl, <id>/ (subagents, tool-results, mcp-tasks)
# and the set-aside copies <id>.orphaned-<ts>-<suffix>.jsonl / <id>.jsonl.superseded-<ts>
SESSION_ARTIFACT_RE = re.compile(r"^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"
                                 r"(?:\.jsonl|\.orphaned-[^/]+\.jsonl|\.jsonl\.superseded-[^/]+)?$")


@dataclass
class Finding:
    tool: str
    path: str
    cls: str
    reason: str
    size: int = 0
    age_days: float = 0.0
    tracked: bool = False
    details: dict = field(default_factory=dict)


# --------------------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------------------
def run(cmd: list[str], cwd: Path | None = None) -> tuple[int, str]:
    """Run a command quietly; return (exit code, stdout)."""
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=120)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


def size_of(p: Path) -> int:
    """Disk usage in bytes via `du -sk` (fast, follows no symlinks)."""
    if p.is_symlink():
        return 0
    code, out = run(["du", "-sk", str(p)])
    return int(out.split()[0]) * 1024 if code == 0 and out else 0


def age_days(p: Path) -> float:
    try:
        return (NOW - p.lstat().st_mtime) / 86400
    except OSError:
        return 0.0


def is_open(p: Path) -> bool:
    """True when any process holds the file (or something under the dir) open."""
    args = ["lsof", "-t", "+D", str(p)] if p.is_dir() else ["lsof", "-t", "--", str(p)]
    code, out = run(args)
    return bool(out.strip())


def tracked_set(home: Path) -> set[str]:
    """Paths tracked by git when the tool home is itself a git repo (dotfiles)."""
    if not (home / ".git").exists():
        return set()
    code, out = run(["git", "-C", str(home), "ls-files", "-z"])
    return set(filter(None, out.split("\0"))) if code == 0 else set()


def is_tracked(tracked: set[str], rel: str) -> bool:
    return rel in tracked or any(t.startswith(rel.rstrip("/") + "/") for t in tracked)


def config_text() -> str:
    """Concatenated text of every config that may reference files in the homes."""
    files = [HOME / ".claude/settings.json", HOME / ".claude.json", HOME / ".codex/config.toml",
             HOME / ".cursor/mcp.json", HOME / ".cursor/hooks.json", HOME / ".codex/hooks.json",
             HOME / ".config/fish/config.fish", HOME / ".zshrc", HOME / ".bashrc"]
    la = HOME / "Library/LaunchAgents"
    if la.is_dir():
        files += list(la.glob("*.plist"))
    chunks = []
    for f in files:
        try:
            chunks.append(f.read_text(errors="ignore"))
        except OSError:
            pass
    code, out = run(["crontab", "-l"])
    return "\n".join(chunks) + out


# --------------------------------------------------------------------------------------
# generic classification
# --------------------------------------------------------------------------------------
def is_referenced(entry: Path, refs: str) -> bool:
    """True when a config/shell/launchd file mentions this path (absolute, $HOME/ or ~/ form)."""
    rel = str(entry).replace(str(HOME), "", 1)
    return any(form in refs for form in (str(entry), f"$HOME{rel}", f"~{rel}"))


def is_dated_copy(entry: Path, known: dict) -> bool:
    """
    Tell whether a top-level entry is a date-stamped copy of another entry (a backup by its name).

    Exists because some tools back up as `<file>.<date>` instead of `<file>.bak`, and the user treats
    both as deletable backups. Called by classify_top() only after the known-name check, so official
    entries never reach it. The base name must exist beside it (or be a known entry), which keeps
    dated logs, session folders and repair dirs like `openclaw-repair-<date>/` out.

    @param entry - Top-level path in a tool home.
    @param known - The tool's *_KNOWN table.
    @returns True when the name is `<sibling>[._-]<YYYYMMDD | YYYY-MM-DD>...`.

    @example
        is_dated_copy(Path.home() / ".claude/settings.json.20261127-080453", CLAUDE_KNOWN)  # True
    """
    m = DATED_COPY_RE.match(entry.name)
    return bool(m) and (m[1] in known or (entry.parent / m[1]).exists())


def classify_top(tool: str, home: Path, known: dict, tracked: set[str], refs: str) -> list[Finding]:
    found: list[Finding] = []
    for entry in sorted(home.iterdir(), key=lambda p: p.name):
        name, rel = entry.name, entry.name
        f = Finding(tool, str(entry), "UNKNOWN", "not in knowledge base - research it",
                    tracked=is_tracked(tracked, rel), age_days=round(age_days(entry), 1))
        if name in known:
            f.cls, f.reason = known[name]
        elif tool == "codex" and CODEX_DB_RE.match(name):
            # current runtime DB; deep_codex() re-flags superseded numbers as SAFE
            f.cls, f.reason = K, "Codex runtime DB"
        elif is_referenced(entry, refs):
            f.cls, f.reason = K, "referenced by a config (statusline / hook / MCP / launchd)"
        elif name == ".DS_Store":
            f.cls, f.reason = S, "macOS Finder junk"
        elif entry.is_file() and entry.stat().st_size == 0 and name.startswith("-"):
            f.cls, f.reason = S, "zero-byte file from a mistyped command"
        elif entry.is_symlink() and not entry.exists():
            f.cls, f.reason = S, "dangling symlink"
        elif any(fnmatch.fnmatch(name, g) for g in BACKUP_GLOBS) or is_dated_copy(entry, known):
            # user rule (2026-11-28): agent config is kept in git, so backups are SAFE at any age
            f.cls, f.reason = S, "backup copy (config history is in git)"
        elif SECRET_RE.search(name):
            f.cls, f.reason = "HOLD", "may contain secrets - confirm unused before deleting"
        elif f.tracked:
            f.reason = "tracked in the dotfiles repo - likely user-authored, confirm it is still used"
        if f.cls != K:
            f.size = size_of(entry)
        found.append(f)
    return found


def dangling_skill_links(tool: str, home: Path) -> list[Finding]:
    out = []
    skills = home / "skills"
    if skills.is_dir():
        for e in skills.iterdir():
            if e.is_symlink() and not e.exists():
                out.append(Finding(tool, str(e), S, f"dangling skill symlink -> {os.readlink(e)}"))
            elif e.name == ".DS_Store":
                out.append(Finding(tool, str(e), S, "macOS Finder junk"))
    return out


def worktree_findings(tool: str, root: Path, depth: int) -> list[Finding]:
    """Describe each worktree under root (depth 1 = root/<wt>, depth 2 = root/<group>/<wt>)."""
    out: list[Finding] = []
    if not root.is_dir():
        return out
    groups = [root] if depth == 1 else [g for g in root.iterdir() if g.is_dir()]
    for g in groups:
        children = [c for c in g.iterdir() if c.is_dir()]
        has_wt = False
        for c in children:
            child_has_wt = False
            # Codex nests the checkout one level deeper: <id>/<repo>/.git
            for cand in [c] + ([x for x in c.iterdir() if x.is_dir()] if depth == 1 else []):
                gitfile = cand / ".git"
                if not gitfile.is_file():
                    continue
                has_wt = child_has_wt = True
                gd = gitfile.read_text().strip().removeprefix("gitdir: ")
                parent = gd.split("/.git/worktrees/")[0]
                d = {"parent": parent, "registered": Path(gd).is_dir()}
                if d["registered"]:
                    _, dirty = run(["git", "-C", str(cand), "status", "--porcelain"])
                    _, sha = run(["git", "-C", str(cand), "rev-parse", "HEAD"])
                    _, br = run(["git", "-C", parent, "branch", "-a", "--contains", sha.strip()])
                    d.update(dirty=len(dirty.splitlines()), head=sha.strip()[:12],
                             head_in_branch=bool(br.strip()))
                    reason = (f"git worktree of {parent}: {d['dirty']} uncommitted change(s), "
                              f"HEAD {'in a branch' if d['head_in_branch'] else 'NOT in any branch'}")
                else:
                    reason = f"orphan checkout: parent repo no longer registers it ({parent})"
                out.append(Finding(tool, str(cand), "HOLD", reason, size_of(cand),
                                   round(age_days(cand), 1), details=d))
            if depth == 1 and not child_has_wt:
                # Codex keeps <id>/.codex-worktree-name after the checkout is gone
                names = [e.name for e in c.iterdir()]
                reason = ("marker-only Codex worktree dir (checkout already removed)"
                          if names == [".codex-worktree-name"] or not names
                          else "Codex worktree dir without a git checkout (stray files)")
                out.append(Finding(tool, str(c), "HOLD", reason, size_of(c), round(age_days(c), 1)))
        if depth == 2 and not has_wt and not any(g.iterdir()):
            out.append(Finding(tool, str(g), S, "empty worktree group dir"))
    return out


# --------------------------------------------------------------------------------------
# tool-specific deep checks
# --------------------------------------------------------------------------------------
def deep_claude(home: Path, tracked: set[str], refs: str) -> list[Finding]:
    out: list[Finding] = []
    plugins = home / "plugins"
    installed: set[str] = set()
    try:
        installed = set(json.loads((plugins / "installed_plugins.json").read_text()).get("plugins", {}))
    except (OSError, ValueError):
        pass
    recent_orphans: set[Path] = set()
    for tmp in plugins.glob("cache/temp_git_*"):
        # leftover clone of a marketplace add that did not finish: never a plugin, stage it whole
        out.append(Finding("claude", str(tmp), S, "temp clone left by an unfinished marketplace add",
                           size_of(tmp), round(age_days(tmp), 1)))
    for ver in plugins.glob("cache/*/*/*"):
        if ver.parent.parent.name.startswith("temp_git_"):
            continue
        marker = ver / ".orphaned_at"
        if marker.is_file():
            try:
                hrs = (NOW * 1000 - int(marker.read_text().strip())) / 3_600_000
            except ValueError:
                hrs = age_days(marker) * 24
            cls = S if hrs > 48 else "HOLD"
            if cls == "HOLD":
                recent_orphans.add(ver.parent)
            out.append(Finding("claude", str(ver), cls,
                               f"orphaned plugin version ({hrs:.0f}h ago; CC auto-removes after 14 days)",
                               size_of(ver), round(hrs / 24, 1)))
    for plug in plugins.glob("cache/*/*"):
        if plug.parent.name.startswith("temp_git_"):
            continue
        pid = f"{plug.name}@{plug.parent.name}"
        if plug.is_dir() and pid not in installed:
            # staging the plugin dir would also take a version a running session may still have loaded
            held = plug in recent_orphans
            out.append(Finding("claude", str(plug), "HOLD" if held else S,
                               f"plugin cache for {pid}, not in installed_plugins.json"
                               + (" (holds a version orphaned < 48h ago)" if held else ""),
                               size_of(plug)))
    for data in plugins.glob("data/*"):
        if not any(re.sub(r"[^A-Za-z0-9_-]", "-", p) == data.name for p in installed):
            empty = data.is_dir() and not any(data.iterdir())
            out.append(Finding("claude", str(data), S if empty else "HOLD",
                               "plugin data dir for a plugin that is not installed" + (" (empty)" if empty else ""),
                               size_of(data)))
    hooks = home / "hooks"
    if hooks.is_dir():
        for h in hooks.iterdir():
            if h.name == "logs" or str(h) in refs or f"$HOME/.claude/hooks/{h.name}" in refs:
                continue
            empty = h.is_dir() and not any(h.iterdir())
            out.append(Finding("claude", str(h), S if empty else "HOLD",
                               "hook asset not referenced by settings.json" + (" (empty dir)" if empty else ""),
                               size_of(h), round(age_days(h), 1), is_tracked(tracked, f"hooks/{h.name}")))
    out += stale_transcripts(home)
    return out


def newest_mtime(p: Path) -> float:
    """
    Latest modification time of a file, or of anything inside a directory.

    Exists because resuming a session can touch only its subdirectory (subagents, tool-results),
    so the top-level mtime alone would make an active session look idle. Called by stale_transcripts().

    @param p - File or directory; symlinks are not followed.
    @returns Epoch seconds, or 0.0 when the path vanished meanwhile.
    """
    try:
        latest = p.lstat().st_mtime
    except OSError:
        return 0.0
    if p.is_dir() and not p.is_symlink():
        for dirpath, _, files in os.walk(p):
            for name in files:
                try:
                    latest = max(latest, os.lstat(os.path.join(dirpath, name)).st_mtime)
                except OSError:
                    pass
    return latest


def stale_transcripts(home: Path) -> list[Finding]:
    """
    Flag Claude Code session transcripts idle for TRANSCRIPT_MAX_AGE_DAYS or longer as SAFE.

    Exists because the user keeps transcripts only 14 days, while Claude's own sweep waits
    cleanupPeriodDays (default 30). Deleting them is what that sweep does anyway, so
    `claude --resume` just stops listing them. Called from deep_claude() on every scan.
    A session is the group of SESSION_ARTIFACT_RE entries sharing one id; its age is the newest
    mtime in the group, so a resumed session survives. Auto memory (`memory/`), backups and any
    other file never match, and a session listed in `sessions/*.json` (running) is skipped.

    @param home - The Claude home (~/.claude).
    @returns One SAFE finding per artifact path of each idle session.

    @example
        findings += stale_transcripts(Path.home() / ".claude")
    """
    running: set[str] = set()
    for marker in (home / "sessions").glob("*.json"):
        try:
            running.add(json.loads(marker.read_text()).get("sessionId", ""))
        except (OSError, ValueError):
            pass
    projects = home / "projects"
    if not projects.is_dir():
        return []
    out: list[Finding] = []
    for proj in sorted(p for p in projects.iterdir() if p.is_dir() and not p.is_symlink()):
        groups: dict[str, list[Path]] = {}
        for entry in proj.iterdir():
            m = SESSION_ARTIFACT_RE.match(entry.name)
            # only session artifacts; memory/, *.tgz backups and stray files never match
            if m:
                groups.setdefault(m[1], []).append(entry)
        for sid, paths in groups.items():
            if sid in running:
                continue
            idle = (NOW - max(newest_mtime(p) for p in paths)) / 86400
            if idle < TRANSCRIPT_MAX_AGE_DAYS:
                continue
            for p in paths:
                out.append(Finding("claude", str(p), S,
                                   f"session transcript idle {idle:.0f}d (rule: >= {TRANSCRIPT_MAX_AGE_DAYS}d)",
                                   size_of(p), round(idle, 1)))
    return out


def deep_codex(home: Path, refs: str) -> list[Finding]:
    out: list[Finding] = []
    # numbered runtime DBs: lower numbers are superseded by migrations
    latest: dict[str, int] = {}
    for f in home.iterdir():
        m = CODEX_DB_RE.match(f.name)
        if m:
            latest[m[1]] = max(latest.get(m[1], 0), int(m[2]))
    for f in home.iterdir():
        m = CODEX_DB_RE.match(f.name)
        if m and int(m[2]) < latest[m[1]] and not is_open(f):
            out.append(Finding("codex", str(f), S, f"superseded DB (current: {m[1]}_{latest[m[1]]})", size_of(f)))
    sq = home / "sqlite"
    if sq.is_dir():
        for f in sq.iterdir():
            m = CODEX_DB_RE.match(f.name)
            if m and latest.get(m[1], -1) >= int(m[2]) and not is_open(f):
                out.append(Finding("codex", str(f), S,
                                   "stale duplicate of a core DB under sqlite/ (Desktop only uses codex-dev.db here)",
                                   size_of(f), round(age_days(f), 1)))
    if (home / "tmp/path").exists() and (home / "tmp/arg0").exists():
        out.append(Finding("codex", str(home / "tmp/path"), S, "legacy arg0 shim dir (replaced by tmp/arg0)"))
    for g in home.glob(".tmp/git-*"):
        if age_days(g) > 1:
            out.append(Finding("codex", str(g), S, "leftover temporary git clone", size_of(g), round(age_days(g), 1)))
    if (home / "chrome-native-hosts.json").exists() and (home / "chrome-native-hosts-v2.json").exists():
        out.append(Finding("codex", str(home / "chrome-native-hosts.json"), S, "v1 registry superseded by v2"))
    mcp = home / "mcp"
    if mcp.is_dir():
        for e in mcp.iterdir():
            if str(e) not in refs and f"~/.codex/mcp/{e.name}" not in refs:
                out.append(Finding("codex", str(e), S, "MCP server files not referenced by any config",
                                   size_of(e), round(age_days(e), 1)))
    # plugin caches without a config entry (app-managed marketplaces excluded)
    cfg = (home / "config.toml").read_text(errors="ignore") if (home / "config.toml").exists() else ""
    for plug in home.glob("plugins/cache/*/*"):
        mkt = plug.parent.name
        if mkt in CODEX_APP_MANAGED_MKTS:
            continue
        if f'[plugins."{plug.name}@{mkt}"]' not in cfg:
            out.append(Finding("codex", str(plug), "HOLD", f"plugin cache with no [plugins.\"{plug.name}@{mkt}\"] entry",
                               size_of(plug)))
    stale = [p for p in re.findall(r'^\[projects\."([^"]+)"\]', cfg, re.M)
             if p.startswith(("/private/var/folders/", "/var/folders/", "/tmp/", "/private/tmp/"))
             and not os.path.exists(p)]
    if stale:
        # Pseudo path ("#...") so it never overrides config.toml's KEEP verdict or reaches stage.sh
        out.append(Finding("codex", str(home / "config.toml") + "#stale-projects", "HOLD",
                           f"{len(stale)} [projects] trust entries for temp dirs that no longer exist "
                           f"(prune_codex_projects.py)"))
    out += worktree_findings("codex", home / "worktrees", depth=1)
    return out


def deep_cursor(home: Path) -> list[Finding]:
    out: list[Finding] = []
    ext = home / "extensions"
    try:
        obsolete = json.loads((ext / ".obsolete").read_text())
    except (OSError, ValueError):
        obsolete = {}
    try:
        registered = {e.get("relativeLocation") for e in json.loads((ext / "extensions.json").read_text())}
    except (OSError, ValueError):
        registered = set()
    for d in ext.iterdir() if ext.is_dir() else []:
        if not d.is_dir() or d.name.startswith("."):
            continue
        if d.name in obsolete:
            out.append(Finding("cursor", str(d), S, "extension marked obsolete (uninstalled/updated)", size_of(d)))
        elif registered and d.name not in registered:
            out.append(Finding("cursor", str(d), "HOLD", "extension dir not registered in extensions.json", size_of(d)))
    plugins = home / "plugins"
    for legacy in ("installed.json", "marketplaces.json", "marketplaces"):
        p = plugins / legacy
        if p.exists():
            out.append(Finding("cursor", str(p), S, "legacy plugin format (cursor-agent reads local-marketplaces.json)",
                               size_of(p)))
    for c in plugins.glob("cache/*"):
        if c.name != "cursor-public":
            out.append(Finding("cursor", str(c), S, "legacy plugin cache (current: cache/cursor-public)", size_of(c)))
    out += worktree_findings("cursor", home / "worktrees", depth=2)
    return out


# --------------------------------------------------------------------------------------
# output
# --------------------------------------------------------------------------------------
def human(n: int) -> str:
    for unit in ("B", "K", "M", "G"):
        if n < 1024:
            return f"{n:.0f}{unit}"
        n /= 1024
    return f"{n:.1f}T"


def to_markdown(findings: list[Finding], show_keep: bool) -> str:
    lines = []
    for cls in ("SAFE", "HOLD", "UNKNOWN") + (("KEEP",) if show_keep else ()):
        rows = [f for f in findings if f.cls == cls]
        total = sum(f.size for f in rows)
        lines.append(f"\n## {cls} ({len(rows)} items, {human(total)})\n")
        if not rows:
            continue
        lines.append("| tool | path | size | age(d) | git | reason |")
        lines.append("|---|---|---|---|---|---|")
        for f in sorted(rows, key=lambda x: (x.tool, x.path)):
            p = f.path.replace(str(HOME), "~")
            lines.append(f"| {f.tool} | `{p}` | {human(f.size)} | {f.age_days} | "
                         f"{'tracked' if f.tracked else ''} | {f.reason} |")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", action="store_true", help="emit JSON")
    ap.add_argument("--all", action="store_true", help="include KEEP rows in markdown")
    ap.add_argument("--list", choices=["SAFE", "HOLD", "UNKNOWN"], help="print absolute paths of one class")
    ap.add_argument("--tool", choices=list(TOOLS), action="append", help="limit to a tool (repeatable)")
    args = ap.parse_args()

    refs = config_text()
    findings: list[Finding] = []
    for tool, (home, known) in TOOLS.items():
        if args.tool and tool not in args.tool or not home.is_dir():
            continue
        tracked = tracked_set(home)
        findings += classify_top(tool, home, known, tracked, refs)
        findings += dangling_skill_links(tool, home)
        if tool == "claude":
            findings += deep_claude(home, tracked, refs)
        elif tool == "codex":
            findings += deep_codex(home, refs)
        else:
            findings += deep_cursor(home)

    # Deep checks are more specific than the top-level verdict: drop duplicate paths keeping the last
    dedup: dict[str, Finding] = {}
    for f in findings:
        dedup[f.path] = f
    findings = list(dedup.values())
    for f in findings:
        # deep checks don't always set an age; fill it from mtime for the report
        if not f.age_days and "#" not in f.path:
            f.age_days = round(age_days(Path(f.path)), 1)

    if args.list:
        # Only real filesystem paths; pseudo findings ("file#note") are report-only
        print("\n".join(f.path for f in findings if f.cls == args.list and "#" not in f.path))
    elif args.json:
        print(json.dumps([asdict(f) for f in findings], indent=2, ensure_ascii=False))
    else:
        print(f"# agent-home scan ({time.strftime('%Y-%m-%d %H:%M')})")
        print(to_markdown(findings, args.all))
    return 0


if __name__ == "__main__":
    sys.exit(main())
