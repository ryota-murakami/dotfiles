# =============================================================================
# rollback_cursor_config - Restore Cursor Editor Settings from Dotfiles
# =============================================================================
#
# DESCRIPTION:
#   Restores Cursor editor settings and keybindings from the dotfiles
#   backup to the system location. Cursor is an AI-powered code editor.
#
# USAGE:
#   rollback_cursor_config
#
# FILES RESTORED:
#   - ~/dotfiles/cursor/keybindings.json → Cursor keybindings
#   - ~/dotfiles/cursor/settings.json → Cursor settings
#
# DESTINATION:
#   ~/Library/Application Support/Cursor/User/
#
# NOTE:
#   Does not restore snippets/ directory (manually copy if needed).
#   Restart Cursor after running for changes to take effect.
#
# EXAMPLE:
#   # After fresh Cursor installation:
#   $ rollback_cursor_config
#   # Restart Cursor - settings restored!
#
# RELATED:
#   - save_cursor_config.fish (backup settings)
#   - rollback_vsc_config.fish (for VS Code)
#
# =============================================================================
function rollback_cursor_config
    cp ~/dotfiles/cursor/keybindings.json ~/Library/Application\ Support/Cursor/User
    cp ~/dotfiles/cursor/settings.json ~/Library/Application\ Support/Cursor/User
end
