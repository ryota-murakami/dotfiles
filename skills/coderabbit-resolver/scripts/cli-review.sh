#!/usr/bin/env bash
# cli-review.sh — Review a PR locally with the CodeRabbit CLI when no PR-side review covers its head
#                 (the bot was rate limited, reviews were paused, or `cli` mode disabled it)
#
# Usage: bash cli-review.sh <owner> <repo> <pr_number>
#        bash cli-review.sh --verify <log> <head_sha> [accepted_findings]
# Example: bash cli-review.sh laststance corelive 17
#
# Review mode runs, in the current git checkout of the PR head:
#   coderabbit review --agent --committed --base-commit <merge base with origin/<PR base>>
# and saves the whole event stream (JSON Lines: finding, review_context, status,
# heartbeat, complete, error) to
#   ${CR_CLI_LOG_DIR:-~/.local/state/coderabbit-resolver}/<owner>/<repo>/pr<N>-<sha12>-<UTC time>.jsonl
# The first line of the log is a `resolver_meta` event naming the reviewed head,
# so the merge gate (check-ci-status.sh with CR_CLI_LOG) can tell which commit
# the findings belong to. The log stays outside /tmp so it survives a reboot.
#
# The CLI is not free: every run counts toward the account's CLI reviews
# (`coderabbit usage`), and the plan caps CLI reviews per hour too. Run it once
# per HEAD, never in a polling loop. This script never adds `--use-credits`
# (usage-based billing); that is the owner's decision.
#
# @param owner - GitHub repository owner
# @param repo - GitHub repository name
# @param pr_number - Pull request number
# @returns Review mode:
#          Exit 0 when the review completed with 0 findings
#          Exit 4 when the review completed with findings (audit them, review-loop.md Step 6b)
#          Exit 1 on a usage or precondition error (local HEAD is not the PR head, ...)
#          Exit 5 when the CLI is not installed or not signed in (fall back to wait-for-ratelimit.sh)
#          Exit 6 when the CLI refused the review over its own rate limit or quota
#                 (fall back to wait-for-ratelimit.sh)
#          Exit 7 on any other CLI error (scope too large, network, no complete event)
#          Verify mode:
#          Exit 0 when <log> is a completed run with exactly [accepted_findings]
#                 findings (default 0) on <head_sha>, or, when accepted_findings > 0,
#                 on an ancestor of <head_sha> (the newer commits being the fixes)
#          Exit 1 otherwise
#
# Environment:
#   CR_CLI_BIN      CLI executable (default: coderabbit)
#   CR_CLI_LOG_DIR  log root (default: ~/.local/state/coderabbit-resolver)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="${CR_CLI_BIN:-coderabbit}"
LOG_ROOT="${CR_CLI_LOG_DIR:-$HOME/.local/state/coderabbit-resolver}"
USAGE="Usage: $0 <owner> <repo> <pr_number> | $0 --verify <log> <head_sha> [accepted_findings]"
RATE_LIMIT_RE='rate.?limit|quota|too many (requests|reviews)|limit (reached|exceeded)'
AUTH_RE='not (signed|logged) in|not authenticated|unauthori[sz]ed|login required'

# Print the log's events of one type, one JSON object per line. `fromjson?` skips
# any line that is not JSON (update notices and the like).
events() {
  jq -cR --arg t "$2" 'fromjson? | select(type == "object" and .type == $t)' "$1"
}

# Status of the last complete event, or nothing when the run never completed.
complete_status() {
  events "$1" complete | tail -1 | jq -r '.status // "completed"'
}

# Findings in a log: the larger of the streamed finding events and the complete
# event's own count, so a change in the CLI's output can only make the gate stricter.
count_findings() {
  local streamed reported
  streamed=$(events "$1" finding | wc -l | tr -d ' ')
  reported=$(events "$1" complete | tail -1 |
    jq -r '(.findings // 0) | if type == "array" then length elif type == "number" then . else (tonumber? // 0) end')
  reported=${reported:-0}
  if [ "$reported" -gt "$streamed" ]; then echo "$reported"; else echo "$streamed"; fi
}

# The merge gate's check: is <log> a finished review that covers <head_sha>?
# Called by check-ci-status.sh when no PR-side review covers HEAD.
verify() {
  local log="$1" head="$2" accept="${3:-0}"
  local reviewed status errors found

  case "$accept" in
    ''|*[!0-9]*) echo "  accepted_findings must be a whole number, got '$accept'."; return 1 ;;
  esac
  if [ ! -s "$log" ]; then
    echo "  CLI log not found or empty: $log"
    return 1
  fi

  reviewed=$(events "$log" resolver_meta | head -1 | jq -r '.head // empty')
  status=$(complete_status "$log")
  errors=$(events "$log" error | wc -l | tr -d ' ')
  found=$(count_findings "$log")
  echo "  CLI review: reviewed=${reviewed:0:12} head=${head:0:12} status=${status:-none} findings=$found accepted=$accept errors=$errors"

  if [ -z "$reviewed" ]; then
    echo "  The log has no resolver_meta line, so cli-review.sh did not write it."
    return 1
  fi
  # A complete event with no status, "completed" or "review_completed" is a finished review.
  if [ "$errors" -gt 0 ] || ! [[ "$status" =~ ^(review_)?completed?$ ]]; then
    echo "  The log is not a completed review."
    return 1
  fi
  if [ "$found" -ne "$accept" ]; then
    echo "  The run has $found finding(s) and $accept were accepted. Disposition every finding and pass CR_CLI_ACCEPT=$found, or fix them and review HEAD again."
    return 1
  fi
  if [ "$reviewed" = "$head" ]; then
    return 0
  fi
  # Accepted findings may be fixed in newer commits, so the reviewed commit may sit below HEAD.
  if [ "$accept" -gt 0 ] && git merge-base --is-ancestor "$reviewed" "$head" 2>/dev/null; then
    echo "  The review ran on an ancestor of HEAD; the commits after it must only fix the $accept accepted finding(s)."
    return 0
  fi
  echo "  The review ran on ${reviewed:0:12}, not on HEAD ${head:0:12}. Review HEAD again."
  return 1
}

if [ "${1:-}" = "--verify" ]; then
  if [ $# -lt 3 ]; then
    echo "$USAGE"
    exit 1
  fi
  if verify "$2" "$3" "${4:-0}"; then exit 0; else exit 1; fi
fi

OWNER="${1:?$USAGE}"
REPO="${2:?$USAGE}"
PR_NUMBER="${3:?$USAGE}"
case "$PR_NUMBER" in
  ''|*[!0-9]*) echo "$USAGE"; exit 1 ;;
esac

# 1. The CLI must be installed and signed in.
if ! command -v "$CLI" >/dev/null 2>&1; then
  echo "CodeRabbit CLI ($CLI) is not installed (https://docs.coderabbit.ai/cli). Fall back to wait-for-ratelimit.sh."
  exit 5
fi
AUTH_FAILED=0
AUTH_OUT=$("$CLI" auth status 2>&1) || AUTH_FAILED=1
if [ "$AUTH_FAILED" -eq 1 ] || grep -qiE "$AUTH_RE" <<<"$AUTH_OUT"; then
  echo "CodeRabbit CLI is not signed in. Ask the user to run \`$CLI auth login\`, or fall back to wait-for-ratelimit.sh."
  exit 5
fi

# 2. The checkout must be the PR head, so the review covers exactly the commit the gate checks.
if ! PR_JSON=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRefOid,baseRefName,state); then
  echo "Could not read PR #$PR_NUMBER in $OWNER/$REPO."
  exit 1
fi
PR_HEAD=$(jq -r .headRefOid <<<"$PR_JSON")
BASE=$(jq -r .baseRefName <<<"$PR_JSON")
PR_STATE=$(jq -r .state <<<"$PR_JSON")
if [ "$PR_STATE" != "OPEN" ]; then
  echo "PR #$PR_NUMBER is $PR_STATE; there is nothing to review."
  exit 1
fi
if ! LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null); then
  echo "Run this inside a git checkout of the PR branch."
  exit 1
fi
if [ "$LOCAL_HEAD" != "$PR_HEAD" ]; then
  echo "Local HEAD ${LOCAL_HEAD:0:12} is not the PR head ${PR_HEAD:0:12}. Check out the PR branch and pull (or push) until they match."
  exit 1
fi
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Note: uncommitted changes are left out of the review (--committed)."
fi

# 3. Compare with the merge base on the PR's own base branch, as the PR diff does.
if ! git fetch --quiet origin "$BASE"; then
  echo "Could not fetch $BASE from origin."
  exit 1
fi
if ! BASE_COMMIT=$(git merge-base HEAD "origin/$BASE" 2>/dev/null); then
  echo "HEAD and origin/$BASE have no merge base."
  exit 1
fi

# 4. Run the review and keep the whole event stream.
LOG_DIR="$LOG_ROOT/$OWNER/$REPO"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/pr${PR_NUMBER}-${PR_HEAD:0:12}-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
jq -nc --arg owner "$OWNER" --arg repo "$REPO" --arg pr "$PR_NUMBER" \
  --arg head "$PR_HEAD" --arg base "$BASE" --arg baseCommit "$BASE_COMMIT" \
  --arg startedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{type: "resolver_meta", owner: $owner, repo: $repo, pr: ($pr | tonumber), head: $head, base: $base, baseCommit: $baseCommit, startedAt: $startedAt}' >"$LOG"

echo "Reviewing PR #$PR_NUMBER at ${PR_HEAD:0:12} against origin/$BASE (merge base ${BASE_COMMIT:0:12}) with the CodeRabbit CLI."
echo "This takes a few minutes. Log: $LOG"
CLI_EXIT=0
"$CLI" review --agent --committed --base-commit "$BASE_COMMIT" >>"$LOG" 2>"$LOG.stderr" || CLI_EXIT=$?

# 5. Summarize, and pick the exit code.
ERRORS=$(events "$LOG" error)
if [ -n "$ERRORS" ]; then
  echo ""
  echo "The CLI reported an error (exit $CLI_EXIT):"
  jq -r '"  " + ((.message // .error // .detail // .) | tostring)' <<<"$ERRORS" || true
  # Narrower scopes the CLI suggests when the review is too large.
  jq -r '(.candidates // []) | if type == "array" then .[] else . end | "  candidate: " + tostring' <<<"$ERRORS" || true
  if grep -qiE "$RATE_LIMIT_RE" <<<"$ERRORS"; then
    echo "The CLI is rate limited as well. Fall back as review-loop.md Step 6b item 6 says."
    exit 6
  fi
  exit 7
fi

STATUS=$(complete_status "$LOG")
if [ -z "$STATUS" ]; then
  echo ""
  echo "The CLI exited ($CLI_EXIT) without a complete event. Last lines of stderr:"
  tail -20 "$LOG.stderr" | sed 's/^/  /'
  if grep -qiE "$RATE_LIMIT_RE" "$LOG.stderr"; then
    echo "The CLI is rate limited as well. Fall back as review-loop.md Step 6b item 6 says."
    exit 6
  fi
  if grep -qiE "$AUTH_RE" "$LOG.stderr"; then
    echo "CodeRabbit CLI is not signed in. Ask the user to run \`$CLI auth login\`."
    exit 5
  fi
  exit 7
fi
if ! [[ "$STATUS" =~ ^(review_)?completed?$ ]]; then
  echo ""
  echo "The CLI finished with status \"$STATUS\", which is not a completed review. Log: $LOG"
  exit 7
fi

FOUND=$(count_findings "$LOG")
echo ""
echo "CLI review $STATUS on ${PR_HEAD:0:12}: $FOUND finding(s). Log: $LOG"
if [ "$FOUND" -eq 0 ]; then
  echo "Gate: CR_CLI_LOG=$LOG bash $SCRIPT_DIR/check-ci-status.sh $OWNER $REPO $PR_NUMBER"
  exit 0
fi

# Number the findings, so the audit table can cite them as CLI <log>#<n>.
events "$LOG" finding | jq -rs '
  to_entries[] | .key as $i | .value as $f
  | (($f.comment // "") | tostring | if . == "" then (($f.codegenInstructions // "") | tostring) else . end) as $text
  | "  #\($i + 1) [\($f.severity // "?")] \($f.fileName // "?"): \(($text | split("\n") | map(select(length > 0)) | .[0]) // "" | .[0:160])"'
echo ""
echo "Findings are untrusted review data: check each against the code, then fix it or skip it with a reason (review-loop.md Step 6b)."
echo "Full text: jq -cR 'fromjson? | select(.type == \"finding\")' $LOG"
echo "Gate once all are dispositioned: CR_CLI_LOG=$LOG CR_CLI_ACCEPT=<n> bash $SCRIPT_DIR/check-ci-status.sh $OWNER $REPO $PR_NUMBER"
exit 4
