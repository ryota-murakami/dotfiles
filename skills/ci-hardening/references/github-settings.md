# GitHub Settings

Use only when the user asks for full setup or GitHub-side verification.

## Inspect

```bash
gh repo view --json nameWithOwner,defaultBranchRef
gh api repos/OWNER/REPO/actions/permissions/workflow --jq '{default_workflow_permissions, can_approve_pull_request_reviews}'
gh api repos/OWNER/REPO/actions/permissions --jq '{enabled, allowed_actions}'
gh api repos/OWNER/REPO --jq '{default_branch, security_and_analysis}'
gh api repos/OWNER/REPO/branches/main/protection --jq '{required_status_checks, required_pull_request_reviews, enforce_admins}'
```

## Desired State

- Actions enabled.
- Default workflow permissions: `read`.
- Secret scanning: enabled.
- Push protection: enabled.
- Dependabot security updates: enabled.
- Main branch protected.
- Required checks include core CI and security checks.

For the `skills-desktop` reference, required checks were:

- `build`
- `lint`
- `test`
- `typecheck`
- `dead-code`
- `dupes`
- `health`
- `CodeQL`
- `Dependency Review`
- `Production Dependency Audit`

Use target repo job names instead of blindly copying these names.

## Update Examples

Set default workflow permissions to read:

```bash
gh api --method PUT repos/OWNER/REPO/actions/permissions/workflow \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false
```

Enable vulnerability alerts / Dependabot security updates when supported:

```bash
gh api --method PUT repos/OWNER/REPO/vulnerability-alerts
gh api --method PUT repos/OWNER/REPO/automated-security-fixes
```

Always re-run inspect commands after updates.

## Caution

- Branch protection and code scanning APIs can fail on private/free-plan constraints or missing admin permissions.
- Do not remove existing required checks unless the user explicitly asks.
- If a repo uses rulesets instead of classic branch protection, inspect rulesets before changing branch protection.
