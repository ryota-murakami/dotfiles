# GitHub GraphQL API Reference for Thread Resolution

## Query: Get All Review Threads

```bash
OWNER="<owner>"
REPO="<repo>"
PR_NUMBER=<number>

gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 3) {
            nodes {
              body
              author { login }
              databaseId
            }
          }
        }
      }
    }
  }
}' -F owner="$OWNER" -F repo="$REPO" -F pr="$PR_NUMBER"
```

## Filter: Unresolved CodeRabbit Threads Only

```bash
gh api graphql -f query='...' | jq '
  .data.repository.pullRequest.reviewThreads.nodes
  | map(select(.isResolved == false))
  | map(select(.comments.nodes[0].author.login == "coderabbitai" or .comments.nodes[0].author.login == "coderabbitai[bot]"))
'
```

## Mutation: Resolve a Thread

```bash
THREAD_ID="PRRT_kwDOxxxxxxxxx"

gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: { threadId: $threadId }) {
    thread { id isResolved }
  }
}' -f threadId="$THREAD_ID"
```

**Key facts:**
- Thread IDs use `PRRT_` prefix (PullRequestReviewThread node ID)
- GraphQL only — no REST API equivalent exists
- Mutation is idempotent — calling on already-resolved thread is safe (no error)
- Requires write access to the repository

## Mutation: Reply to a Thread

Answers a finding in its own thread, for example a false positive before it is resolved (SKILL.md Principle 8). Write the reply to a file first, so the shell never sees its text:

```bash
THREAD_ID="PRRT_kwDOxxxxxxxxx"
REPLY_FILE=reply.md   # starts with "@coderabbitai", states the reason and the evidence

gh api graphql -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: $threadId, body: $body }) {
    comment { url }
  }
}' -f threadId="$THREAD_ID" -F body=@"$REPLY_FILE"
```

**Key facts:**
- Takes the same `PRRT_` thread ID as `resolveReviewThread`; the REST alternative is `POST /repos/{owner}/{repo}/pulls/{pull_number}/comments/{comment_id}/replies` with the thread's first comment's database ID
- A reply on the line-level comment gives CodeRabbit the file and context for a learning; a general PR comment gives a vaguer one
- Reply first, then resolve: resolving collapses the thread and keeps the reply

## Query: Get Review Bodies (Outside-Diff Comments)

Outside-diff findings are embedded in `PullRequestReview.body`, not resolvable inline threads. The `/issues/{pr}/comments` endpoint used for walkthrough/rate-limit comments does not return these review bodies.

Fetch **all pages** and accept both CodeRabbit login forms. REST responses commonly use `coderabbitai[bot]`; matching only `coderabbitai` silently drops those reviews. Keep the source URL and reviewed commit for the audit:

```bash
gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews?per_page=100" --paginate \
  --jq '.[]
    | select(.user.login == "coderabbitai" or .user.login == "coderabbitai[bot]")
    | {id, html_url, commit_id, submitted_at, state, body}'
```

Read every returned body for outside-diff findings, including collapsed HTML details and repeated AI prompt sections. Do not filter to the latest review, current-HEAD reviews, or a particular review state: older findings remain relevant until checked against current code, even after an approval or a later review with no new comments. Preserve `cr-comment` markers when present to identify duplicate appearances of the same finding.

An API failure is not an empty review history. If no CodeRabbit reviews are returned despite a known review URL or completed review, investigate the repository, pagination, and author filtering before declaring the audit clean.

## Check CI Status

```bash
# All checks including CodeRabbit (check runs and commit statuses alike)
gh pr checks $PR_NUMBER --json name,bucket,state

# Specifically CodeRabbit
gh pr checks $PR_NUMBER --json name,bucket,state \
  --jq '.[] | select(.name | test("coderabbit"; "i"))'
```

Judge each check by `bucket` (`pass`, `fail`, `pending`, `skipping`, `cancel`), never by the exit code: with `--json` it is 0 even when a check failed. gh keeps only the newest run of each check. CodeRabbit may report through a commit status rather than a check run, so the `check-runs` endpoint can miss it. `scripts/check-ci-status.sh` applies these rules.

## Check Merge Requirements

```bash
gh pr view $PR_NUMBER --json mergeable,mergeStateStatus \
  --jq '{mergeable, mergeStateStatus}'
```
