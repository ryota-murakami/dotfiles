# =============================================================================
# volta-dir - Navigate to Volta Installation Directory
# =============================================================================
#
# DESCRIPTION:
#   Changes to the directory where Volta is installed. Useful for
#   inspecting Volta's binaries, cached Node versions, or debugging
#   Volta-related issues.
#
# USAGE:
#   volta-dir
#
# TYPICAL LOCATION:
#   ~/.volta/bin/ (where Volta binaries are located)
#
# WHAT'S IN VOLTA DIRECTORY:
#   ~/.volta/
#   ├── bin/         # Shims for node, npm, yarn, etc.
#   ├── tools/       # Cached tool versions
#   │   ├── node/    # Node.js versions
#   │   ├── npm/     # npm versions
#   │   └── yarn/    # Yarn versions
#   └── tmp/         # Temporary files
#
# DEPENDENCIES:
#   - volta (curl https://get.volta.sh | bash)
#
# EXAMPLE:
#   $ volta-dir
#   $ pwd
#   /Users/me/.volta/bin
#
#   $ ls
#   node  npm  npx  volta  yarn
#
#   # Check installed Node versions:
#   $ ls ~/.volta/tools/node/
#   18.17.0  20.9.0
#
# =============================================================================
function volta-dir
    cd (which volta | awk -F/ 'BEGIN {OFS="/"} {$NF=""; print $0}')
end
