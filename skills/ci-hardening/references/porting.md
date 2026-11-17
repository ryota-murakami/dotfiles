# Porting Workflow

Follow this order. Keep changes small and reviewable.

## 1. Inventory

Run from target repo root:

```bash
pwd
git status --short --branch
find .github -maxdepth 3 -type f | sort
node /Users/ryotamurakami/.agents/skills/ci-hardening/scripts/audit-ci-hardening.mjs
```

If there is no `.github/`, create it. If CI exists, preserve job names that branch protection may already require.

## 2. Normalize Existing Workflows

For each workflow:

- Add workflow-level `permissions: contents: read`.
- Pin third-party `uses:` refs to full SHAs.
- Add `persist-credentials: false` to checkout unless the job must push, tag, comment, or release.
- Keep write permissions scoped to the exact job that needs them.
- Move secret values into `env:` and reference quoted shell variables in `run:`.
- Avoid writing secret-derived values into artifacts or logs.

## 3. Add Shared Prepare Action

If the repo repeats pnpm/node setup, add or update `.github/actions/prepare/action.yml`.

Prefer:

- repo-pinned Node version from package manager/tooling
- `pnpm install --frozen-lockfile`
- `cache: pnpm`
- pinned `pnpm/action-setup` and `actions/setup-node`

Do not switch package managers.

## 4. Add Security Workflow

Start from `assets/security.yml`, then adjust:

- language list for CodeQL
- package manager audit command
- workflow triggers and paths
- job names if branch protection expects stable names

For non-JS repos, adapt CodeQL language and audit command or explain why omitted.

## 5. Add Scorecard

Start from `assets/scorecard.yml`.

If SARIF upload is unavailable, keep Scorecard but remove SARIF publish only after verifying the repo limitation.

## 6. Add Maintenance Files

Start from:

- `assets/dependabot.yml`
- `assets/CODEOWNERS`
- `assets/pull_request_template.md`
- `assets/SECURITY.md`

Adapt owners, supported versions, package ecosystem, schedules, and security-sensitive paths.

## 7. Validate

Run:

```bash
node /Users/ryotamurakami/.agents/skills/ci-hardening/scripts/audit-ci-hardening.mjs
```

Then run repo-native validation, usually:

```bash
pnpm lint
pnpm test
pnpm typecheck
pnpm build
```

Use existing scripts instead of inventing new ones.

## 8. Report

Summarize:

- files changed
- hardening properties achieved
- validation run and results
- remaining repo/GitHub-side settings that need manual/admin action
