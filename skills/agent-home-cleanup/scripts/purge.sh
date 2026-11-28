#!/usr/bin/env bash
# Permanently delete staging folders created by stage.sh (only after the user approves).
#
# Pass explicit paths: macOS privacy controls (TCC) can make globbing ~/.Trash return
# nothing from a terminal, so `purge.sh ~/.Trash/agent-home-cleanup-*` may silently skip.
#
# Usage: bash purge.sh <staging-dir> [<staging-dir> ...]
set -uo pipefail

[[ $# -gt 0 ]] || { echo "usage: purge.sh <staging-dir>..." >&2; exit 1; }

for s in "$@"; do
  s="${s%/}"
  base="$(basename "$s")"
  # Guard: only our own staging folders directly under ~/.Trash
  if [[ "$(dirname "$s")" != "$HOME/.Trash" || ! "$base" =~ ^(agent-home-cleanup|ai-config-cleanup)- ]]; then
    echo "REFUSED (not a staging folder in ~/.Trash): $s" >&2; continue
  fi
  if [[ ! -d "$s" ]]; then
    echo "SKIP (missing): $s"; continue
  fi
  size=$(du -sh "$s" 2>/dev/null | cut -f1)
  rm -rf -- "$s" && echo "PURGED [$size] $s"
  [[ -e "$s" ]] && echo "STILL EXISTS (check Full Disk Access for the terminal): $s" >&2
done
