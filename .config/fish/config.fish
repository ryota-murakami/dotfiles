#!/usr/local/bin/fish
# =============================================================================
# Fish Shell Configuration
# =============================================================================
#
# This is a minimal config.fish file. All configurations are modularized:
#
# conf.d/
#   00-env.fish     - Environment variables
#   10-path.fish    - PATH configurations
#   20-aliases.fish - Shell aliases
#   30-tools.fish   - Tool initializations (zoxide, etc.)
#   40-lazy.fish    - Lazy loading configurations
#   rustup.fish     - Rust toolchain (auto-generated)
#
# functions/
#   - Individual function files are auto-loaded by fish
#   - Each function is in its own file (e.g., awsdir.fish, genpasswd.fish)
#
# Note: Fish automatically sources conf.d/*.fish and auto-loads functions/
# =============================================================================

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init2.fish 2>/dev/null || :

source ~/.safe-chain/scripts/init-fish.fish # Safe-chain Fish initialization script
