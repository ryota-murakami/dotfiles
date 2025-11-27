# =============================================================================
# fd - Enhanced File Finder (Wrapper)
# =============================================================================
#
# DESCRIPTION:
#   Wrapper around the 'fd' command that automatically excludes
#   /System/ directory. Prevents searching through macOS system
#   files which are rarely needed and slow down searches.
#
# USAGE:
#   fd <pattern>           # Find files matching pattern
#   fd <pattern> <path>    # Find in specific path
#   fd -t d <pattern>      # Find directories only
#   fd -e js <pattern>     # Find files with .js extension
#
# WHY THIS WRAPPER:
#   macOS has extensive system directories that clutter search results.
#   This wrapper keeps searches focused on user files.
#
# DEPENDENCIES:
#   - fd (brew install fd)
#
# EXAMPLE:
#   $ fd config
#   .config/fish/config.fish
#   .gitconfig
#   package.json
#
#   # Without wrapper, would also show:
#   # /System/Library/.../config.plist (etc.)
#
# =============================================================================
function fd
    command fd $argv --exclude /System/
end
