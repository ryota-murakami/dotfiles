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
#   - pyenv (python, pip): Python version manager
#   - direnv: Directory-specific environment variables
#   - OrbStack (docker): Docker Desktop alternative
#   - Kiro: AI terminal integration
#
# EXAMPLES:
#   # First python call initializes pyenv (slight delay):
#   python --version
#
#   # Subsequent calls are instant (pyenv already loaded):
#   python script.py
#
#   # First docker call initializes OrbStack:
#   docker ps
#
# HOW IT WORKS:
#   1. Wrapper function intercepts the command
#   2. Loads the actual tool (pyenv init, OrbStack init, etc.)
#   3. Removes the wrapper function (functions -e)
#   4. Executes the original command with arguments
#
# =============================================================================

if status is-interactive
    # -------------------------------------------------------------------------
    # direnv - Directory Environment Manager
    # -------------------------------------------------------------------------
    # Only load direnv hook if .envrc exists in current directory.
    # This avoids the overhead of direnv when not needed.
    #
    # Usage: Create a .envrc file in any directory with environment variables.
    # Example .envrc:
    #   export DATABASE_URL="postgres://localhost/myapp"
    #   export API_KEY="secret123"
    #
    # Install: brew install direnv
    if test -f .envrc
        eval "$(direnv hook fish)"
    end

    # -------------------------------------------------------------------------
    # pyenv - Python Version Manager (Lazy Loaded)
    # -------------------------------------------------------------------------
    # Wrapper functions that initialize pyenv on first use of python/pip.
    # After initialization, the wrappers remove themselves.
    #
    # Usage:
    #   pyenv install 3.12.0     # Install Python version
    #   pyenv global 3.12.0      # Set global version
    #   python --version         # Triggers lazy load on first call
    #
    # Install: brew install pyenv
    function python --wraps python
        pyenv init - | source
        functions -e python pip  # Remove wrappers after init
        python $argv
    end

    function pip --wraps pip
        pyenv init - | source
        functions -e pip python  # Remove wrappers after init
        pip $argv
    end

    # -------------------------------------------------------------------------
    # OrbStack - Docker Desktop Alternative (Lazy Loaded)
    # -------------------------------------------------------------------------
    # OrbStack is a fast, lightweight Docker Desktop replacement for macOS.
    # The wrapper loads OrbStack's shell integration on first docker command.
    #
    # Usage:
    #   docker ps                # First call initializes OrbStack
    #   docker-compose up        # Works after initialization
    #
    # Install: brew install orbstack
    function docker --wraps docker
        source ~/.orbstack/shell/init2.fish 2>/dev/null || :
        functions -e docker  # Remove wrapper after init
        docker $argv
    end
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
