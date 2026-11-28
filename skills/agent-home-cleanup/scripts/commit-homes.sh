#!/usr/bin/env bash
# Commit each agent home's git repo, create a private GitHub remote when it has none, and push.
#
# Why: the user keeps agent config in git (that is also why backup copies are deletable at any age),
#      so a cleanup ends by recording the cleaned state and pushing it to a private remote.
# When: the last step of the agent-home-cleanup skill, after verification and purge. Nothing else calls it.
# Stages: tracked changes (`git add -u`, so cleanup deletions and config edits) plus untracked files under
#      user-config paths only (USER_CONFIG). Never `git add -A`: ~/.cursor's managed .gitignore un-ignores
#      projects/ (tens of thousands of agent files) and ~/.codex has untracked sessions and logs.
# Remote: a repo with no upstream gets `origin` = <owner>/<home without dot>-home (e.g. ~/.codex -> codex-home),
#      created --private. Owner: $AGENT_HOME_GH_OWNER, else the active gh account.
# Safety: untracked files with secret-looking names, build artifacts or > 5 MB are skipped; gitleaks scans the
#      staged diff before a commit and the whole history before a first push. Low-value API keys are accepted
#      and listed (user policy); high-impact credentials stop that repo (leak_check). Push only to a PRIVATE
#      GitHub remote; never force-push.
#
# Usage: bash commit-homes.sh [--dry-run] [--message <msg>] <home>...
#   e.g. bash commit-homes.sh --dry-run ~/.claude ~/.codex
set -uo pipefail
export GIT_TERMINAL_PROMPT=0   # fail instead of hanging on a credential prompt

DRY=0
MSG="chore(cleanup): agent-home-cleanup $(date +%F)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --message) MSG="$2"; shift 2 ;;
    *) break ;;
  esac
done
[[ $# -eq 0 ]] && { echo "usage: bash commit-homes.sh [--dry-run] [--message <msg>] <home>..." >&2; exit 2; }
command -v gitleaks >/dev/null || { echo "ABORT: gitleaks is required (brew install gitleaks)" >&2; exit 1; }

# User-authored config that belongs in the repo even when it is new (relative to the home)
USER_CONFIG=(skills agents commands rules hooks output-styles themes workflows prompts
  CLAUDE.md AGENTS.md AGENTS.override.md settings.json keybindings.json config.toml mcp.json hooks.json)
SECRET_RE='(^|/)\.env|secret|token|credential|password|auth\.json|\.key$|-key$|\.pem$'
# Build and OS artifacts that can sit inside skill folders; never configuration
GENERATED_RE='(^|/)(__pycache__|node_modules|\.venv)/|\.pyc$|(^|/)\.DS_Store$'
MAX_BYTES=$((5 * 1024 * 1024))
OWNER="${AGENT_HOME_GH_OWNER:-$(gh api user -q .login 2>/dev/null)}"

# Name of the private repo created for a home: ~/.codex -> codex-home
repo_name() { local b; b=$(basename "$1"); echo "${b#.}-home"; }

# Clone URL in the protocol gh is configured with (https goes through gh's credential helper)
repo_url() {
  if [[ "$(gh config get git_protocol 2>/dev/null)" == "ssh" ]]; then echo "git@github.com:$1.git"
  else echo "https://github.com/$1.git"; fi
}

# Visibility (PRIVATE / PUBLIC / INTERNAL) of a GitHub repo given as owner/name or URL; empty if unknown
visibility() { gh repo view "$1" --json visibility -q .visibility 2>/dev/null; }

# Credentials that grant account access or spend money; everything else is a low-value key the user accepts
HIGH_IMPACT_RE='^(github-|gitlab-|aws-|gcp-|azure-|private-key|stripe-|slack-|openai-|anthropic-|npm-|pypi-|digitalocean-|heroku-)'

# Run gitleaks and apply the user's policy (2026-11-28): API keys in agent config are accepted, because the
# keys are low-value and the remotes are private.
# Ordinary findings are listed as accepted; HIGH_IMPACT_RE rules block. Values are never printed (--redact).
# Called before every commit (staged diff) and before a first push (whole history).
# $1 = repo, rest = extra gitleaks args (e.g. --pre-commit --staged). Returns 0 to proceed, 1 if blocked or on error.
leak_check() {
  local repo="$1" report rc; shift
  report=$(mktemp "${TMPDIR:-/tmp}/ahc-gitleaks.XXXXXX")
  gitleaks git --redact --no-banner --log-level error --exit-code 2 \
    --report-format json --report-path "$report" "$@" "$repo" >/dev/null 2>&1
  rc=$?
  # 0 = clean, 2 = findings; anything else is a scanner error, so fail closed
  if [[ $rc -ne 0 && $rc -ne 2 ]]; then rm -f "$report"; echo "  gitleaks failed (exit $rc)"; return 1; fi
  python3 - "$report" "$HIGH_IMPACT_RE" <<'PY'
import json, re, sys
path, high = sys.argv[1], re.compile(sys.argv[2])
try:
    findings = json.load(open(path)) or []
except ValueError:
    findings = []
blocked = 0
for f in findings:
    where = f"{f['RuleID']} {f['File']}:{f['StartLine']}" + (f" @{f['Commit'][:8]}" if f.get("Commit") else "")
    if high.search(f["RuleID"]):
        blocked += 1
        print(f"  BLOCKED (high-impact credential): {where}")
    else:
        print(f"  accepted (low-value key, user policy): {where}")
sys.exit(1 if blocked else 0)
PY
  rc=$?
  rm -f "$report"
  return $rc
}

status=0
for h in "$@"; do
  h="${h%/}"
  echo "=== $h"
  top=$(git -C "$h" rev-parse --show-toplevel 2>/dev/null)
  real=$(cd "$h" 2>/dev/null && pwd -P)
  # Only a repo rooted at the home itself (symlinks resolved); never commit a parent repo that contains it
  if [[ -z "$top" || "$top" != "$real" ]]; then echo "skip: not a git repo rooted here"; continue; fi

  # Candidate new files: untracked, not ignored, under USER_CONFIG, not secret-looking, not generated, not huge
  new=()
  while IFS= read -r -d '' f; do
    if [[ "$f" =~ $SECRET_RE ]]; then echo "skip (secret-looking name): $f"; continue; fi
    if [[ "$f" =~ $GENERATED_RE ]]; then continue; fi
    sz=$(wc -c < "$h/$f" 2>/dev/null || echo 0)
    if (( sz > MAX_BYTES )); then echo "skip (> 5 MB): $f"; continue; fi
    new+=("$f")
  done < <(git -C "$h" ls-files --others --exclude-standard -z -- "${USER_CONFIG[@]}" 2>/dev/null)

  up=$(git -C "$h" rev-parse --abbrev-ref '@{u}' 2>/dev/null)
  origin=$(git -C "$h" remote get-url origin 2>/dev/null)

  if [[ $DRY -eq 1 ]]; then
    echo "tracked changes:"; git -C "$h" status --porcelain --untracked-files=no | sed 's/^/  /'
    echo "new config files: ${#new[@]}"; for f in ${new[@]+"${new[@]}"}; do echo "  ?? $f"; done
    if [[ -n "$up" ]]; then echo "upstream: $up"
    else
      [[ -n "$origin" ]] && echo "remote: origin exists without upstream; would push -u" \
                         || echo "remote: none; would create private repo $OWNER/$(repo_name "$h") and push -u"
      # The first push publishes every commit, so show the history scan result now
      echo "history scan:"
      if leak_check "$h"; then echo "  -> first push may proceed"; else echo "  -> first push would be refused"; fi
    fi
    continue
  fi

  # --- commit ---
  git -C "$h" add -u
  # ${arr[@]+...}: bash 3.2 treats an empty array as unset under set -u
  [[ ${#new[@]} -gt 0 ]] && git -C "$h" add -- ${new[@]+"${new[@]}"}
  if git -C "$h" diff --cached --quiet; then
    echo "nothing to commit"
  elif ! leak_check "$h" --pre-commit --staged; then
    # Fail closed: a high-impact credential (or a scanner error) means no commit and no push for this repo
    git -C "$h" reset -q; echo "ABORT: high-impact credential staged (or gitleaks failed), unstaged"; status=1; continue
  else
    git -C "$h" diff --cached --stat | tail -1
    if ! git -C "$h" commit -q -m "$MSG"; then echo "ABORT: commit failed (hook?)"; status=1; continue; fi
    echo "committed $(git -C "$h" rev-parse --short HEAD): $MSG"
  fi

  # --- first push: create the private remote when needed ---
  if [[ -z "$up" ]]; then
    if ! leak_check "$h"; then
      echo "NOT PUSHED: high-impact credential in the history (or gitleaks failed); the first push would publish it"; status=1; continue
    fi
    if [[ -z "$origin" ]]; then
      slug="$OWNER/$(repo_name "$h")"
      vis=$(visibility "$slug")
      if [[ -z "$vis" ]]; then
        gh repo create "$slug" --private --disable-issues --disable-wiki \
          --description "Private backup of ~/$(basename "$h") (agent-home-cleanup)" >/dev/null \
          || { echo "NOT PUSHED: gh repo create $slug failed"; status=1; continue; }
        echo "created private repo $slug"
      elif [[ "$vis" != "PRIVATE" ]]; then
        echo "NOT PUSHED: $slug already exists and is $vis"; status=1; continue
      fi
      origin=$(repo_url "$slug")
      git -C "$h" remote add origin "$origin"
    fi
    vis=$(visibility "$origin")
    # Agent homes hold paths, settings and sometimes tokens: push only where nobody else can read
    if [[ "$vis" != "PRIVATE" ]]; then echo "NOT PUSHED: origin visibility is '${vis:-unknown}', not PRIVATE"; status=1; continue; fi
    if git -C "$h" push -q -u origin HEAD; then echo "pushed to $(git -C "$h" rev-parse --abbrev-ref '@{u}') (new upstream)"
    else echo "NOT PUSHED: first push to $origin failed (remote not empty?); resolve by hand, never force"; status=1; fi
    continue
  fi

  # --- regular push ---
  vis=$(visibility "$(git -C "$h" remote get-url "${up%%/*}")")
  if [[ "$vis" != "PRIVATE" ]]; then echo "NOT PUSHED: remote visibility is '${vis:-unknown}', not PRIVATE"; status=1; continue; fi
  if [[ -z "$(git -C "$h" rev-list '@{u}..HEAD' 2>/dev/null)" ]]; then echo "up to date with $up"; continue; fi
  if git -C "$h" push -q; then echo "pushed to $up"; continue; fi
  # Behind the remote: rebase once, never force
  if git -C "$h" pull -q --rebase --autostash && git -C "$h" push -q; then
    echo "pushed to $up (after rebase)"
  else
    git -C "$h" rebase --abort 2>/dev/null
    echo "NOT PUSHED: push failed after one rebase attempt; resolve by hand"; status=1
  fi
done
exit $status
