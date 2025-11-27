# =============================================================================
# getpr - Checkout GitHub Pull Request
# =============================================================================
#
# DESCRIPTION:
#   Quickly checkout a GitHub Pull Request by its number.
#   Uses GitHub CLI (gh) to fetch and switch to the PR branch.
#
# USAGE:
#   getpr <pr_number>
#
# ARGUMENTS:
#   pr_number - The PR number to checkout (e.g., 123)
#
# WHAT HAPPENS:
#   1. Fetches the PR branch from GitHub
#   2. Creates a local branch for the PR
#   3. Switches to that branch
#
# DEPENDENCIES:
#   - gh (brew install gh)
#   - Must be authenticated: gh auth login
#
# EXAMPLE:
#   $ getpr 42
#   remote: Enumerating objects: 10, done.
#   ...
#   Switched to branch 'feature/new-component'
#
#   # Now you can review, test, or add commits
#   $ git log --oneline -5
#
# RELATED:
#   - copy_head_commit_hash.fish (copy current commit)
#
# =============================================================================
function getpr
    gh pr checkout $argv
end
