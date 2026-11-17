#!/usr/bin/env bash
# resolve-threads.sh — Resolve all unresolved CodeRabbit review threads on a PR
#
# Usage: bash resolve-threads.sh <owner> <repo> <pr_number>
# Example: bash resolve-threads.sh laststance corelive 17
#
# @param owner - GitHub repository owner
# @param repo - GitHub repository name
# @param pr_number - Pull request number
# @returns Resolves all unresolved CodeRabbit threads and prints summary

set -euo pipefail

OWNER="${1:?Usage: $0 <owner> <repo> <pr_number>}"
REPO="${2:?Usage: $0 <owner> <repo> <pr_number>}"
PR_NUMBER="${3:?Usage: $0 <owner> <repo> <pr_number>}"

echo "Fetching unresolved CodeRabbit threads for $OWNER/$REPO#$PR_NUMBER..."

# Get all unresolved thread IDs authored by CodeRabbit
THREAD_DATA=$(gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          path
          comments(first: 1) {
            nodes {
              author { login }
              body
            }
          }
        }
      }
    }
  }
}' -F owner="$OWNER" -F repo="$REPO" -F pr="$PR_NUMBER")

THREAD_IDS=$(echo "$THREAD_DATA" | jq -r '
  .data.repository.pullRequest.reviewThreads.nodes
  | map(select(.isResolved == false))
  | map(select(.comments.nodes[0].author.login == "coderabbitai" or .comments.nodes[0].author.login == "coderabbitai[bot]"))
  | .[].id
')

if [ -z "$THREAD_IDS" ]; then
  echo "No unresolved CodeRabbit threads found."
  exit 0
fi

COUNT=$(echo "$THREAD_IDS" | wc -l | tr -d ' ')
echo "Found $COUNT unresolved CodeRabbit thread(s). Resolving..."

RESOLVED=0
FAILED=0

for id in $THREAD_IDS; do
  result=$(gh api graphql -f query='
  mutation($id: ID!) {
    resolveReviewThread(input: { threadId: $id }) {
      thread { id isResolved }
    }
  }' -f id="$id" 2>&1)

  if echo "$result" | jq -e '.data.resolveReviewThread.thread.isResolved' > /dev/null 2>&1; then
    RESOLVED=$((RESOLVED + 1))
    # Get file path for this thread
    FILE_PATH=$(echo "$THREAD_DATA" | jq -r --arg tid "$id" '
      .data.repository.pullRequest.reviewThreads.nodes[]
      | select(.id == $tid) | .path // "unknown"
    ')
    echo "  Resolved: $FILE_PATH ($id)"
  else
    FAILED=$((FAILED + 1))
    echo "  FAILED: $id"
    echo "    $result" | head -3
  fi
done

echo ""
echo "Done. Resolved: $RESOLVED, Failed: $FAILED"
[ "$FAILED" -eq 0 ] || exit 1
