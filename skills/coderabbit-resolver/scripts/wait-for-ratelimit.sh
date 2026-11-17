#!/usr/bin/env bash
# wait-for-ratelimit.sh — Detect CodeRabbit rate limit, wait for expiry, trigger full review
#
# Fallback only: review-loop.md Step 6b reviews HEAD with cli-review.sh first,
# and comes here when the CodeRabbit CLI cannot run (cli-review.sh exit 5 or 6).
#
# Usage: bash wait-for-ratelimit.sh <owner> <repo> <pr_number>
# Example: bash wait-for-ratelimit.sh laststance corelive 17
#
# @param owner - GitHub repository owner
# @param repo - GitHub repository name
# @param pr_number - Pull request number
# @returns Exit 0 if rate limit detected + waited + full review triggered
#          Exit 1 if no rate limit found (normal flow)
#          Exit 2 if error occurred

set -euo pipefail

OWNER="${1:?Usage: $0 <owner> <repo> <pr_number>}"
REPO="${2:?Usage: $0 <owner> <repo> <pr_number>}"
PR_NUMBER="${3:?Usage: $0 <owner> <repo> <pr_number>}"

BUFFER_SECONDS=30

echo "Checking for CodeRabbit rate limit on PR #$PR_NUMBER..."

# Layer (a) — AUTHORITATIVE, the same per-SHA signal check-ci-status.sh gates on.
# CodeRabbit can announce a rate limit through the commit status ALONE, posting
# no comment at all. On PR #184 (2026-09-07) the status on a09904fb read
# "Review rate limited" at 16:05:55Z while the newest CodeRabbit comment was its
# walkthrough from 14:15:55Z — edited in place, so it still carried the
# walkthrough marker. Both comment checks below then misfire: the walkthrough
# guard reads "a real review ran" and the `rate.?limit` grep finds nothing,
# each exiting 1 and dead-ending the recovery path that check-ci-status.sh's
# exit 3 sends the caller here for. When the status says rate limited, trust it
# and skip both comment short-circuits; the comment is still read below for the
# wait duration (absent one, the 15-minute fallback applies).
HEAD_SHA=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRefOid -q .headRefOid 2>/dev/null || true)
CR_DESC=""
if [ -n "$HEAD_SHA" ]; then
  CR_DESC=$(gh api "repos/$OWNER/$REPO/commits/$HEAD_SHA/statuses" \
    --jq '[.[] | select(.context == "CodeRabbit")] | .[0].description' 2>/dev/null || true)
fi
STATUS_RATE_LIMITED=0
case "$CR_DESC" in
  *"rate limited"*|*"Rate limited"*|*"rate-limited"*)
    STATUS_RATE_LIMITED=1
    echo "  CodeRabbit per-SHA status on ${HEAD_SHA:0:7}: \"$CR_DESC\" — rate limited (authoritative)." ;;
esac

# Fetch the most recent CodeRabbit comment body.
#
# Two bug-fixes vs prior versions:
# 1. REST returns `coderabbitai[bot]` for App-installed bots; older accounts
#    and some GraphQL endpoints return the bare `coderabbitai`. Match both.
# 2. CodeRabbit comment bodies are multi-line (starting with HTML auto-gen
#    markers, then markdown). The previous `head -1` of the joined-bodies
#    string took the *first line of the first body* — which is just the HTML
#    summary marker, never the rate-limit warning that lives further down.
#    Reduce to a single body inside jq so the entire body lands in the var.
# 3. The per-issue comments endpoint ignores `sort`/`direction` (only the
#    repo-wide /issues/comments endpoint honours them), so the old
#    `per_page=10&sort=created&direction=desc` returned the OLDEST 10 comments
#    and `.[0]` picked CodeRabbit's FIRST comment — never the rate-limit notice.
#    Paginate ascending and take the LAST match instead. Bodies are multi-line,
#    so base64-encode per comment to keep `tail -1` line-oriented.
LATEST_COMMENT=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments?per_page=100" --paginate \
  --jq '.[] | select(.user.login == "coderabbitai" or .user.login == "coderabbitai[bot]") | .body | @base64' 2>/dev/null | tail -1 | base64 -d 2>/dev/null || true)

if [ "$STATUS_RATE_LIMITED" -eq 0 ] && [ -z "$LATEST_COMMENT" ]; then
  echo "  No CodeRabbit comments found."
  exit 1
fi

# Real CodeRabbit walkthrough comments include an informational footer
#   <sub>Review rate limit: X/Y reviews remaining, refill in N minutes.</sub>
# which the old naive `grep -qiE 'rate.?limit'` matched as if it were a
# "we couldn't review" notice — leading to a 60-minute wait + redundant
# `@coderabbitai full review` post when CodeRabbit had ALREADY reviewed.
# Reject those comments first using the walkthrough marker as a positive
# signal of a real review.
if [ "$STATUS_RATE_LIMITED" -eq 0 ] && echo "$LATEST_COMMENT" | grep -qE '<!-- walkthrough_start -->|^## Walkthrough'; then
  echo "  Latest CodeRabbit comment is a real review (walkthrough), not a rate-limit notice."
  exit 1
fi

# Match rate limit patterns (case-insensitive)
# Common CodeRabbit rate limit messages:
#   "rate limit" / "rate-limited" / "rate limited"
#   "try again in X minutes" / "available in approximately X minutes"
#   "will be available in X min"
if [ "$STATUS_RATE_LIMITED" -eq 0 ] && ! echo "$LATEST_COMMENT" | grep -qiE 'rate.?limit'; then
  echo "  No rate limit detected in latest CodeRabbit comment."
  exit 1
fi

echo "  Rate limit detected!"

# Extract wait time from the comment
# Patterns: "X minutes", "X min", "X hours", "X seconds", "X sec"
WAIT_SECONDS=0

# Extract wait time using POSIX ERE so the script works on BSD/macOS grep too
# (BSD grep does not support `-P` Perl regex). Pattern uses `[0-9]+` instead of
# `\d+` and ERE alternation `(...)` instead of non-capturing `(?:...)`.
#
# CodeRabbit's rate-limit comment can include multiple numbers (e.g.
# "wait 24 minutes and 22 seconds before requesting another review"), so we
# add minutes + seconds together and treat hours separately as a max-unit
# fallback for very long limits.

# Minutes
MINUTES=$(echo "$LATEST_COMMENT" | grep -oiE '[0-9]+ ?(minutes?|mins?)' | head -1 | grep -oE '[0-9]+' || true)
if [ -n "$MINUTES" ]; then
  WAIT_SECONDS=$((MINUTES * 60))
  echo "  Detected wait time: ${MINUTES} minute(s)"
fi

# Seconds — added on top of minutes when the comment mentions both
SECONDS_VAL=$(echo "$LATEST_COMMENT" | grep -oiE '[0-9]+ ?(seconds?|secs?)' | head -1 | grep -oE '[0-9]+' || true)
if [ -n "$SECONDS_VAL" ]; then
  WAIT_SECONDS=$((WAIT_SECONDS + SECONDS_VAL))
  echo "  Detected additional wait time: ${SECONDS_VAL} second(s)"
fi

# Hours — used only if neither minutes nor seconds were found
if [ "$WAIT_SECONDS" -eq 0 ]; then
  HOURS=$(echo "$LATEST_COMMENT" | grep -oiE '[0-9]+ ?(hours?|hrs?)' | head -1 | grep -oE '[0-9]+' || true)
  if [ -n "$HOURS" ]; then
    WAIT_SECONDS=$((HOURS * 3600))
    echo "  Detected wait time: ${HOURS} hour(s)"
  fi
fi

# Fallback: if rate limit detected but no time extracted, default to 15 minutes
if [ "$WAIT_SECONDS" -eq 0 ]; then
  WAIT_SECONDS=900
  echo "  Could not extract wait time. Defaulting to 15 minutes."
fi

# Add buffer
TOTAL_WAIT=$((WAIT_SECONDS + BUFFER_SECONDS))
echo "  Waiting ${TOTAL_WAIT}s (${WAIT_SECONDS}s + ${BUFFER_SECONDS}s buffer)..."

# Wait with progress indicator
ELAPSED=0
INTERVAL=30
while [ "$ELAPSED" -lt "$TOTAL_WAIT" ]; do
  REMAINING=$((TOTAL_WAIT - ELAPSED))
  REMAINING_MIN=$((REMAINING / 60))
  echo "  Waiting... ${REMAINING}s remaining (~${REMAINING_MIN}m)"

  if [ "$REMAINING" -lt "$INTERVAL" ]; then
    sleep "$REMAINING"
    ELAPSED=$TOTAL_WAIT
  else
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
  fi
done

echo "  Rate limit wait complete. Triggering full review..."

# Post @coderabbitai full review to trigger a complete re-review
gh pr comment "$PR_NUMBER" --repo "$OWNER/$REPO" --body "@coderabbitai full review"

if [ $? -eq 0 ]; then
  echo "  Posted '@coderabbitai full review' on PR #$PR_NUMBER."
  echo "  Full review triggered successfully."
  exit 0
else
  echo "  ERROR: Failed to post full review comment."
  exit 2
fi
