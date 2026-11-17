---
name: ci-hardening
description: Port the skills-desktop GitHub Actions hardening setup to another repo. Use when asked to harden CI, secure GitHub Actions, add CodeQL, Dependency Review, Scorecard, Dependabot, CODEOWNERS, pinned actions, least-privilege permissions, or branch/security settings.
---

# CI Hardening

Replicate the `laststance/skills-desktop` CI security baseline in a target repo.
This is an implementation skill, not a vulnerability review. For exploit-focused review only, use `gha-security-review`.

## When To Use

- User asks to strengthen GitHub Actions or `.github/`.
- User asks for a secure CI baseline based on `skills-desktop`.
- User wants CodeQL, Dependency Review, OpenSSF Scorecard, Dependabot, CODEOWNERS, PR template, or GitHub security settings.
- User wants a repo compared against the `skills-desktop` hardening pattern.

## Workflow

1. Inspect repo state first:
   - `pwd`
   - `git status --short --branch`
   - `find .github -maxdepth 3 -type f | sort`
   - `rg -n "permissions:|uses:|pull_request_target|issue_comment|workflow_run|secrets\\.|persist-credentials" .github`
2. Run the bundled audit:
   - `node ~/.agents/skills/ci-hardening/scripts/audit-ci-hardening.mjs`
   - (Claude Code: `~/.claude/skills/...`, Cursor: `~/.cursor/skills/...` or `.cursor/skills/...` via symlink)
3. Read `references/blueprint.md` before designing changes.
4. Read `references/porting.md` before editing files.
5. Prefer existing repo patterns and package manager. Do not replace working CI unrelated to security.
6. Edit only the target repo. Preserve user diffs.
7. Re-run the bundled audit and repo validation after changes.
8. If asked to change GitHub-side settings, use `gh api` / `gh` and verify the result.

## Baseline

Target these properties unless repo constraints require otherwise:

- Workflow-level `permissions: contents: read`.
- Job-level write permissions only where needed.
- No `pull_request_target` unless there is a reviewed reason and no fork code checkout.
- All third-party actions pinned to full commit SHA with version comments.
- `actions/checkout` uses `persist-credentials: false` in non-writing jobs.
- Security workflow includes CodeQL, Dependency Review, and production dependency audit.
- Scorecard workflow publishes SARIF where supported.
- Dependabot updates both npm and GitHub Actions.
- CODEOWNERS covers `.github/`, release, dependency, script, and security-sensitive surfaces.
- PR template includes security checklist.
- GitHub repo settings enable read-only workflow permissions, secret scanning, push protection, branch protection, and required security checks when available.

## References

- `references/blueprint.md` - skills-desktop reference baseline and target checks.
- `references/porting.md` - file-by-file implementation workflow.
- `references/github-settings.md` - GitHub-side settings and verification commands.
- `assets/` - starter templates to adapt, not blindly overwrite.
