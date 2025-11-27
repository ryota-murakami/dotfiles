# =============================================================================
# storage_usage - Analyze Directory Storage Usage
# =============================================================================
#
# DESCRIPTION:
#   Analyzes disk usage for a specified directory up to 3 levels deep.
#   Shows the top 20 largest items, sorted by size. Useful for finding
#   what's consuming disk space in large directories.
#
# USAGE:
#   storage_usage <directory>
#
# ARGUMENTS:
#   directory - Path to analyze (required)
#
# OUTPUT:
#   Top 20 largest items within the directory, showing:
#   - Human-readable sizes (GB, MB, KB)
#   - Sorted largest to smallest
#   - Up to 3 directory levels deep
#
# DEPENDENCIES:
#   - du (pre-installed on macOS)
#   - sort, head (pre-installed on macOS)
#   - sudo (for accessing protected directories)
#
# EXAMPLE:
#   $ storage_usage ~/Library
#   Password: ****
#   15G     /Users/me/Library
#   4.2G    /Users/me/Library/Caches
#   3.1G    /Users/me/Library/Application Support
#   2.0G    /Users/me/Library/Application Support/Code
#   ...
#
# RELATED:
#   - ssdinfo.fish (current directory, simpler)
#
# =============================================================================
function storage_usage
    if not test -n $argv[1]
        echo 'Expected delectory path as first argument.'
        return 1
    else
        sudo du -hd3 $argv[1] 2>&1 | sort -hr | head -n 20
    end
end
