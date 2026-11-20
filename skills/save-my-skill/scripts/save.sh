#!/bin/bash
# save.sh — copy a personal agent skill into ~/dotfiles/skills/<name> and report what to commit.
#
# Why it exists: skills are edited in their installed copy (~/.claude/skills/<name>, usually a symlink
# into ~/.agents/skills) or directly in dotfiles. Copying in the wrong direction silently loses edits,
# so the direction is decided from the committed version (HEAD), never guessed from timestamps.
# Called by the save-my-skill SKILL.md procedure.
#
# Usage:
#   save.sh status                 skills in ~/dotfiles/skills whose installed copy or dotfiles copy has changes
#   save.sh <name> [SOURCE_DIR]    save one skill; SOURCE_DIR defaults to its installed copy
#
# Result line (last line of output) and exit status:
#   SAVED         0  installed copy was copied over dotfiles
#   DOTFILES      0  only the dotfiles copy was edited: commit it, then refresh the install
#   LINKED        0  the install is a link to the dotfiles folder: commit it; nothing to copy or refresh
#   UNCHANGED     0  installed copy and dotfiles copy are the same (commit if git still shows changes)
#   CONFLICT      3  both copies were edited differently since HEAD: nothing was copied
#   CHECK FAILED  4  the skill's own scripts/check failed: fix the skill before committing
set -euo pipefail

DOT="${DOTFILES_DIR:-$HOME/dotfiles}"
SKILLS="$DOT/skills"
# Same exclusions as the skills CLI install, plus Finder litter
EXCLUDES=(--exclude metadata.json --exclude .git --exclude __pycache__ --exclude __pypackages__ --exclude .DS_Store)

die() { echo "save.sh: $*" >&2; exit 1; }

# Installed copy of a skill: the first agent home that has it, resolved through symlinks
installed_dir() {
  local c
  for c in "$HOME/.claude/skills/$1" "$HOME/.agents/skills/$1" "$HOME/.codex/skills/$1" "$HOME/.cursor/skills/$1"; do
    [ -f "$c/SKILL.md" ] && { (cd "$c" && pwd -P); return; }
  done
}

# Print the result line, after the skill's own static checks (scripts/check) when it ships them,
# so a skill with a known class of mechanical bugs cannot be committed with one
finish() {
  local result="$1" check="$SKILLS/$2/scripts/check"
  if [ -x "$check" ]; then
    echo "running $check"
    if ! "$check"; then
      echo "CHECK FAILED"
      return 4
    fi
  fi
  echo "$result"
}

# True when two skill folders have the same content (ignoring the excluded files)
same_tree() {
  diff -rq "${EXCLUDES[@]/--exclude/-x}" "$1" "$2" >/dev/null 2>&1
}

# Modification time (epoch seconds) of the newest file in a folder
newest() {
  find "$1" -type f ! -name .DS_Store -exec stat -f %m {} + 2>/dev/null | sort -n | tail -1 | grep . || echo 0
}

# Committed version of the skill in a temp folder (empty folder when the skill is not committed yet)
head_tree() {
  local tmp
  tmp=$(mktemp -d)
  git -C "$DOT" archive HEAD "skills/$1" 2>/dev/null | tar -x -C "$tmp" 2>/dev/null || true
  mkdir -p "$tmp/skills/$1"
  echo "$tmp/skills/$1"
}

cmd_status() {
  local d n src state
  for d in "$SKILLS"/*/; do
    n=$(basename "$d"); src=$(installed_dir "$n")
    state=""
    [ -n "$(git -C "$DOT" status --porcelain -- "skills/$n")" ] && state="dotfiles has uncommitted changes"
    if [ -z "$src" ]; then state="${state:+$state; }not installed"
    elif [ "$src" != "$(cd "$d" && pwd -P)" ] && ! same_tree "$src" "$d"; then state="${state:+$state; }installed copy differs"; fi
    [ -n "$state" ] && printf '%-28s %s\n' "$n" "$state"
  done
  return 0
}

cmd_save() {
  local name="$1" src="${2:-}" dest="$SKILLS/$1" head
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid skill name: $name"
  [ -d "$DOT/.git" ] || die "$DOT is not a git checkout"
  [ -n "$src" ] || src=$(installed_dir "$name")
  [ -n "$src" ] && [ -f "$src/SKILL.md" ] || die "no copy of '$name' with a SKILL.md: pass its folder as the second argument"
  src=$(cd "$src" && pwd -P)
  mkdir -p "$SKILLS"

  # Linked install (or editing dotfiles in place): nothing to copy, nothing to refresh
  if [ -d "$dest" ] && [ "$src" = "$(cd "$dest" && pwd -P)" ]; then
    git -C "$DOT" status --short -- "skills/$name"; finish LINKED "$name"; return
  fi

  if [ -d "$dest" ] && ! same_tree "$src" "$dest"; then
    head=$(head_tree "$name")
    if same_tree "$src" "$head"; then
      # Installed copy is still the committed one: the edit was made in dotfiles
      git -C "$DOT" status --short -- "skills/$name"; finish DOTFILES "$name"; return
    fi
    # A skill never committed has no HEAD to compare with: copy when the installed side is the newer one, otherwise ask
    if [ -z "$(ls -A "$head")" ] && [ "$(newest "$src")" -ge "$(newest "$dest")" ]; then
      :
    elif ! same_tree "$dest" "$head"; then
      # Both sides moved away from HEAD in different ways: a human has to pick
      echo "installed: $src"; echo "dotfiles:  $dest"
      diff -ru "${EXCLUDES[@]/--exclude/-x}" "$dest" "$src" | head -80 || true
      echo "CONFLICT"; return 3
    fi
  fi

  if [ -d "$dest" ] && same_tree "$src" "$dest"; then
    git -C "$DOT" status --short -- "skills/$name"; finish UNCHANGED "$name"; return
  fi

  rsync -a --checksum --delete "${EXCLUDES[@]}" "$src/" "$dest/"
  # Warn about anything that looks like a credential or a personal address before it is committed
  grep -rInE '(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_|AKIA[0-9A-Z]{16}|xox[bpa]-|-----BEGIN [A-Z ]*PRIVATE KEY|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})' "$dest" \
    | grep -v '@example\.' | sed 's/^/⚠ possible secret or address: /' | head -20 || true
  git -C "$DOT" status --short -- "skills/$name"
  finish SAVED "$name"
}

case "${1:-}" in
  status) cmd_status ;;
  ""|-h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 2 ;;
  *) cmd_save "$@" ;;
esac
