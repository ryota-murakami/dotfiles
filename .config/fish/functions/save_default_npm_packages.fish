# =============================================================================
# save_default_npm_packages - Dump global npm packages to dotfiles
# =============================================================================
#
# DESCRIPTION:
#   Writes currently installed global npm package names to
#   ~/dotfiles/.default-npm-packages (one package per line, sorted).
#
# USAGE:
#   save_default_npm_packages
#
# EXAMPLE:
#   $ save_default_npm_packages
#   $ cd ~/dotfiles && git diff .default-npm-packages
#
# RELATED:
#   - npm_global_install.fish (install from the list)
#   - ~/dotfiles/.default-npm-packages
#
# =============================================================================
function save_default_npm_packages
    set --local packages_file "$HOME/dotfiles/.default-npm-packages"
    set --local tmp_file (mktemp)

    npm list -g --depth=0 --parseable 2>/dev/null \
        | string match '*node_modules/*' \
        | string replace -r '.*/node_modules/' '' \
        | sort -u \
        >"$tmp_file"

    if test (count (cat "$tmp_file")) -eq 0
        rm -f "$tmp_file"
        echo "No global npm packages found"
        return 1
    end

    mv "$tmp_file" "$packages_file"
    echo "Saved to $packages_file"
end
