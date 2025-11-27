# =============================================================================
# _fzf_compgen_path - FZF Path Completion Generator
# =============================================================================
#
# DESCRIPTION:
#   Custom path generator for FZF (fuzzy finder) file completion.
#   Uses 'fd' instead of the default 'find' for better performance
#   and automatic .gitignore respect.
#
# USAGE:
#   This function is called automatically by FZF during tab completion.
#   Not intended for direct use.
#
#   Triggered by: Ctrl+T in terminal (FZF file search)
#
# ARGUMENTS:
#   $argv - Base path to start file traversal from
#
# DEPENDENCIES:
#   - fd (brew install fd)
#   - fzf (brew install fzf)
#
# RELATED:
#   - _fzf_compgen_dir.fish (directory-only version)
#   - 00-env.fish (FZF_DEFAULT_COMMAND settings)
#
# EXAMPLE:
#   # Internally called when you press Ctrl+T:
#   _fzf_compgen_path /some/directory
#   # Returns: list of all files under /some/directory
#
# =============================================================================
function _fzf_compgen_path
    fd --hidden --exclude .git . $argv
end
