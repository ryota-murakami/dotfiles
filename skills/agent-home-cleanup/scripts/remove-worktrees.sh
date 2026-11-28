#!/usr/bin/env bash
# Remove Codex / Cursor agent worktrees the right way (git worktree remove + prune).
#
# Why: deleting a worktree dir with rm leaves stale metadata in the parent repo, and can
#      silently lose uncommitted edits or commits that exist only on a detached HEAD.
# When: the user approved deleting HOLD worktrees reported by scan.py.
# Default is a dry run that prints what would be lost; pass --yes to delete.
#
# Usage: bash remove-worktrees.sh [--yes] <path-under-~/.codex/worktrees-or-~/.cursor/worktrees>...
set -uo pipefail

YES=0
if [[ "${1:-}" == "--yes" ]]; then YES=1; shift; fi
[[ $# -gt 0 ]] || { echo "usage: remove-worktrees.sh [--yes] <path>..." >&2; exit 1; }

parents=()
for target in "$@"; do
  target="${target%/}"
  target="${target/#\~/$HOME}"
  if [[ "$target" != "$HOME/.codex/worktrees/"* && "$target" != "$HOME/.cursor/worktrees/"* ]]; then
    echo "REFUSED (not under a worktrees root): $target" >&2; continue
  fi
  [[ -e "$target" ]] || { echo "SKIP (missing): $target"; continue; }

  # A target may be the checkout itself or a Codex <id>/ wrapper containing it
  while IFS= read -r gitfile; do
    wt="$(dirname "$gitfile")"
    gd="$(sed -n 's/^gitdir: //p' "$gitfile")"
    parent="${gd%%/.git/worktrees/*}"
    if [[ -d "$gd" ]]; then
      parents+=("$parent")
      dirty=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
      sha=$(git -C "$wt" rev-parse HEAD 2>/dev/null)
      inbr=$(git -C "$parent" branch -a --contains "$sha" 2>/dev/null | head -1)
      echo "WORKTREE $wt"
      echo "  parent=$parent dirty=$dirty head=${sha:0:12} head_in_branch=$([[ -n "$inbr" ]] && echo yes || echo NO)"
      [[ "$dirty" != "0" ]] && git -C "$wt" status --porcelain | sed 's/^/  will lose: /'
      if [[ $YES -eq 1 ]]; then
        git -C "$parent" worktree remove --force --force "$wt" && echo "  removed via git"
      fi
    else
      echo "ORPHAN $wt (parent no longer registers it: $parent)"
      [[ -d "$parent" ]] && parents+=("$parent")
    fi
  done < <(find "$target" -maxdepth 3 -name .git -type f 2>/dev/null)

  if [[ $YES -eq 1 && -e "$target" ]]; then
    rm -rf -- "$target" && echo "DELETED $target"
  elif [[ $YES -eq 0 ]]; then
    echo "WOULD DELETE $target ($(du -sh "$target" 2>/dev/null | cut -f1))"
  fi
done

if [[ $YES -eq 1 && ${#parents[@]} -gt 0 ]]; then
  printf '%s\n' "${parents[@]}" | sort -u | while IFS= read -r p; do
    git -C "$p" worktree prune && echo "PRUNED $p"
  done
fi
[[ $YES -eq 0 ]] && echo "(dry run - rerun with --yes to delete)"
exit 0
