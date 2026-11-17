#!/usr/bin/env bash
# check-ci-status.sh — Wait for CI and CodeRabbit review to complete on a PR
#
# Usage: bash check-ci-status.sh <owner> <repo> <pr_number> [max_wait_seconds]
# Example: bash check-ci-status.sh laststance corelive 17 300
#
# @param owner - GitHub repository owner
# @param repo - GitHub repository name
# @param pr_number - Pull request number
# @param max_wait_seconds - Maximum wait time (default: 300 = 5 minutes)
# @returns Exit 0 only when:
#          - CI is green: `gh pr checks` has no check pending, none in its
#            `fail` bucket (failure, error, timed out, waiting for approval)
#            and none in `cancel`. gh keeps only the newest run of each check
#            per workflow and event, so a run that a later run replaced is ignored.
#          - at least one check besides CodeRabbit exists, so CI ran at all
#          - every CodeRabbit check on HEAD is in the `pass` bucket
#          - CodeRabbit really reviewed HEAD, which three layers decide:
#              a) the per-SHA commit status `.description` ("Review completed" /
#                 "Review rate limited" / "Review in progress"), which cannot
#                 carry over from an earlier commit;
#              b) the latest CodeRabbit issue comment is not a rate-limit notice;
#              c) a coderabbitai[bot] review exists on HEAD. The status alone
#                 can read "Review completed" after a run that reviewed nothing
#                 (switch-time 7886215 and 77b5483: a 5-second run, the real
#                 review about an hour later), or "Reviews paused" / "Review
#                 skipped" on a head nobody reviewed, and a later run can
#                 overwrite it.
#          - or, in place of (a) to (c) when they show no PR-side review of HEAD:
#            CR_CLI_LOG holds a CodeRabbit CLI review that
#            `cli-review.sh --verify` accepts for HEAD. Run the gate from the
#            PR's checkout: when the review ran on an ancestor of HEAD, --verify
#            needs HEAD's commits there (the gate fetches pull/<n>/head if missing).
#          Exit 1 when a check failed or was cancelled (the script lists them),
#                 or a CodeRabbit check did not pass. CI is judged before the
#                 review: fixing it moves HEAD, which needs a new review anyway.
#          Exit 2 on timeout: a check still pending, or no check besides
#                 CodeRabbit ever appeared
#          Exit 3 when CodeRabbit's check says success but it did not review
#                 HEAD: rate limited, no review on HEAD, or still reviewing.
#                 Layer (b) alone is NOT sufficient: CodeRabbit EDITS its
#                 walkthrough comment in place, so a stale walkthrough from an
#                 earlier commit still reads as "a real review ran" (PR #184,
#                 2026-09-07 — merged an unreviewed diff on GATE_EXIT=0).
#                 Unless the review is still running, the caller should review
#                 HEAD with cli-review.sh and rerun with CR_CLI_LOG
#                 (review-loop.md Step 6b).
#                 In CLI mode (`CR_CLI_MODE=1`) exit 3 also means CI is green
#                 and no accepted CLI log covers HEAD yet.
#
# Environment (optional):
#   CR_CLI_LOG         log written by cli-review.sh (review-loop.md Step 6b); read
#                      only when the PR-side review did not cover HEAD
#   CR_CLI_ACCEPT      number of findings in that log dispositioned by hand (default 0)
#   CR_CLI_MODE        1 = CLI-first (`cli` argument): do not wait for a
#                      CodeRabbit GitHub check, ignore leftover bot reviews, and
#                      require CR_CLI_LOG. Used when the PR description has
#                      `@coderabbitai ignore` so the bot never runs.
#   CR_CHECK_INTERVAL  seconds between polls (default 10)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OWNER="${1:?Usage: $0 <owner> <repo> <pr_number> [max_wait_seconds]}"
REPO="${2:?Usage: $0 <owner> <repo> <pr_number> [max_wait_seconds]}"
PR_NUMBER="${3:?Usage: $0 <owner> <repo> <pr_number> [max_wait_seconds]}"
MAX_WAIT="${4:-300}"
INTERVAL="${CR_CHECK_INTERVAL:-10}"
ELAPSED=0

head_sha() { gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRefOid -q .headRefOid 2>/dev/null || true; }
# Number of lines in $1 that match the extended regex $2.
count() { printf '%s\n' "$1" | grep -cE "$2" || true; }
wait_more() { sleep "$INTERVAL"; ELAPSED=$((ELAPSED + INTERVAL)); }

echo "Waiting for CI on PR #$PR_NUMBER..."

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  HEAD_SHA=$(head_sha)
  if [ -z "$HEAD_SHA" ]; then
    echo "  Could not read the PR head. Retrying..."
    wait_more
    continue
  fi
  # gh sorts every check on the PR head (check runs and commit statuses alike)
  # into pass, fail, pending, skipping or cancel, and drops runs that a newer run
  # of the same check replaced. Judge the bucket, never gh's exit code: with
  # --json it is 0 even when a check failed, and a cancelled check exits 0 anyway.
  CHECKS=$(gh pr checks "$PR_NUMBER" --repo "$OWNER/$REPO" --json name,bucket,state \
    --jq '.[] | "\(.name)|\(.bucket)|\(.state)"' 2>/dev/null | sed '/^$/d' || true)
  # gh answers for whatever the head is now; read again if it moved meanwhile.
  if [ "$(head_sha)" != "$HEAD_SHA" ]; then
    echo "  HEAD moved while the checks were read. Reading again..."
    wait_more
    continue
  fi

  # CLI mode disables the GitHub bot (`@coderabbitai ignore`). Drop its rows so a
  # missing, pending, or leftover CodeRabbit check cannot stall or fail the gate.
  if [ "${CR_CLI_MODE:-}" = 1 ]; then
    CHECKS=$(printf '%s\n' "$CHECKS" | grep -viE '^[^|]*coderabbit' || true)
    CHECKS=$(printf '%s\n' "$CHECKS" | sed '/^$/d')
  fi

  CR_CHECKS=$(printf '%s\n' "$CHECKS" | grep -iE '^[^|]*coderabbit' || true)
  TOTAL=$(count "$CHECKS" '.')
  PENDING=$(count "$CHECKS" '\|pending\|')
  CR_TOTAL=$(count "$CR_CHECKS" '.')
  CR_PASS=$(count "$CR_CHECKS" '\|pass\|')
  CI_TOTAL=$((TOTAL - CR_TOTAL))

  if [ "${CR_CLI_MODE:-}" = 1 ]; then
    echo "  Checks on ${HEAD_SHA:0:7}: $((TOTAL - PENDING))/$TOTAL finished, CLI mode (${ELAPSED}s elapsed)"
  else
    echo "  Checks on ${HEAD_SHA:0:7}: $((TOTAL - PENDING))/$TOTAL finished, CodeRabbit: $CR_PASS pass / $CR_TOTAL found (${ELAPSED}s elapsed)"
  fi

  # No CodeRabbit check: wait for the bot unless this is a CLI review (cli mode,
  # or a CR_CLI_LOG already in hand). `@coderabbitai ignore` often posts none.
  if [ "$CR_TOTAL" -eq 0 ]; then
    if [ "${CR_CLI_MODE:-}" != 1 ] && [ -z "${CR_CLI_LOG:-}" ]; then
      echo "  CodeRabbit not found on HEAD yet. Waiting..."
      wait_more
      continue
    fi
  fi

  if [ "$(count "$CR_CHECKS" '\|(fail|cancel)\|')" -gt 0 ]; then
    echo ""
    echo "CodeRabbit check failed."
    printf '%s\n' "$CR_CHECKS" | while IFS='|' read -r name bucket state; do
      echo "  [$bucket] $name ($state)"
    done
    exit 1
  fi

  # CodeRabbit alone is not CI; a PR whose workflows have not started is not green.
  if [ "$CI_TOTAL" -eq 0 ]; then
    echo "  No CI checks besides CodeRabbit on HEAD yet. Waiting..."
    wait_more
    continue
  fi

  if [ "$PENDING" -eq 0 ]; then
    echo ""
    echo "All $TOTAL checks finished:"
    printf '%s\n' "$CHECKS" | while IFS='|' read -r name bucket state; do
      echo "  [$bucket] $name ($state)"
    done

    # CI verdict: fail and cancel block; pass and skipping (skipped, neutral) do not.
    NOT_PASSED=$(printf '%s\n' "$CHECKS" | grep -E '\|(fail|cancel)\|' || true)
    if [ -n "$NOT_PASSED" ]; then
      echo ""
      echo "$(count "$NOT_PASSED" '.') check(s) did not pass:"
      printf '%s\n' "$NOT_PASSED" | while IFS='|' read -r name bucket state; do
        echo "  - $name: $bucket ($state)"
      done
      echo "  Fix them (review-loop.md Step 6e). A cancelled or timed-out check blocks like a failed one;"
      echo "  rerun it once its cause is clear."
      exit 1
    fi

    # Even with no unresolved threads, we must not merge until every CodeRabbit
    # check on current HEAD passed. CLI mode already dropped those rows.
    if [ "${CR_CLI_MODE:-}" != 1 ] && [ "$CR_PASS" -lt "$CR_TOTAL" ]; then
      echo ""
      echo "CodeRabbit review is not in completed+success state yet."
      exit 1
    fi

    # CLI mode: the bot is disabled. Do not accept a leftover GitHub review.
    # Layers (a)–(c) stay for the default path only.
    echo ""
    if [ "${CR_CLI_MODE:-}" = 1 ]; then
      echo "CLI mode: a CodeRabbit CLI review must cover ${HEAD_SHA:0:7} (the GitHub bot is disabled)."
      NO_REVIEW="cli mode"
    else
    # CodeRabbit's check reads success even when it did not review HEAD, so three
    # layers decide whether it did.
    #
    # IMPORTANT: real walkthrough comments include an informational footer
    #   <sub>Review rate limit: X/Y reviews remaining, refill in N minutes.</sub>
    # which is a STATUS report, not a "we couldn't review" notice. The old
    # naive `grep -qiE 'rate.?limit'` matched that footer and produced
    # false-positive exit 3 even when CodeRabbit had genuinely reviewed
    # (just used its last credit). Resolve by checking for the walkthrough
    # marker first — if present, the comment IS a real review regardless
    # of any rate-limit text in its footer.
    echo "Verifying that CodeRabbit really reviewed ${HEAD_SHA:0:7}..."
    NO_REVIEW=""

    # Layer (a) — AUTHORITATIVE for rate limits. CodeRabbit stamps a per-SHA
    # commit status whose .description carries the verdict while .state is
    # `success` in every case (including a rate-limited run). Unlike the
    # walkthrough comment — edited in place, so a stale one still matches layer
    # (b)'s grep — this is per-SHA and cannot carry over from an earlier commit.
    CR_DESC=$(gh api "repos/$OWNER/$REPO/commits/$HEAD_SHA/statuses" \
      --jq '[.[] | select(.context == "CodeRabbit")] | .[0].description' 2>/dev/null || true)
    case "$CR_DESC" in
      *"rate limited"*|*"Rate limited"*|*"rate-limited"*)
        echo "  CodeRabbit per-SHA status on ${HEAD_SHA:0:7}: \"$CR_DESC\" — no real review ran."
        NO_REVIEW="rate limited" ;;
      *"in progress"*|*"In progress"*|*"queued"*|*"Queued"*)
        echo "  CodeRabbit per-SHA status on ${HEAD_SHA:0:7}: \"$CR_DESC\" — review not finished."
        echo "  Caller must wait for the review to complete and retry."
        exit 3 ;;
      *"completed"*|*"Completed"*)
        echo "  CodeRabbit per-SHA status on ${HEAD_SHA:0:7}: \"$CR_DESC\" — checking that a review exists." ;;
      # "Reviews paused — CodeRabbit will not run on this PR", "Review skipped: reviews are disabled
      # for this base branch": this push was not reviewed, but a review made before it still counts.
      *"paused"*|*"Paused"*|*"skipped"*|*"Skipped"*)
        echo "  CodeRabbit per-SHA status on ${HEAD_SHA:0:7}: \"$CR_DESC\" — it did not run on this push;"
        echo "  only a review already made on this commit counts." ;;
      *)
        echo "  CodeRabbit per-SHA status on ${HEAD_SHA:0:7}: \"${CR_DESC:-<none>}\" — unrecognised;"
        echo "  the layers below decide." ;;
    esac

    # Layer (b) — the latest CodeRabbit issue comment. The per-issue comments
    # endpoint ignores `sort`/`direction` (only the repo-wide /issues/comments
    # endpoint honours them), so the old `per_page=10&sort=created&direction=desc`
    # returned the OLDEST 10 comments and `.[0]` picked CodeRabbit's FIRST
    # comment — never the rate-limit notice. Paginate ascending and take the LAST
    # match instead. Bodies are multi-line, so base64-encode per comment to keep
    # `tail -1` line-oriented.
    if [ -z "$NO_REVIEW" ]; then
      LATEST_CR_COMMENT=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments?per_page=100" --paginate \
        --jq '.[] | select(.user.login == "coderabbitai" or .user.login == "coderabbitai[bot]") | .body | @base64' 2>/dev/null | tail -1 | base64 -d 2>/dev/null || true)

      if [ -n "$LATEST_CR_COMMENT" ]; then
        if echo "$LATEST_CR_COMMENT" | grep -qE '<!-- walkthrough_start -->|^## Walkthrough'; then
          echo "  Confirmed: latest CodeRabbit comment contains walkthrough markers — real review ran."
        elif echo "$LATEST_CR_COMMENT" | grep -qiE 'rate.?limit'; then
          echo "  Latest CodeRabbit comment is a rate-limit notice — no real review ran."
          NO_REVIEW="rate limited"
        else
          echo "  Confirmed: latest CodeRabbit comment is not a rate-limit notice."
        fi
      fi
    fi

    # Layer (c) — a review on HEAD. A run can end in "Review completed" without
    # reviewing anything, and an earlier walkthrough still passes (b). Only a coderabbitai[bot] review whose commit_id is HEAD shows
    # this commit was read: APPROVED, or any review with a body (an empty-bodied
    # COMMENTED row is just a thread reply). HEAD_SHA is hex, so it is safe to
    # splice into the filter; `gh api --jq` takes no --arg.
    if [ -z "$NO_REVIEW" ]; then
      HEAD_REVIEWS=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews?per_page=100" --paginate \
        --jq ".[] | select(.commit_id == \"$HEAD_SHA\" and .user.login == \"coderabbitai[bot]\" and (.state == \"APPROVED\" or (.body | length) > 0)) | .id" 2>/dev/null || true)
      HEAD_REVIEWS=$(count "$HEAD_REVIEWS" '.')
      if [ "$HEAD_REVIEWS" -eq 0 ]; then
        echo "  No CodeRabbit review object on ${HEAD_SHA:0:7}: its status alone does not show that this commit was reviewed."
        NO_REVIEW="no review on HEAD"
      else
        echo "  Confirmed: CodeRabbit left $HEAD_REVIEWS review(s) on ${HEAD_SHA:0:7}."
      fi
    fi
    fi

    # A PR-side review that did not cover HEAD can be replaced by a CodeRabbit CLI
    # review of HEAD (cli-review.sh, review-loop.md Step 6b). Without one, exit 3.
    if [ -n "$NO_REVIEW" ]; then
      if [ -z "${CR_CLI_LOG:-}" ]; then
        echo "  Caller must review HEAD with cli-review.sh (review-loop.md Step 6b) and rerun with CR_CLI_LOG set."
        if [ "$NO_REVIEW" = "rate limited" ]; then
          echo "  Fall back to wait-for-ratelimit.sh only when the CLI cannot run (cli-review.sh exit 5 or 6)."
        fi
        exit 3
      fi
      echo "  Checking the CodeRabbit CLI review in CR_CLI_LOG instead..."
      # --verify's ancestor check needs HEAD's commits in this checkout.
      if ! git cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null; then
        git fetch -q origin "pull/$PR_NUMBER/head" 2>/dev/null || true
        if ! git cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null; then
          echo "  HEAD ${HEAD_SHA:0:7} is not in this checkout; run the gate from the PR's checkout."
        fi
      fi
      if ! bash "$SCRIPT_DIR/cli-review.sh" --verify "$CR_CLI_LOG" "$HEAD_SHA" "${CR_CLI_ACCEPT:-0}"; then
        echo "  That CLI review does not cover HEAD (see above). Not merge-ready."
        exit 3
      fi
      if [ "$NO_REVIEW" = "cli mode" ]; then
        echo "  Accepted: the CLI review covers ${HEAD_SHA:0:7}."
      else
        echo "  Accepted: the CLI review replaces the missing PR-side review on ${HEAD_SHA:0:7}."
      fi
    fi

    echo ""
    echo "All checks passed."
    exit 0
  fi

  wait_more
done

echo ""
echo "Timeout after ${MAX_WAIT}s. Current status:"
gh pr checks "$PR_NUMBER" --repo "$OWNER/$REPO" 2>/dev/null || echo "(Unable to fetch checks)"
exit 2
