# =============================================================================
# rollback_windsurf_config - Restore Windsurf Editor Settings from Dotfiles
# =============================================================================
#
# DESCRIPTION:
#   Restores Windsurf editor settings and keybindings from the dotfiles
#   backup to the system location. Windsurf is an AI-powered code editor.
#
# USAGE:
#   rollback_windsurf_config
#
# FILES RESTORED:
#   - ~/dotfiles/windsurf/keybindings.json → Windsurf keybindings
#   - ~/dotfiles/windsurf/settings.json → Windsurf settings
#
# DESTINATION:
#   ~/Library/Application Support/Windsurf/User/
#
# NOTE:
#   Does not restore snippets/ directory (manually copy if needed).
#   Restart Windsurf after running for changes to take effect.
#
# EXAMPLE:
#   # After fresh Windsurf installation:
#   $ rollback_windsurf_config
#   # Restart Windsurf - settings restored!
#
# RELATED:
#   - save_windsurf_config.fish (backup settings)
#   - rollback_cursor_config.fish (for Cursor)
#
# =============================================================================
function rollback_windsurf_config
    cp ~/dotfiles/windsurf/keybindings.json ~/Library/Application\ Support/Windsurf/User
    cp ~/dotfiles/windsurf/settings.json ~/Library/Application\ Support/Windsurf/User
end
