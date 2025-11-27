# =============================================================================
# 20-aliases.fish - Shell Aliases
# =============================================================================
#
# DESCRIPTION:
#   Short command aliases for frequently used operations. Aliases are simple
#   command substitutions (for complex logic, use functions in functions/).
#
# USAGE:
#   Just type the alias name. To see what an alias does:
#     type <alias_name>
#     # Example: type e → "e is an alias for eza --all --long..."
#
# EXAMPLES:
#   c              # Clear terminal
#   e              # List files with details (eza)
#   dotfiles       # cd to ~/dotfiles
#   wanip          # Show public IP address
#
# =============================================================================

# -----------------------------------------------------------------------------
# Editor
# -----------------------------------------------------------------------------
# Use system vim instead of any custom vim (ensures consistent behavior)
alias vi="/usr/bin/vim"

# -----------------------------------------------------------------------------
# Terminal Utilities
# -----------------------------------------------------------------------------
# c: Clear screen (muscle memory from years of usage)
alias c="clear"

# e: Enhanced ls with eza (shows git status, icons, and file details)
# Flags: --all (show hidden), --long (detailed), --header (column headers),
#        --git (git status), --icons (file type icons), --color (always color)
alias e="eza --all --long --header --git --icons --color=always"

# lf: Line feed - double-space text output for readability
# Usage: cat file.txt | lf
alias lf="perl -pe 's/\n/\n\n/g'"

# -----------------------------------------------------------------------------
# Browser Shortcuts
# -----------------------------------------------------------------------------
# chrome: Open Chrome in guest mode (no extensions, clean profile)
# Useful for testing or avoiding extension interference
alias chrome="/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --guest"

# wanip: Show your public IP address (useful for VPN verification)
alias wanip="curl https://ipinfo.io/ip"

# v8: Open Chromium with DevTools for V8/JavaScript debugging
# Flags: auto-open-devtools, incognito mode, disable XSS warnings
alias v8="/Applications/Chromium.app/Contents/MacOS/Chromium --auto-open-devtools-for-tabs --incognito --unsafely-disable-devtools-self-xss-warnings"

# -----------------------------------------------------------------------------
# Directory Navigation
# -----------------------------------------------------------------------------
# Quick jumps to frequently used project directories
# Usage: Just type the alias to cd to that directory

alias dotfiles="cd ~/dotfiles"       # This dotfiles repository
alias nsx="cd ~/nsx"                 # NSX project
alias last="cd ~/laststance"         # Laststance organization projects
alias io="cd ~/laststance/laststance.io"  # Laststance.io website
alias claudia="cd ~/.claude"         # Claude Code configuration
alias corelive="cd ~/corelive"       # CoreLive project

# yalclist: Navigate to yalc packages directory and list contents
# yalc is a local package publishing tool for testing npm packages
alias yalclist="mkdir -p (yalc dir)/packages; cd (yalc dir)/packages; and e"
