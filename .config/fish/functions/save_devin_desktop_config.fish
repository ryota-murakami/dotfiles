# =============================================================================
# save_devin_desktop_config - Backup Devin Desktop Editor Settings to Dotfiles
# =============================================================================
#
# DESCRIPTION:
#   Copies Devin Desktop editor settings, keybindings, and snippets from the
#   system location to the dotfiles repository for version control backup.
#   Devin Desktop (formerly Windsurf) is an AI-powered code editor based on VS Code.
#
# USAGE:
#   save_devin_desktop_config
#
# FILES BACKED UP:
#   - keybindings.json → ~/dotfiles/devin-desktop/keybindings.json
#   - settings.json → ~/dotfiles/devin-desktop/settings.json
#   - snippets/ → ~/dotfiles/devin-desktop/snippets/ (entire directory)
#
# SOURCE LOCATION:
#   ~/Library/Application Support/Devin/User/
#
# EXAMPLE:
#   $ save_devin_desktop_config
#   # Settings copied to ~/dotfiles/devin-desktop/
#
#   $ cd ~/dotfiles && git status
#   # See backed up files
#
# RELATED:
#   - rollback_devin_desktop_config.fish (restore from backup)
#   - save_cursor_config.fish (for Cursor)
#
# =============================================================================
function save_devin_desktop_config
    cp ~/Library/Application\ Support/Devin/User/keybindings.json ~/dotfiles/devin-desktop
    cp ~/Library/Application\ Support/Devin/User/settings.json ~/dotfiles/devin-desktop
    cp -R ~/Library/Application\ Support/Devin/User/snippets ~/dotfiles/devin-desktop
end
