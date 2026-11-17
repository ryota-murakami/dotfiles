# skills-desktop CI Hardening Blueprint

Use this as the target posture, then adapt to the target repo.

## Reference Repo

`/Users/ryotamurakami/laststance/skills-desktop` is the model repo.

Important files:

- `.github/workflows/security.yml`
- `.github/workflows/scorecard.yml`
- `.github/workflows/build.yml`
- `.github/workflows/test.yml`
- `.github/actions/prepare/action.yml`
- `.github/dependabot.yml`
- `.github/CODEOWNERS`
- `.github/pull_request_template.md`
- `SECURITY.md`

## Workflow Defaults

- Add `permissions: contents: read` to every workflow.
- Add narrower job overrides only when required.
- Avoid `permissions: write-all`.
- Avoid broad write scopes in PR-triggered workflows.
- Prefer `pull_request`, not `pull_request_target`.
- If `pull_request_target` already exists, inspect with `gha-security-review`.

## Action Supply Chain

- Pin third-party actions to full 40-char SHAs.
- Keep version comments, for example `# v7.0.0`.
- Local actions like `./.github/actions/prepare` are fine.
- Configure Dependabot for `github-actions` so pins stay current.
- In non-writing jobs, set checkout:

```yaml
with:
  persist-credentials: false
```

## Security Workflow

Include:

- CodeQL for JavaScript/TypeScript when applicable.
- Dependency Review on `pull_request`.
- Production dependency audit, usually `pnpm audit --prod --audit-level high`.

Use job-level permissions:

- CodeQL: `actions: read`, `contents: read`, `security-events: write`.
- Dependency Review: `contents: read`, `pull-requests: read`.
- Audit: inherit `contents: read`.

## Scorecard Workflow

Use OpenSSF Scorecard on `push`, `schedule`, `workflow_dispatch`, and optionally `branch_protection_rule`.

Permissions:

- `actions: read`
- `contents: read`
- `id-token: write`
- `security-events: write`

Publish SARIF when the repo supports code scanning.

## Repo Hygiene Files

- `dependabot.yml`: npm + github-actions, weekly schedule, grouped dependency PRs when useful.
- `CODEOWNERS`: cover `.github/`, package manifests, lockfiles, scripts, release artifacts/config.
- PR template: add a security checklist for workflow/dependency/release changes.
- `SECURITY.md`: report path, supported versions, scope, response targets, posture summary.

## Acceptance Bar

The target repo should pass:

- Audit script reports zero unpinned third-party actions.
- Audit script reports all workflows have explicit permissions.
- Audit script reports checkout persistence disabled in read-only jobs.
- Security workflow exists and has CodeQL/Dependency Review/audit where relevant.
- Dependabot and security policy files exist.
- GitHub settings are verified when the user asked for full setup.
