# =============================================================================
# save_windsurf_config - Backup Windsurf Editor Settings to Dotfiles
# =============================================================================
#
# DESCRIPTION:
#   Copies Windsurf editor settings, keybindings, and snippets from the
#   system location to the dotfiles repository for version control backup.
#   Windsurf is an AI-powered code editor based on VS Code.
#
# USAGE:
#   save_windsurf_config
#
# FILES BACKED UP:
#   - keybindings.json → ~/dotfiles/windsurf/keybindings.json
#   - settings.json → ~/dotfiles/windsurf/settings.json
#   - snippets/ → ~/dotfiles/windsurf/snippets/ (entire directory)
#
# SOURCE LOCATION:
#   ~/Library/Application Support/Windsurf/User/
#
# EXAMPLE:
#   $ save_windsurf_config
#   # Settings copied to ~/dotfiles/windsurf/
#
#   $ cd ~/dotfiles && git status
#   # See backed up files
#
# RELATED:
#   - rollback_windsurf_config.fish (restore from backup)
#   - save_cursor_config.fish (for Cursor)
#
# =============================================================================
function save_windsurf_config
    cp ~/Library/Application\ Support/Windsurf/User/keybindings.json ~/dotfiles/windsurf
    cp ~/Library/Application\ Support/Windsurf/User/settings.json ~/dotfiles/windsurf
    cp -R ~/Library/Application\ Support/Windsurf/User/snippets ~/dotfiles/windsurf
end
