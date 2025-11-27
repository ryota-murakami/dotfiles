# =============================================================================
# rollback_vsc_config - Restore VS Code Settings from Dotfiles
# =============================================================================
#
# DESCRIPTION:
#   Restores VS Code settings and keybindings from the dotfiles backup
#   to the system location. Useful after reinstalling VS Code or on
#   a new machine.
#
# USAGE:
#   rollback_vsc_config
#
# FILES RESTORED:
#   - ~/dotfiles/vscode/keybindings.json → VS Code keybindings
#   - ~/dotfiles/vscode/settings.json → VS Code settings
#
# DESTINATION:
#   ~/Library/Application Support/Code/User/
#
# WHEN TO USE:
#   - Fresh VS Code installation
#   - New machine setup
#   - Accidentally changed settings
#   - Sync settings across machines
#
# NOTE:
#   Uses -f flag to force overwrite existing files.
#   Restart VS Code after running for changes to take effect.
#
# EXAMPLE:
#   # New machine after cloning dotfiles:
#   $ rollback_vsc_config
#   # Restart VS Code - all settings restored!
#
# RELATED:
#   - save_vsc_config.fish (backup settings)
#   - rollback_cursor_config.fish (for Cursor editor)
#
# =============================================================================
function rollback_vsc_config
    cp -f ~/dotfiles/vscode/keybindings.json ~/Library/Application\ Support/Code/User/keybindings.json
    cp -f ~/dotfiles/vscode/settings.json ~/Library/Application\ Support/Code/User/settings.json
end
