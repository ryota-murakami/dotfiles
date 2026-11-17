# TODOs

Tracked follow-ups for {{PROJECT_NAME}}.

## Repository

### Protect main with a ruleset

**What:** Add a branch ruleset that requires the Test, Build, TypeCheck, Lint and Format checks, a pull request, and blocks force pushes.

**Why:** OpenSSF Scorecard's Branch-Protection and Code-Review checks stay low without it, and a direct push can currently skip CI.

**Effort:** S
**Priority:** P2
**Depends on:** Nothing
