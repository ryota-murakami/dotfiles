# =============================================================================
# 21-sfw.fish - Socket Firewall (sfw) package manager aliases
# =============================================================================
# Synchronized with ~/.aliases-sfw for bash/zsh.
# Install: npm install -g sfw
# Toggle wrapping on/off with `sfw on|off|toggle` (state: ~/.sfw-disabled)

# Skip when wrapping is disabled via `sfw off`
if not test -f ~/.sfw-disabled
    # JavaScript/TypeScript
    alias npm="sfw npm"
    alias npx="sfw npx"
    alias pnpm="sfw pnpm"
    alias pnpx="sfw pnpx"
    alias yarn="sfw yarn"
    alias bun="sfw bun"

    # Python
    alias pip="sfw pip"
    alias pip3="sfw pip3"
    alias uv="sfw uv"

    # Rust
    alias cargo="sfw cargo"
end
