# =============================================================================
# 30-tools.fish - Tool Initializations
# =============================================================================
#
# DESCRIPTION:
#   Initialize tools that need to run on every shell startup. These are
#   tools that modify shell behavior or require environment setup.
#
#   Note: For tools that are slow to initialize, use 40-lazy.fish instead
#   to defer loading until the tool is actually used.
#
# USAGE:
#   Auto-loaded by fish shell on startup. No manual action required.
#
# TOOLS INITIALIZED:
#   - zoxide: Smarter cd command that learns your habits
#   - Chrome headless fix: Workaround for macOS 26 performance bug
#
# EXAMPLES:
#   # zoxide usage (replaces cd):
#   z dotfiles     # Jump to ~/dotfiles (learned from history)
#   z nsx          # Jump to ~/nsx
#   zi             # Interactive selection with fzf
#
#   # Check zoxide database:
#   zoxide query --list
#
# =============================================================================

# -----------------------------------------------------------------------------
# zoxide - Smarter cd Command
# -----------------------------------------------------------------------------
# zoxide tracks your most-used directories and lets you jump to them
# with partial names. It learns from your cd usage over time.
#
# Commands added:
#   z <query>   - Jump to best match (e.g., 'z dot' → ~/dotfiles)
#   zi <query>  - Interactive selection with fzf
#   za <path>   - Add a directory to the database
#   zr <path>   - Remove a directory from the database
#
# Install: brew install zoxide
zoxide init fish | source

# -----------------------------------------------------------------------------
# macOS 26 Chrome Headless Fix
# -----------------------------------------------------------------------------
# Workaround for a known macOS 26 bug that causes performance issues
# when Chrome runs in headless mode. Setting CHROME_HEADLESS=1 via
# launchctl ensures the fix applies system-wide.
#
# Reference: https://www.reddit.com/r/MacOS/comments/1no872w/
launchctl setenv CHROME_HEADLESS 1
