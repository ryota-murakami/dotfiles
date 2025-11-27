# =============================================================================
# save_vsc_config - Backup VS Code Settings to Dotfiles
# =============================================================================
#
# DESCRIPTION:
#   Copies VS Code settings and keybindings from the system location
#   to the dotfiles repository for version control backup.
#
# USAGE:
#   save_vsc_config
#
# FILES BACKED UP:
#   - keybindings.json → ~/dotfiles/vscode/keybindings.json
#   - settings.json → ~/dotfiles/vscode/settings.json
#
# SOURCE LOCATION:
#   ~/Library/Application Support/Code/User/
#
# WORKFLOW:
#   1. Make changes to VS Code settings
#   2. Run save_vsc_config to backup
#   3. Commit and push dotfiles
#
# EXAMPLE:
#   $ save_vsc_config
#   # Settings copied to ~/dotfiles/vscode/
#
#   $ cd ~/dotfiles && git diff
#   # See what changed
#
#   $ git up
#   # Commit and push backup
#
# RELATED:
#   - rollback_vsc_config.fish (restore from backup)
#   - save_cursor_config.fish (for Cursor editor)
#
# =============================================================================
function save_vsc_config
    cp ~/Library/Application\ Support/Code/User/keybindings.json ~/dotfiles/vscode
    cp ~/Library/Application\ Support/Code/User/settings.json ~/dotfiles/vscode
end
