# Workflow: Bulk PR Processing

<required_reading>
**Read these before proceeding:**
1. workflows/review-loop.md (the single-PR workflow this builds upon)
2. references/github-graphql-api.md
3. references/coderabbit-commands.md
</required_reading>

<process>

## Step 0: List All Open PRs

Fetch all open PRs sorted by creation date (oldest first):

```bash
REMOTE_URL=$(git remote get-url origin)
OWNER=$(echo "$REMOTE_URL" | sed -n 's/.*github.com[:/]\([^/]*\)\/.*/\1/p')
REPO=$(echo "$REMOTE_URL" | sed -n 's/.*github.com[:/][^/]*\/\([^.]*\).*/\1/p')

gh pr list --state open --json number,title,createdAt \
  --jq 'sort_by(.createdAt) | .[] | "\(.number)\t\(.title)\t\(.createdAt)"'
```

If no open PRs exist, report to user and exit.

Store the PR list. Initialize the results tracker:
```
RESULTS=()  # Array of "PR_NUMBER|TITLE|RESULT|REASON"
```

If the skill was invoked with `cli` or `--cli`, set `CLI_MODE=1` and run every PR through review-loop.md's CLI-mode rules (`@coderabbitai ignore` + CodeRabbit CLI). Record those merges as `MERGED (CLI review)`.

## Step 1: Process Each PR (Oldest First)

For each PR in the sorted list:

### 1a. Checkout PR Branch

```bash
# Always return to main before switching to next PR
git checkout main
git pull origin main

# Checkout the PR branch
gh pr checkout $PR_NUMBER
```

### 1b. Execute review-loop.md

Run the **full** `review-loop.md` workflow for this PR (CLI mode if `CLI_MODE=1`). This includes:
- Extracting and fixing CodeRabbit review comments
- Running validation
- Committing and pushing fixes
- Resolving threads
- **Fixing CI failures** (Step 6c — even if unrelated to PR)
- Waiting for CI + re-review
- Merging on success

### 1c. Record Result

After `review-loop.md` completes for this PR:

- **Success (merged):** Record as `MERGED`
- **Failure (CI fix attempts exhausted):** Record as `SKIPPED` with reason
  - Return to main: `git checkout main && git pull origin main`
  - Move to next PR

**IMPORTANT:** Do not stop the bulk loop on a single PR failure. Skip and continue.

## Step 2: Summary Report

After all PRs have been processed, generate and display the results:

```
## Bulk Processing Complete

| PR | Title | Result | Notes |
|----|-------|--------|-------|
| #12 | Add auth middleware | MERGED | |
| #15 | Fix date parsing | MERGED | |
| #18 | Update deps | SKIPPED | CI failure after 3 attempts (test-e2e) |

**Total: 2 merged, 1 skipped**
```

Report to user with the full summary table.

</process>

<error_handling>

### PR Checkout Failure
If `gh pr checkout` fails (merge conflicts, deleted branch, etc.):
- Record as `SKIPPED` with reason
- Continue to next PR

### CI Fix Limit
Max CI fix attempts per PR: **3** (inherited from review-loop.md Step 6c).
After 3 failed attempts, skip the PR.

### CodeRabbit Rate Limit or No Review on HEAD
If `check-ci-status.sh` exits 3 because CodeRabbit was rate limited or left no review on HEAD:
- Follow review-loop.md Step 6b: review the PR with the CodeRabbit CLI (`cli-review.sh`) and pass the gate with `CR_CLI_LOG`. Record the PR as `MERGED (CLI review)`.
- The PR-side limit counts per developer across all repositories, so the next PRs are likely to be rate limited too. Expect the CLI path for them until the window resets. Run CLI reviews one at a time, since they count toward the CLI's own hourly limit.
- Use `wait-for-ratelimit.sh` only when the CLI cannot run (`cli-review.sh` exit 5 or 6) **and this is not CLI mode**. It waits and triggers `@coderabbitai full review`. Max 3 wait retries per PR; after that, record the PR as `SKIPPED (CodeRabbit rate limit)`.
- **CLI mode:** never run `wait-for-ratelimit.sh`. Exit 5 → `SKIPPED (CodeRabbit CLI not available)`. Exit 6 after 3 waits → `SKIPPED (CodeRabbit CLI rate limit)`.

### Stacked PRs
review-loop.md Step 9 retargets every open PR based on the merged branch to that PR's base, and closes and reopens it so its CI runs. The list from Step 0 is a snapshot, so before processing each PR, read its current base and state (`gh pr view $PR_NUMBER --json baseRefName,state`):
- A PR whose base is still another open PR's branch would merge into that branch. Process the parent first; oldest first usually does this.
- CodeRabbit may skip PRs whose base is not the default branch, so a stacked PR often gets its first review only after the retarget. Wait for that review (review-loop.md Step 6a) instead of reusing an earlier result.

### Network/API Errors
If GitHub API is unreachable or rate-limited:
- Wait 60 seconds, retry once
- If still failing, pause and report to user

### Merge Conflicts After Previous PR Merge
After merging PR N, PR N+1 may now have conflicts:
- Attempt `git merge main` on the PR branch to incorporate changes
- If conflicts are auto-resolvable, resolve and push
- If manual resolution needed, record as `SKIPPED (merge conflict)`

</error_handling>

<success_criteria>
This workflow is complete when:
- [ ] All open PRs have been processed (attempted)
- [ ] Each PR is either MERGED or SKIPPED with documented reason
- [ ] Summary report displayed to user
- [ ] Working directory is clean on main branch
</success_criteria>
