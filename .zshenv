# ツール設定（Fish shellから移植）
export BUN_INSTALL="$HOME/.bun"

# Cargo環境設定
. "$HOME/.cargo/env"

# Vite+ bin (https://viteplus.dev)
. "$HOME/.vite-plus/env"

# Words starting with "=" (e.g. echo ======) stay literal instead of expanding to a command path.
setopt NO_EQUALS
