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

fish_add_path -gm /Users/ryotamurakami/go/bin


# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/ryotamurakami/Downloads/google-cloud-sdk/path.fish.inc' ]; . '/Users/ryotamurakami/Downloads/google-cloud-sdk/path.fish.inc'; end

# Rust/Cargo
fish_add_path ~/.cargo/bin

# try CLI (Homebrew)
fish_add_path /opt/homebrew/opt/ruby/bin
# try picks the init language from $SHELL: pin it to fish, or a fish started from zsh/bash
# (Claude Code, scripts) gets bash code and errors on every start
eval (SHELL=(status fish-path) try init ~/src/tries | string collect)

# Added by Devin
fish_add_path /Users/ryotamurakami/.codeium/windsurf/bin

# Keep Homebrew's dependency-only Node out of fish even when inherited.
set -gx PATH (string match -v /opt/homebrew/opt/node/bin $PATH)

# Homebrew: disable interactive confirmation on upgrade/install prompts.
set -Ux HOMEBREW_NO_ASK 1

# Ensure ~/.local/bin is on PATH
fish_add_path "$HOME/.local/bin"

# OpenClaw Completion
test -f "/Users/ryotamurakami/.openclaw/completions/openclaw.fish"; and source "/Users/ryotamurakami/.openclaw/completions/openclaw.fish"

# 1Password Shell Plugins: doctl reads its DigitalOcean token from 1Password (Touch ID) instead of a saved config
test -f ~/.config/op/plugins.sh; and source ~/.config/op/plugins.sh

# Keep Vite+'s Node ahead of mise's shims. Homebrew's vendor_conf.d/mise-activate.fish
# runs after conf.d/vite-plus.fish and prepends ~/.local/share/mise/shims, then keeps
# re-prepending it on every directory change. Re-assert order after mise's hooks:
# insert vite-plus/bin right before the shims entry so mise-managed tool dirs
# (prepended by `mise hook-env` inside .mise.toml dirs) still win.
set -gx PATH $HOME/.vite-plus/bin (string match -v -- $HOME/.vite-plus/bin $PATH)
function __vite_plus_node_first --on-variable PWD --on-event fish_prompt
    set -l vpbin $HOME/.vite-plus/bin
    set -l shims $HOME/.local/share/mise/shims
    while set -l i (builtin contains -i -- $vpbin $PATH)
        set -e PATH[$i]
    end
    set -l s (builtin contains -i -- $shims $PATH)
    if set -q s[1]; and test $s[1] -gt 1
        set -gx PATH $PATH[1..(math $s[1] - 1)] $vpbin $PATH[$s[1]..-1]
    else
        set -gx PATH $vpbin $PATH
    end
end
