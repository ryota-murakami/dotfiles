# =============================================================================
# rollback_devin_desktop_config - Restore Devin Desktop Editor Settings from Dotfiles
# =============================================================================
#
# DESCRIPTION:
#   Restores Devin Desktop editor settings and keybindings from the dotfiles
#   backup to the system location. Devin Desktop (formerly Windsurf) is an
#   AI-powered code editor.
#
# USAGE:
#   rollback_devin_desktop_config
#
# FILES RESTORED:
#   - ~/dotfiles/devin-desktop/keybindings.json → Devin Desktop keybindings
#   - ~/dotfiles/devin-desktop/settings.json → Devin Desktop settings
#
# DESTINATION:
#   ~/Library/Application Support/Devin/User/
#
# NOTE:
#   Does not restore snippets/ directory (manually copy if needed).
#   Restart Devin Desktop after running for changes to take effect.
#
# EXAMPLE:
#   # After fresh Devin Desktop installation:
#   $ rollback_devin_desktop_config
#   # Restart Devin Desktop - settings restored!
#
# RELATED:
#   - save_devin_desktop_config.fish (backup settings)
#   - rollback_cursor_config.fish (for Cursor)
#
# =============================================================================
function rollback_devin_desktop_config
    cp ~/dotfiles/devin-desktop/keybindings.json ~/Library/Application\ Support/Devin/User
    cp ~/dotfiles/devin-desktop/settings.json ~/Library/Application\ Support/Devin/User
end
