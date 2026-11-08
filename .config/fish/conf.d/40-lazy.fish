# =============================================================================
# 40-lazy.fish - Lazy Loading Configurations
# =============================================================================
#
# DESCRIPTION:
#   Implements lazy loading for slow-initializing tools. Instead of loading
#   these tools on every shell startup (which would slow down shell launch),
#   we create wrapper functions that initialize the tool on first use.
#
#   This improves shell startup time significantly while maintaining
#   seamless tool availability.
#
# USAGE:
#   Auto-loaded by fish shell on startup. The wrapper functions are
#   transparent - just use the tools normally and they'll initialize
#   automatically on first use.
#
# LAZY-LOADED TOOLS:
#   - Kiro: AI terminal integration
#   (direnv is hooked in conf.d/direnv.fish)
#
# EXAMPLES:
#   # First tool call initializes the tool (slight delay),
#   # subsequent calls are instant (wrapper already removed).
#
# HOW IT WORKS:
#   1. Wrapper function intercepts the command
#   2. Loads the actual tool (pyenv init, OrbStack init, etc.)
#   3. Removes the wrapper function (functions -e)
#   4. Executes the original command with arguments
#
# =============================================================================

if status is-interactive
    # direnv hook lives in conf.d/direnv.fish (overrides Homebrew vendor conf).
end

# -----------------------------------------------------------------------------
# Kiro Shell Integration
# -----------------------------------------------------------------------------
# Kiro is an AI-powered terminal. This loads its shell integration only
# when running inside the Kiro terminal (detected via TERM_PROGRAM).
#
# Install: Download from https://kiro.dev
if status is-interactive; and string match -q "$TERM_PROGRAM" "kiro"
    . (kiro --locate-shell-integration-path fish)
end
