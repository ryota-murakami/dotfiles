# =============================================================================
# ssdinfo - Show Disk Usage Summary
# =============================================================================
#
# DESCRIPTION:
#   Displays disk usage of items in the current directory, sorted by size
#   (largest first). Quick way to find what's consuming disk space.
#
# USAGE:
#   ssdinfo
#
# NOTE:
#   Requires sudo for accurate sizes of protected directories.
#   Uses GNU sort (gsort) for human-readable size sorting.
#
# DEPENDENCIES:
#   - du (pre-installed on macOS)
#   - gsort (brew install coreutils)
#
# EXAMPLE:
#   $ cd ~/
#   $ ssdinfo
#   Password: ****
#   4.2G    Library
#   2.1G    Documents
#   1.5G    Downloads
#   ...
#
# RELATED:
#   - storage_usage.fish (for specific directory with depth)
#
# =============================================================================
function ssdinfo
    sudo du -hs * | gsort -hr
end
