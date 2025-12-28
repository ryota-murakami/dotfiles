# =============================================================================
# 00-env.fish - Environment Variables
# =============================================================================
#
# DESCRIPTION:
#   Sets global environment variables for terminal tools, development
#   environments, and SDKs. These variables are used by other conf.d files
#   and external tools.
#
# USAGE:
#   Auto-loaded by fish shell on startup (conf.d/*.fish are sourced
#   alphabetically). No manual action required.
#
# DEPENDENCIES:
#   - fd (for FZF commands)
#   - eza (for EZA_COLORS)
#   - Java 17 (optional, for Android development)
#
# EXAMPLES:
#   # Check environment variable values:
#   echo $ANDROID_HOME   # → /Users/username/Library/Android/sdk
#   echo $FZF_DEFAULT_COMMAND  # → fd --hidden --strip-cwd-prefix --exclude .git
#
# =============================================================================

# -----------------------------------------------------------------------------
# Terminal Colors
# -----------------------------------------------------------------------------
# LSCOLORS: BSD ls command color scheme (macOS)
# EZA_COLORS: Modern ls replacement (eza) - green directories
# LESS: Enable raw control characters for colored output
set -gx LSCOLORS "CxGxBxDxCxEgEdxbxgxcxd"
set -gx EZA_COLORS "di=1;32"
set -x LESS "-R"

# -----------------------------------------------------------------------------
# Git Prompt
# -----------------------------------------------------------------------------
# Truncate long branch names in fish prompt (max 30 chars)
set -g __fish_git_prompt_shorten_branch_len 30

# -----------------------------------------------------------------------------
# FZF (Fuzzy Finder) Configuration
# -----------------------------------------------------------------------------
# Use fd instead of default find for better performance and .gitignore respect
# FZF_DEFAULT_COMMAND: Default file search
# FZF_CTRL_T_COMMAND: Ctrl+T file search
# FZF_ALT_C_COMMAND: Alt+C directory search
set -gx FZF_DEFAULT_COMMAND "fd --hidden --strip-cwd-prefix --exclude .git"
set -gx FZF_CTRL_T_COMMAND "$FZF_DEFAULT_COMMAND"
set -gx FZF_ALT_C_COMMAND "fd --type=d --hidden --strip-cwd-prefix --exclude .git"

# -----------------------------------------------------------------------------
# JavaScript Development Tools
# -----------------------------------------------------------------------------
# pnpm: Fast, disk space efficient package manager
set -gx PNPM_HOME "$HOME/Library/pnpm"

# bun: Fast all-in-one JavaScript runtime
set --export BUN_INSTALL "$HOME/.bun"

# -----------------------------------------------------------------------------
# Java Development
# -----------------------------------------------------------------------------
# Auto-detect Java 17 installation on macOS (required for Android development)
if test -x /usr/libexec/java_home
    set -l _java17 ( /usr/libexec/java_home -v17 2>/dev/null )
    if test -n "$_java17"
        set -x JAVA_HOME "$_java17"
    end
end

# -----------------------------------------------------------------------------
# Android Development
# -----------------------------------------------------------------------------
# Android SDK location (installed via Android Studio)
set -x ANDROID_HOME $HOME/Library/Android/sdk
