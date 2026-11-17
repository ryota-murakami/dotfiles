---
name: coderabbit-resolver
description: |
  CodeRabbit PR loop: audit findings, fix, wait for CI, merge. Pass `cli` to put
  `@coderabbitai ignore` in the PR description (disables the GitHub bot) and
  review with the CodeRabbit CLI instead.
  Use when: resolving CodeRabbit comments, merging a reviewed PR, or reviewing
  via CLI to skip the PR-side bot.
  Keywords: CodeRabbit, PR review, merge, CLI, @coderabbitai ignore, --bulk
argument-hint: "[pr-number|--bulk] [cli]"
---

## Codex Compatibility
When running this skill in Codex, translate Claude Code-only primitives before acting: `AskUserQuestion` -> chat/request_user_input, `TodoWrite` -> `update_plan`, `Task`/`TaskCreate`/`TeamCreate`/`SendMessage` -> `spawn_agent`/`send_input`/`wait_agent` when available and allowed, and `EnterPlanMode`/`ExitPlanMode` -> a concise chat plan plus explicit approval.
Resolve `Read`/`Write`/`Edit`/`Bash`/`WebSearch`/`WebFetch` to Codex file/shell/web tools, and map `~/.claude/...` paths to `~/.agents/...` or `~/.codex/...` unless the task explicitly targets Claude Code.

## Cursor Compatibility
When running this skill in Cursor Agent, translate Claude Code-only primitives before acting: `AskUserQuestion` -> `AskQuestion`; `TodoWrite` -> Cursor `TodoWrite` or an equivalent checklist; `Task`/`TaskCreate`/`TeamCreate`/`SendMessage`/multi-agent flows -> Cursor `Task` (subagents), parallel Tasks, or `run_in_background` when allowed (`TeamCreate`/`SendMessage` may have no exact match); `EnterPlanMode`/`ExitPlanMode` -> Plan mode (`SwitchMode` / `CreatePlan`) plus explicit user approval.
Resolve `Read`/`Write`/`Edit`/`StrReplace`/`Bash`/web/search/MCP via Cursor Composer or Agent equivalents. MCP names written as `mcp__server__tool` typically map to `call_mcp_tool` with configured server identifiers. Map `~/.claude/...` to `~/.cursor/skills/`, `.cursor/skills/`, and `.cursor/rules/` unless the task explicitly targets Claude Code.


<essential_principles>
## How This Skill Works

Automates the iterative CodeRabbit review loop on a GitHub PR until all review comments are resolved and CI is green, then merges and cleans up.

### Principle 1: GraphQL-Only Thread Resolution

GitHub has NO REST API for resolving review threads. You MUST use the GraphQL `resolveReviewThread` mutation with `PRRT_`-prefixed thread IDs. The mutation is idempotent — safe to call on already-resolved threads.

Outside-diff findings live in review bodies and have no resolvable thread ID. Track their disposition and evidence in the audit table; zero unresolved inline threads does not prove these findings are addressed.

### Principle 2: Iterative Loop Until Clean

The workflow runs in a loop:
1. Extract unresolved CodeRabbit inline threads AND all CodeRabbit review bodies, including older outside-diff findings
2. Verify each finding against current code; fix real issues, answer each false positive in its thread with the reason (Principle 8), or record why already fixed/skipped, and resolve applicable inline threads
3. Commit → Push → Wait for CI + CodeRabbit re-review (or, in `cli` mode, CI + CodeRabbit CLI re-review)
4. Re-fetch both sources after every re-review and before merge. Repeat until: zero unresolved threads AND zero unaudited/unaddressed outside-diff findings AND all CI checks pass AND (CodeRabbit reviewed current HEAD OR a CLI review passed the `CR_CLI_LOG` gate)

### Principle 3: Validation Before Every Push

Run `pnpm validate` (or project-specific validation) before every commit. Never push broken code.

### Principle 4: Safe Merge and Cleanup

Only merge when ALL conditions are met: CI green (no check pending, failed or cancelled), no unresolved threads, every outside-diff finding has a current-code disposition with evidence, and CodeRabbit reviewed the current HEAD commit (its check passed and a CodeRabbit review exists on that commit). When no PR-side review covers HEAD, a CodeRabbit CLI review that passes the `CR_CLI_LOG` gate (Principle 5) meets the last condition instead. `check-ci-status.sh` is the gate for CI and review, because a repository may require no checks and GitHub then lets a red PR merge. It does not audit outside-diff findings; its exit 0 cannot replace that audit. Merge only the verified head (`--match-head-commit`). After merge, retarget the PRs stacked on the branch, then delete the remote branch and prune local (review-loop.md Step 9). Never use `gh pr merge --delete-branch`: GitHub closes the stacked PRs instead of retargeting them.

### Principle 5: No Review on HEAD, No Merge — Rate Limits Included

CodeRabbit may hit API rate limits and post a rate-limit warning comment **instead of** running a real review. Critically, the GitHub Checks API still reports `completed/success` for that case — there's no API-only signal to distinguish a real review from a rate-limit response. **Trusting the Checks API alone leads to merging unreviewed PRs.**

Therefore: every "CodeRabbit success" must be cross-validated against the latest CodeRabbit issue comment. If the latest comment matches a rate-limit pattern (e.g. "Rate limit exceeded", "wait X minutes before requesting another review"), the run is rate-limited regardless of API status. A "success" can also cover a push that CodeRabbit never read: the per-SHA status can read "Review completed" after a run that left no review, or "Reviews paused" / "Review skipped", and a later run can overwrite it. Only a CodeRabbit review whose `commit_id` is HEAD shows that HEAD was reviewed.

`check-ci-status.sh` performs these checks internally: the per-SHA status text, the latest comment, and a review on HEAD. It returns **exit 3** when they show that no review covers HEAD. The workflow's Step 6a treats exit 3 as "go to Step 6b," and Step 8 (Final Verification) treats exit 3 as "do not merge." This makes the review gate impossible to skip.

When no review covers HEAD, don't wait out a rate-limit window. Review the PR locally with the CodeRabbit CLI (`scripts/cli-review.sh`, review-loop.md Step 6b), audit its findings like review comments, and pass the merge gate by rerunning `check-ci-status.sh` with `CR_CLI_LOG` (plus `CR_CLI_ACCEPT` for findings dispositioned by hand). The script accepts the log only if it is a completed CLI run with exactly that many findings, on HEAD (or, when findings were accepted, on an ancestor of HEAD whose newer commits fix them).

The CLI has its own limits. Every run counts toward the account's CLI reviews (`coderabbit usage`), and the plan caps CLI reviews per hour. So run it once per HEAD, and at most 3 CLI passes per PR, because passes don't converge on zero findings. Never add `--use-credits` (usage-based billing) unless the owner asks.

Fall back to waiting only when the CLI cannot run: it is not installed, not signed in, or rate limited as well (`cli-review.sh` exit 5 or 6). Then `wait-for-ratelimit.sh` waits for the window to expire (+ 30s buffer) and posts `@coderabbitai full review`. Max 3 such retries per PR to prevent infinite loops.

While the CLI is rate limited (exit 6), create new PRs with `@coderabbitai ignore` in the description, so the bot doesn't hit the limit on them as well. When the CLI can review again, remove the line and review those PRs with the CLI (review-loop.md Step 6b item 6). That temporary ignore is not `cli` mode.

### Principle 6: Long Waits Use ScheduleWakeup, Not sleep

Top-level `sleep` is blocked by Claude Code's Bash policy and burns the 5-minute prompt cache. **Internal `sleep` inside `scripts/*.sh` is fine** — Claude sees the script as a single command. But when YOU (the agent) need to wait between steps without a script wrapper (e.g., letting CodeRabbit post comments after a check completes), use `ScheduleWakeup` with a continuation prompt that re-enters the workflow. Never write `sleep 180; gh api ...` as a top-level Bash command.

### Principle 7: `cli` Mode Disables the GitHub Bot

When the invocation includes `cli` or `--cli`, the GitHub bot must not review this PR. Put `@coderabbitai ignore` on its own line in the **PR description** (`scripts/ensure-cli-ignore.sh`) and keep it there — a comment with the same text does nothing. Review every HEAD with `cli-review.sh` and pass the gate with `CR_CLI_MODE=1` plus `CR_CLI_LOG`. Do not post `@coderabbitai review` / `full review` / `resume`, and do not run `wait-for-ratelimit.sh` (it posts `full review`). If the CLI cannot run, stop and ask the user.

### Principle 8: Explain a False Positive, Then Resolve It

When verification shows an inline finding is a false positive (the code is already correct, the finding's premise is wrong, or it contradicts the repository's documented rules), change no code. Reply in that finding's thread, addressed to `@coderabbitai`, with the reason and its evidence (file and line, the test that covers it, the documented rule, an observed result), then resolve the thread. CodeRabbit reads the reply, may answer with a **Learnings added** section, and applies the learning to the repository's later reviews, so the same false positive stops coming back. Reply on the specific inline comment, never as a general PR comment: a line-level reply gives a learning tied to that file and context. Never resolve a false positive without its reply, and never put `@coderabbitai review` / `full review` in it. An outside-diff false positive has no thread: its reason goes in the audit row (Step 5 says when a PR comment is allowed).
</essential_principles>

<intake>
This skill accepts a PR number, `--bulk`, and an optional `cli` flag. `cli` and `--cli` are the same flag. Usage:

```
/coderabbit-resolver <PR_NUMBER>       # Process single PR (GitHub bot)
/coderabbit-resolver 17                # Process PR #17
/coderabbit-resolver 17 cli            # PR #17 via CodeRabbit CLI; bot ignored
/coderabbit-resolver cli               # Current-branch PR via CodeRabbit CLI
/coderabbit-resolver --bulk            # Process ALL open PRs (oldest first)
/coderabbit-resolver --bulk cli        # All open PRs via CodeRabbit CLI
```

Parse every argument: `cli` / `--cli` sets CLI mode; `--bulk` selects the bulk workflow; the first all-digit token is the PR number. If no PR number (and no `--bulk`), detect from current branch:
```bash
gh pr view --json number -q .number
```

**After obtaining the PR number, read and follow `workflows/review-loop.md`.**
**If `--bulk` is specified, read and follow `workflows/bulk-loop.md`.**
**If `cli` is set, follow that workflow's CLI-mode rules (Principle 7).**
</intake>

<routing>
| Input | Action |
|-------|--------|
| PR number provided | Read `workflows/review-loop.md` and execute with that PR |
| No PR number | Auto-detect from current branch, then read `workflows/review-loop.md` |
| `--bulk` flag | Read `workflows/bulk-loop.md` and process all open PRs |
| `cli` / `--cli` (with any of the above) | Same workflow, CLI mode: `@coderabbitai ignore` + CodeRabbit CLI |

**After reading the workflow, follow it exactly.**
</routing>

<reference_index>
## References

All in `references/`:

| File | Content |
|------|---------|
| github-graphql-api.md | GraphQL queries/mutations for thread resolution, CI status checks |
| coderabbit-commands.md | CodeRabbit bot commands and behavior reference |
</reference_index>

<workflows_index>
## Workflows

All in `workflows/`:

| Workflow | Purpose |
|----------|---------|
| review-loop.md | The main iterative review-fix-resolve-merge loop (single PR) |
| bulk-loop.md | Process all open PRs sequentially (oldest first), merging each |
</workflows_index>

<scripts_index>
## Scripts

| Script | Purpose |
|--------|---------|
| resolve-threads.sh | Resolve all unresolved CodeRabbit threads on a PR |
| check-ci-status.sh | The merge gate: waits for CI and CodeRabbit on the PR head. Any failed, cancelled or pending check blocks (by `gh pr checks` bucket), and so do a PR with no CI besides CodeRabbit and a head with no CodeRabbit review. Accepts a CLI review via `CR_CLI_LOG` when no PR-side review covers HEAD. `CR_CLI_MODE=1` skips the GitHub bot check and requires that log |
| cli-review.sh | Review the PR locally with the CodeRabbit CLI when no PR-side review covers HEAD (rate limited, reviews paused, or `cli` mode); `--verify` checks a saved run for the merge gate |
| ensure-cli-ignore.sh | Put `@coderabbitai ignore` in the PR description so the GitHub bot does not auto-review (`cli` mode). Idempotent |
| wait-for-ratelimit.sh | Fallback when the CLI cannot run: detect the rate limit, wait for expiry, trigger full review. Do not use this in `cli` mode |

`tests/run_tests.py` tests `cli-review.sh`, `check-ci-status.sh` (the `CR_CLI_LOG` / `CR_CLI_MODE` branches, the review layers and the CI verdict), and `ensure-cli-ignore.sh` against a fake `gh` and a fake CLI (`python3 tests/run_tests.py`; no review is spent). Run it after changing those scripts.
</scripts_index>

<success_criteria>
A successful coderabbit-resolver invocation (single PR):
- [ ] All CodeRabbit review threads resolved (zero unresolved)
- [ ] Every false-positive inline finding has a reply in its own thread, addressed to `@coderabbitai`, with the reason and evidence, posted before that thread was resolved
- [ ] All outside-diff review body findings audited against current HEAD: FIXED with evidence or SKIPPED with a reason; none unaudited or NOT_FIXED
- [ ] All CI checks passing (green, none pending, failed or cancelled), including fixes for unrelated CI failures
- [ ] CodeRabbit reviewed HEAD (a review on that commit), or, when no PR-side review covers HEAD, a CLI review of HEAD passed the `CR_CLI_LOG` gate
- [ ] PR merged successfully
- [ ] PRs stacked on the branch retargeted, then the remote branch deleted
- [ ] Local branch cleaned up (switched to main, pruned)

A successful `--bulk` invocation:
- [ ] All open PRs processed (oldest first)
- [ ] Each PR either MERGED or SKIPPED (with reason)
- [ ] Summary report generated with results table

A successful `cli` invocation (single PR or `--bulk cli`) also:
- [ ] PR description contains `@coderabbitai ignore` for the whole run
- [ ] Review evidence is a CodeRabbit CLI log that passed the `CR_CLI_MODE=1` + `CR_CLI_LOG` gate
- [ ] No `@coderabbitai review` / `full review` / `resume` comment was posted
</success_criteria>
