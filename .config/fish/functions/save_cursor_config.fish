# =============================================================================
# save_cursor_config - Backup Cursor Editor Settings to Dotfiles
# =============================================================================
#
# DESCRIPTION:
#   Copies Cursor editor settings, keybindings, and snippets from the
#   system location to the dotfiles repository for version control backup.
#   Cursor is an AI-powered code editor based on VS Code.
#
# USAGE:
#   save_cursor_config
#
# FILES BACKED UP:
#   - keybindings.json → ~/dotfiles/cursor/keybindings.json
#   - settings.json → ~/dotfiles/cursor/settings.json
#   - snippets/ → ~/dotfiles/cursor/snippets/ (entire directory)
#
# SOURCE LOCATION:
#   ~/Library/Application Support/Cursor/User/
#
# EXAMPLE:
#   $ save_cursor_config
#   # Settings copied to ~/dotfiles/cursor/
#
#   $ cd ~/dotfiles && git status
#   # See backed up files
#
# RELATED:
#   - rollback_cursor_config.fish (restore from backup)
#   - save_vsc_config.fish (for VS Code)
#
# =============================================================================
function save_cursor_config
    cp ~/Library/Application\ Support/Cursor/User/keybindings.json ~/dotfiles/cursor
    cp ~/Library/Application\ Support/Cursor/User/settings.json ~/dotfiles/cursor
    cp -R ~/Library/Application\ Support/Cursor/User/snippets ~/dotfiles/cursor
end
