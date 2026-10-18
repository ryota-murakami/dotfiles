# =============================================================================
# install_extend_keybinds - Install local.extend-keybinds into editors
# =============================================================================
#
# DESCRIPTION:
#   Packages ~/dotfiles/local.extend-keybinds and installs the VSIX into
#   VS Code, Cursor, and Devin Desktop. Extra keybind commands live in that
#   extension so they work in every workspace.
#
# USAGE:
#   install_extend_keybinds
#
# EDITORS:
#   - code           → ~/.vscode/extensions
#   - cursor         → ~/.cursor/extensions
#   - devin-desktop  → ~/.devin/extensions
#     (`devin` is the agent CLI and cannot install editor extensions)
#
# NOTE:
#   Reload each editor window after install. A missing CLI is skipped.
#
# EXAMPLE:
#   $ install_extend_keybinds
#   # Extension installed into code, cursor, and devin-desktop
#
# RELATED:
#   - ~/dotfiles/local.extend-keybinds
#
# =============================================================================
function install_extend_keybinds
    set --local extension_dir "$HOME/dotfiles/local.extend-keybinds"

    if not test -d "$extension_dir"
        echo "Missing $extension_dir"
        return 1
    end

    pushd "$extension_dir"
    npx --yes @vscode/vsce package --allow-missing-repository
    set --local package_status $status
    popd

    if test $package_status -ne 0
        echo "Failed to package local.extend-keybinds"
        return 1
    end

    set --local vsix_files $extension_dir/*.vsix

    if not test -f "$vsix_files[1]"
        echo "VSIX was not created"
        return 1
    end

    for editor in code cursor devin-desktop
        if not command -q $editor
            echo "Skip $editor: command not found"
            continue
        end

        $editor --install-extension "$vsix_files[1]" --force
    end

    rm -f $extension_dir/*.vsix
end
