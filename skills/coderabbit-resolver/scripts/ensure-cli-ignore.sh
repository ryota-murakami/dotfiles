#!/usr/bin/env bash
# ensure-cli-ignore.sh — Put `@coderabbitai ignore` in the PR description so the
#                        GitHub bot does not auto-review. Idempotent.
#
# Usage: bash ensure-cli-ignore.sh <owner> <repo> <pr_number>
# Example: bash ensure-cli-ignore.sh laststance corelive 17
#
# The marker must live in the pull request *description*, not a comment —
# CodeRabbit ignores a comment with the same text. `gh pr edit --body-file`
# replaces the whole body, so this script reads, appends if missing, and writes
# back. CLI mode (review-loop.md) keeps the line; do not strip it afterwards.
#
# @param owner - GitHub repository owner
# @param repo - GitHub repository name
# @param pr_number - Pull request number
# @returns Exit 0 when the description already has the marker, or after adding it
#          Exit 1 when the PR body cannot be read or written

set -euo pipefail

USAGE="Usage: $0 <owner> <repo> <pr_number>"
OWNER="${1:?$USAGE}"
REPO="${2:?$USAGE}"
PR_NUMBER="${3:?$USAGE}"
case "$PR_NUMBER" in
  ''|*[!0-9]*) echo "$USAGE"; exit 1 ;;
esac

MARKER='@coderabbitai ignore'

if ! BODY=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json body -q .body); then
  echo "Could not read PR #$PR_NUMBER in $OWNER/$REPO."
  exit 1
fi
# gh prints the JSON null as the string "null" when the body is unset.
if [ "$BODY" = "null" ]; then
  BODY=""
fi

if printf '%s\n' "$BODY" | grep -qF "$MARKER"; then
  echo "PR #$PR_NUMBER description already has $MARKER."
  exit 0
fi

if [ -z "$BODY" ]; then
  NEW="$MARKER"
else
  NEW=$(printf '%s\n\n%s' "$BODY" "$MARKER")
fi

if ! printf '%s\n' "$NEW" | gh pr edit "$PR_NUMBER" --repo "$OWNER/$REPO" --body-file -; then
  echo "Could not write $MARKER to PR #$PR_NUMBER description."
  exit 1
fi

echo "Added $MARKER to PR #$PR_NUMBER description. The GitHub bot will not auto-review this PR."
exit 0
