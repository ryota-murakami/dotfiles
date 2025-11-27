# =============================================================================
# show_claude_md - Remove CLAUDE.md from Global Gitignore
# =============================================================================
#
# DESCRIPTION:
#   Removes "CLAUDE.md" from the global gitignore file, making CLAUDE.md
#   files visible to git again. Use when you want to commit CLAUDE.md
#   files to repositories.
#
# USAGE:
#   show_claude_md
#
# WHAT IT DOES:
#   1. Filters out "CLAUDE.md" from ~/.gitignore_global
#   2. Writes the filtered content to a temp file
#   3. Replaces the original with the filtered version
#
# EXAMPLE:
#   $ show_claude_md
#   Removed CLAUDE.md from .gitignore_global
#
#   # Now CLAUDE.md will appear in git status
#   $ cd ~/my-project
#   $ touch CLAUDE.md
#   $ git status
#   Untracked files:
#     CLAUDE.md
#
# RELATED:
#   - hide_claude_md.fish (add to gitignore)
#
# =============================================================================
function show_claude_md
    grep -v "CLAUDE.md" ~/.gitignore_global > ~/.gitignore_global.tmp
    mv ~/.gitignore_global.tmp ~/.gitignore_global
    echo "Removed CLAUDE.md from .gitignore_global"
end
