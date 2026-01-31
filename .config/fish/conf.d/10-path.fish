# =============================================================================
# 10-path.fish - PATH Configuration
# =============================================================================
#
# DESCRIPTION:
#   Configures the system PATH for all development tools. Paths are added
#   in priority order (most specific first). This file is synchronized with
#   .path for bash/zsh compatibility.
#
# USAGE:
#   Auto-loaded by fish shell on startup. To verify PATH:
#     echo $PATH | tr ' ' '\n'
#

# EXAMPLES:
#   # Check if a tool is in PATH:
#   which cargo       # → ~/.cargo/bin/cargo
#
#   # Verify PATH order:
#   echo $PATH | tr ' ' '\n' | head -10
#
# PATH ORDER (highest priority first):
#   1. nvim-macos/bin  - Neovim (custom macOS build)
#   2. cargo/bin       - Rust tools
#   3. bun/bin         - Bun runtime
#   6. homebrew/bin    - Homebrew packages
#   7. local/bin       - uv and other local tools
#   8. homebrew/sbin   - System utilities
#   9. Android SDK     - emulator, platform-tools
#   10. Conditional    - Maestro, Windsurf, Antigravity (if installed)
#
# =============================================================================

# -----------------------------------------------------------------------------
# Core Development Tools
# -----------------------------------------------------------------------------
# Homebrew (Apple Silicon path)
set -gx PATH /opt/homebrew/bin $PATH

# Rust toolchain (cargo, rustc, rustup)
fish_add_path --prepend "$HOME/.cargo/bin"

# Neovim (custom macOS build for better performance)
fish_add_path --prepend "$HOME/nvim-macos/bin"

# -----------------------------------------------------------------------------
# JavaScript Ecosystem
# -----------------------------------------------------------------------------

# pnpm global packages
set -gx PNPM_HOME "$HOME/Library/pnpm"
fish_add_path --prepend "$PNPM_HOME"

# Bun runtime and package manager
set --export PATH $BUN_INSTALL/bin $PATH

# -----------------------------------------------------------------------------
# Python Tools
# -----------------------------------------------------------------------------
# uv (fast Python package installer) and other local binaries
fish_add_path "$HOME/.local/bin"

# -----------------------------------------------------------------------------
# System Utilities
# -----------------------------------------------------------------------------
# Homebrew system binaries
fish_add_path /usr/local/sbin

# -----------------------------------------------------------------------------
# Android Development
# -----------------------------------------------------------------------------
# Android emulator (for running virtual devices)
if test -d "$ANDROID_HOME/emulator"
    if not contains -- "$ANDROID_HOME/emulator" $PATH
        set -x PATH $PATH $ANDROID_HOME/emulator
    end
end

# Android platform-tools (adb, fastboot)
if test -d "$ANDROID_HOME/platform-tools"
    if not contains -- "$ANDROID_HOME/platform-tools" $PATH
        set -x PATH $PATH $ANDROID_HOME/platform-tools
    end
end

# =============================================================================
# Conditional Paths (only add if tool is installed)
# =============================================================================
# These tools are optional and only added to PATH if their directories exist

# Maestro - Mobile UI testing framework
# Install: curl -Ls "https://get.maestro.mobile.dev" | bash
test -d "$HOME/.maestro/bin"; and fish_add_path "$HOME/.maestro/bin"

# Windsurf - AI-powered IDE by Codeium
# Install: Download from https://codeium.com/windsurf
test -d "$HOME/.codeium/windsurf/bin"; and fish_add_path "$HOME/.codeium/windsurf/bin"

# Antigravity - Custom tool
test -d "$HOME/.antigravity/antigravity/bin"; and fish_add_path "$HOME/.antigravity/antigravity/bin"
