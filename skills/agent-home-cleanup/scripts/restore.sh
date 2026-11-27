#!/usr/bin/env bash
# Undo stage.sh: move everything listed in <staging>/MANIFEST.tsv back to its original path.
#
# Why: a tool broke after staging, or the user changed their mind before the purge.
# Usage: bash restore.sh <staging-dir> [original-path-substring]
#   The optional filter restores only matching entries (e.g. "settings.json").
set -uo pipefail

STAGING="${1:?usage: restore.sh <staging-dir> [filter]}"
FILTER="${2:-}"
MANIFEST="$STAGING/MANIFEST.tsv"
[[ -f "$MANIFEST" ]] || { echo "no manifest: $MANIFEST" >&2; exit 1; }

restored=0 skipped=0
while IFS=$'\t' read -r orig trash _size; do
  [[ "$orig" == "original_path" ]] && continue
  [[ -n "$FILTER" && "$orig" != *"$FILTER"* ]] && continue
  if [[ -e "$orig" || -L "$orig" ]]; then
    echo "SKIP (destination exists): $orig"; skipped=$((skipped + 1)); continue
  fi
  if [[ ! -e "$trash" && ! -L "$trash" ]]; then
    echo "SKIP (not in staging): $trash"; skipped=$((skipped + 1)); continue
  fi
  mkdir -p "$(dirname "$orig")"
  mv -- "$trash" "$orig" && { echo "RESTORED $orig"; restored=$((restored + 1)); }
done < "$MANIFEST"

echo "restored=$restored skipped=$skipped"
