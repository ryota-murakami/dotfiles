# =============================================================================
# hide_claude_md - Add CLAUDE.md to Global Gitignore
# =============================================================================
#
# DESCRIPTION:
#   Adds "CLAUDE.md" to the global gitignore file, making it invisible
#   to git across all repositories. Useful when you want to keep
#   CLAUDE.md files for AI assistants but not commit them.
#
# USAGE:
#   hide_claude_md
#
# WHAT IT DOES:
#   1. Checks if CLAUDE.md is already in ~/.gitignore_global
#   2. If not, ensures file ends with newline
#   3. Appends "CLAUDE.md" to the file
#
# GLOBAL GITIGNORE:
#   Uses ~/.gitignore_global (configured in .gitconfig with:
#   [core] excludesfile = ~/.gitignore_global)
#
# EXAMPLE:
#   $ hide_claude_md
#   Added CLAUDE.md to .gitignore_global
#
#   # Or if already hidden:
#   $ hide_claude_md
#   CLAUDE.md already exists in .gitignore_global
#
#   # Now CLAUDE.md won't show in git status anywhere
#   $ cd ~/any-project
#   $ touch CLAUDE.md
#   $ git status  # CLAUDE.md not listed
#
# RELATED:
#   - show_claude_md.fish (remove from gitignore)
#
# =============================================================================
function hide_claude_md
    if not grep -q "CLAUDE.md" ~/.gitignore_global
        # Check if the file ends with a newline
        if test (tail -c 1 ~/.gitignore_global | wc -l) -eq 0
            # File does not end with newline, add an extra one
            echo "" >> ~/.gitignore_global
        end
        # Now add CLAUDE.md
        echo "CLAUDE.md" >> ~/.gitignore_global
        echo "Added CLAUDE.md to .gitignore_global"
    else
        echo "CLAUDE.md already exists in .gitignore_global"
    end
end
