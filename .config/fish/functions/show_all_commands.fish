# =============================================================================
# show_all_commands - List All Available Commands in PATH
# =============================================================================
#
# DESCRIPTION:
#   Lists all executable commands available in your PATH, showing
#   which directory each command comes from. Useful for understanding
#   what tools are available and where they're installed.
#
# USAGE:
#   show_all_commands
#
# OUTPUT:
#   For each directory in PATH (except pnpm):
#   - Directory path
#   - Tree listing of executables
#   - Blank line separator
#
# WHY EXCLUDE PNPM:
#   The pnpm directory contains thousands of symlinks that would
#   overwhelm the output. Skip it for cleaner results.
#
# DEPENDENCIES:
#   - tree (brew install tree)
#
# EXAMPLE:
#   $ show_all_commands
#   /opt/homebrew/bin
#   /opt/homebrew/bin/brew
#   /opt/homebrew/bin/git
#   /opt/homebrew/bin/node
#   ...
#
#   /Users/me/.cargo/bin
#   /Users/me/.cargo/bin/cargo
#   /Users/me/.cargo/bin/rustc
#   ...
#
# TIP:
#   Pipe to grep to find specific commands:
#   show_all_commands | grep python
#
# =============================================================================
function show_all_commands
    for dir in (echo $PATH | string split " ")
        if test $dir != "$HOME/Library/pnpm"
            echo $dir
            tree -fiC --noreport $dir | grep -v '/$'
            echo ""
        end
    end
end
