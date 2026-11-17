# Phases 6-8: Gate, confirm, push, repository settings

## 6. Local gate

```sh
pnpm check          # must pass on the final tree
git status --short  # nothing unexpected (coverage/, .fallow/ ignored)
git log --oneline   # chore → test → ci → docs, each passing on its own
```

## 7. Confirm with AskUserQuestion (never skip)

Pushing and changing GitHub settings are visible to others. Ask in one AskUserQuestion call (multiSelect where it fits):

1. Push: `main` directly / feature branch + PR / don't push yet.
2. Repository settings to apply (multiSelect), each with the proposed value:
   - Description (from package.json `description`)
   - Homepage (npm page, Marketplace listing, or docs site)
   - Topics (5-10, lowercase-hyphenated, proposed from the domain)
   - Private vulnerability reporting (SECURITY.md links to it)
   - Delete branch on merge
3. Branch ruleset now, or keep it as the TODOS.md item.

Only run what was approved.

## 8. Push and settings

```sh
gh auth status                         # the active account must be able to push to the target repo
git push origin main                   # or: git push -u origin <branch> && gh pr create

R=<owner>/<repo>
gh repo edit $R --description "<text>" --homepage "<url>" --delete-branch-on-merge
gh repo edit $R --add-topic <t1> --add-topic <t2>
gh api -X PUT repos/$R/private-vulnerability-reporting
gh api repos/$R/private-vulnerability-reporting   # → {"enabled":true}
```

## Watch CI

```sh
gh run list --repo $R --limit 12
gh run watch <run-id> --repo $R --exit-status
```

### Codecov "Repository not found" on a new repo

The first upload for a repository Codecov has not synced yet fails with `Repository not found` (the job fails because of `fail_ci_if_error: true`). Do not change the workflow or token. Wait a minute, then rerun only the failed job:

```sh
gh run rerun <test-run-id> --repo $R --failed
```

The failed attempt makes Codecov sync the repository (on deep-trace-extension it appeared as `activated: true` about two minutes later), so the rerun succeeds and the badge starts rendering. Check with `curl -s https://api.codecov.io/api/v2/github/<owner>/repos/<repo>/`.

### Other first-run failures

- Socket fails with the `Set SOCKET_SECURITY_API_TOKEN` message → org secret not visible to this repo (see ci.md "Secrets").
- Scorecard needs a public repo; on private repos drop the workflow and its badge.
- Fallow health fails only in CI → forgot `fetch-depth: 0` or coverage step; compare with the template.

Report to the user: commit list, green run links, settings applied, remaining TODOS.md items.
