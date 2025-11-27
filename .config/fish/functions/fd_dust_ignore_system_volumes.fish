# =============================================================================
# fd_dust_ignore_system_volumes - Find Files Ignoring System Volumes
# =============================================================================
#
# DESCRIPTION:
#   Searches for files system-wide while filtering out macOS system
#   volume duplicates. On macOS, /System/Volumes/Data mirrors user
#   data, causing duplicate results. This function filters those out.
#
# USAGE:
#   fd_dust_ignore_system_volumes <filename>
#
# ARGUMENTS:
#   filename - Name or pattern to search for
#
# WHY THIS EXISTS:
#   macOS has a "firmlink" at /System/Volumes/Data that mirrors the
#   root filesystem. Without filtering, fd searches would return
#   duplicates like:
#     /Users/me/file.txt
#     /System/Volumes/Data/Users/me/file.txt
#
# DEPENDENCIES:
#   - fd (brew install fd)
#   - sudo (for searching system directories)
#
# EXAMPLE:
#   $ fd_dust_ignore_system_volumes "settings.json"
#   /Users/me/.config/Code/User/settings.json
#   /Users/me/dotfiles/vscode/settings.json
#
#   # Without filter, would also show:
#   # /System/Volumes/Data/Users/me/.config/Code/User/settings.json
#   # (duplicate)
#
# =============================================================================
function fd_dust_ignore_system_volumes
    set name $argv[1]
    sudo fd $name / | grep -v '^/System/Volumes/Data' | while read -l line
        echo $line
    end
end
