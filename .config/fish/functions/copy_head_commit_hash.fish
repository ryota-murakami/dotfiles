# =============================================================================
# copy_head_commit_hash - Copy Current Commit Hash to Clipboard
# =============================================================================
#
# DESCRIPTION:
#   Copies the short hash of the current HEAD commit to the clipboard.
#   Useful for referencing commits in PRs, issues, or documentation.
#
# USAGE:
#   copy_head_commit_hash
#
# OUTPUT:
#   Short commit hash (7 characters) copied to clipboard
#
# DEPENDENCIES:
#   - git (pre-installed on macOS via Xcode CLT)
#   - pbcopy (pre-installed on macOS)
#
# EXAMPLE:
#   $ git log --oneline -1
#   abc1234 Fix authentication bug
#
#   $ copy_head_commit_hash
#   # "abc1234" is now in clipboard
#
#   # Paste in PR description:
#   # "This fixes the issue introduced in abc1234"
#
# RELATED:
#   - getpr.fish (checkout GitHub PRs)
#
# =============================================================================
function copy_head_commit_hash
    git rev-parse --short HEAD | pbcopy
end
