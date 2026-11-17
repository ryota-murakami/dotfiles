# Phase 4: CI

Goal: one commit (`ci: add lint, format, Fallow, security, Socket, Scorecard and Codecov workflows`). Land it after tooling and tests, so the first run is green.

## Files (`scaffold.mjs --group ci`)

| File                                 | Runs                                                                    | Adapt                                                                      |
| ------------------------------------ | ----------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `.github/actions/prepare/action.yml` | pnpm (from `packageManager`), Node from `.node-version`, frozen install | Nothing if `.node-version` exists                                          |
| `workflows/test.yml`                 | `pnpm test:coverage` on ubuntu/windows/macos, Codecov upload (ubuntu)   | OS / Node matrix; upload guard must match exactly one matrix cell          |
| `workflows/build.yml`                | `pnpm build`                                                            | VS Code ext: add `- run: pnpm package`; library: `pnpm check:package` etc. |
| `workflows/typecheck.yml`            | `pnpm typecheck`                                                        | Add `pnpm build` first if types come from build output                     |
| `workflows/lint.yml`                 | `pnpm lint`, `pnpm check:docs`                                          | —                                                                          |
| `workflows/format.yml`               | `pnpm format:check`                                                     | —                                                                          |
| `workflows/fallow.yml`               | matrix health/dupes/dead-code; health runs coverage first               | Keep `fetch-depth: 0` (health reads churn from history)                    |
| `workflows/security.yml`             | CodeQL, dependency review (PR), `pnpm audit --prod --audit-level high`  | CodeQL `languages` if not JS/TS                                            |
| `workflows/socket.yml`               | Socket CLI scan; skips fork PRs                                         | —                                                                          |
| `workflows/scorecard.yml`            | OpenSSF Scorecard → SARIF, publishes results                            | — (public repos only)                                                      |
| `codecov.yml`                        | project `auto` ±1%, patch 80%                                           | —                                                                          |
| `.coderabbit.yaml`                   | assertive review, path instructions                                     | Fill `{{PROJECT_SUMMARY}}`, `{{SOURCE_INVARIANTS}}`; add path rules        |

Requirements in `package.json`: `"packageManager": "pnpm@<ver>+sha512.<hash>"` (pnpm 12 also writes `packageManagerDependencies` into the lockfile; commit it or `--frozen-lockfile` fails). `.node-version` present.

## Conventions (keep them when editing)

- Remote actions pinned to full SHAs with `# vX.Y.Z` comment. No Dependabot → re-pin manually when touching workflows:
  `gh api repos/<owner>/<action>/releases/latest --jq .tag_name` then `gh api repos/<owner>/<action>/commits/<tag> --jq .sha`.
- Top-level `permissions: contents: read`; widen per job only (Scorecard/CodeQL `security-events: write`).
- `persist-credentials: false` on every checkout; `concurrency` with `cancel-in-progress`.
- Cache pnpm store only (setup-node `cache: pnpm`), never `node_modules`.

## No Dependabot

Do not add `.github/dependabot.yml`. If one exists, delete it in its own commit (`ci: remove Dependabot config`). The `ci-hardening` and `github-actions-pnpm-ci` skills ship a Dependabot asset — skip that part when combining them with this skill.

## Secrets

`CODECOV_TOKEN` and `SOCKET_SECURITY_API_TOKEN` are **laststance organization secrets**. Nothing to create per repo. Verify the repo can read them:

```sh
gh api repos/<owner>/<repo>/actions/organization-secrets --jq '.secrets[].name'
```

Missing → the org secret is limited to selected repositories; ask the user to add the repo (needs org admin; the `gh` token has no `admin:org`). Non-laststance owner → ask the user how to provision them.

Fork PRs cannot read secrets: Socket skips them by `if:`; Codecov upload fails with `fail_ci_if_error` — accepted trade-off, documented in TESTING.md.
