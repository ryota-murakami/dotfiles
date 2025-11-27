# =============================================================================
# _fzf_compgen_dir - FZF Directory Completion Generator
# =============================================================================
#
# DESCRIPTION:
#   Custom directory generator for FZF (fuzzy finder) directory completion.
#   Uses 'fd' instead of the default 'find' for better performance
#   and automatic .gitignore respect. Only returns directories.
#
# USAGE:
#   This function is called automatically by FZF during directory completion.
#   Not intended for direct use.
#
#   Triggered by: Alt+C in terminal (FZF directory search)
#
# ARGUMENTS:
#   $argv - Base path to start directory traversal from
#
# DEPENDENCIES:
#   - fd (brew install fd)
#   - fzf (brew install fzf)
#
# RELATED:
#   - _fzf_compgen_path.fish (all files version)
#   - 00-env.fish (FZF_ALT_C_COMMAND settings)
#
# EXAMPLE:
#   # Internally called when you press Alt+C:
#   _fzf_compgen_dir /some/directory
#   # Returns: list of directories under /some/directory
#
# =============================================================================
function _fzf_compgen_dir
    fd --type=d --hidden --exclude .git . $argv
end
