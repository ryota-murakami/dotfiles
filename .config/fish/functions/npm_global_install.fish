# =============================================================================
# npm_global_install - Install global npm packages from dotfiles list
# =============================================================================
#
# DESCRIPTION:
#   Reads package names from ~/dotfiles/.default-npm-packages and runs
#   npm install -g for each entry in the shared default package list.
#
# USAGE:
#   npm_global_install
#
# RELATED:
#   - save_default_npm_packages.fish (dump current globals to the list)
#   - ~/dotfiles/.default-npm-packages
#
# =============================================================================
function npm_global_install
    set --local packages_file "$HOME/dotfiles/.default-npm-packages"

    if not test -f "$packages_file"
        echo "Missing $packages_file"
        return 1
    end

    set --local packages
    while read -l line
        set line (string trim "$line")
        # Skip blank lines and comments.
        if test -z "$line"
            continue
        end
        if string match -q '#*' -- "$line"
            continue
        end
        set packages $packages "$line"
    end <$packages_file

    if test (count $packages) -eq 0
        echo "No packages listed in $packages_file"
        return 1
    end

    npm install -g $packages
end
