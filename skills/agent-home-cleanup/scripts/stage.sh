#!/usr/bin/env bash
# Move cleanup targets into ~/.Trash/agent-home-cleanup-<stamp>/ with a restore manifest.
#
# Why: deletions stay reversible until the user approves a purge (restore.sh undoes this).
# When: the "Stage" step of the agent-home-cleanup skill, after scan.py + manual verification.
# Input: absolute paths, one per line, from a file or stdin (e.g. `scan.py --list SAFE`).
#
# Usage: bash stage.sh [--dry-run] <paths-file | ->
set -uo pipefail

DRY=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY=1; shift; fi
SRC="${1:--}"

STAMP="agent-home-cleanup-$(date +%Y%m%d-%H%M%S)"
DEST="$HOME/.Trash/$STAMP"
MANIFEST="$DEST/MANIFEST.tsv"

# Never stage these (relative to the tool home): transcripts, credentials, user config, memory.
# Only exception: Claude Code transcripts idle >= TRANSCRIPT_MIN_AGE_DAYS (see below).
PROTECTED_EXACT=" projects sessions archived_sessions chats history.jsonl .credentials.json auth.json \
settings.json settings.local.json config.toml mcp.json hooks.json CLAUDE.md AGENTS.md skills agents \
commands rules jobs daemon .git plugins plugins/installed_plugins.json memories memories_v2 \
sqlite/codex-dev.db sqlite/codex-dev.db-shm sqlite/codex-dev.db-wal "
PROTECTED_PREFIX=("projects/" "sessions/" "archived_sessions/" "chats/" ".git/" "memories/" "memories_v2/")

# The one exception under projects/: Claude Code session artifacts idle >= this many days (user rule,
# mirrors scan.py TRANSCRIPT_MAX_AGE_DAYS). Re-checked here so a hand-written list cannot stage a live one.
TRANSCRIPT_MIN_AGE_DAYS=14
UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
TRANSCRIPT_RE="^projects/[^/]+/(${UUID_RE})(\\.jsonl|\\.orphaned-[^/]+\\.jsonl|\\.jsonl\\.superseded-[^/]+)?$"

moved=0 refused=0
if [[ $DRY -eq 0 ]]; then
  mkdir -p "$DEST"
  printf 'original_path\ttrash_path\tsize\n' > "$MANIFEST"
fi

refuse() { echo "REFUSED ($2): $1" >&2; refused=$((refused + 1)); }

while IFS= read -r p || [[ -n "$p" ]]; do
  [[ -z "$p" || "$p" == \#* ]] && continue
  p="${p/#\~/$HOME}"
  [[ "$p" == *"#"* ]] && { refuse "$p" "report-only pseudo path"; continue; }

  # Must live inside one of the three tool homes (not be the home itself)
  rel="" root=""
  for r in "$HOME/.claude" "$HOME/.codex" "$HOME/.cursor"; do
    if [[ "$p" == "$r/"* ]]; then root="$r"; rel="${p#"$r"/}"; fi
  done
  [[ -z "$root" || -z "$rel" ]] && { refuse "$p" "outside ~/.claude ~/.codex ~/.cursor"; continue; }
  [[ -e "$p" || -L "$p" ]] || { refuse "$p" "missing"; continue; }

  transcript=0
  if [[ "$root" == "$HOME/.claude" && "$rel" =~ $TRANSCRIPT_RE ]]; then
    sid="${BASH_REMATCH[1]}"
    # Age = newest mtime across the whole session group (<id>.jsonl, <id>/, set-aside copies)
    # Fail closed: if find errors, the empty output must not read as "old"
    if ! recent=$(find "$(dirname "$p")/$sid"* -mmin -$((TRANSCRIPT_MIN_AGE_DAYS * 1440)) -print -quit 2>/dev/null); then
      refuse "$p" "could not check transcript age"; continue
    fi
    [[ -n "$recent" ]] && { refuse "$p" "transcript active within ${TRANSCRIPT_MIN_AGE_DAYS} days"; continue; }
    if grep -qs -- "$sid" "$HOME/.claude/sessions/"*.json; then refuse "$p" "transcript of a running session"; continue; fi
    transcript=1
  fi

  # Everything else under the protected names stays (memory/, other files in projects/, credentials, config)
  if [[ $transcript -eq 0 ]]; then
    if [[ "$PROTECTED_EXACT" == *" $rel "* ]]; then refuse "$p" "protected"; continue; fi
    skip=0
    for pre in "${PROTECTED_PREFIX[@]}"; do [[ "$rel" == "$pre"* ]] && skip=1; done
    [[ $skip -eq 1 ]] && { refuse "$p" "protected subtree"; continue; }
  fi

  # Do not move files a running process still holds open (DBs, logs)
  if [[ -f "$p" ]] && lsof -t -- "$p" >/dev/null 2>&1; then refuse "$p" "open by a running process"; continue; fi

  size=$(du -sh "$p" 2>/dev/null | cut -f1)
  dst="$DEST/${p#"$HOME"/}"
  if [[ $DRY -eq 1 ]]; then
    echo "WOULD MOVE [$size] $p"
  else
    mkdir -p "$(dirname "$dst")"
    if mv -- "$p" "$dst"; then
      printf '%s\t%s\t%s\n' "$p" "$dst" "$size" >> "$MANIFEST"
      echo "MOVED [$size] $p"
    else
      refuse "$p" "mv failed"; continue
    fi
  fi
  moved=$((moved + 1))
done < <(if [[ "$SRC" == "-" ]]; then cat; else cat -- "$SRC"; fi)

echo
echo "moved=$moved refused=$refused dry_run=$DRY"
if [[ $DRY -eq 0 ]]; then
  echo "staging=$DEST"
  echo "manifest=$MANIFEST"
  du -sh "$DEST" 2>/dev/null
fi
