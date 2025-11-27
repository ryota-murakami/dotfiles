# ショーカット
alias ll="ls -lG"
alias d='cd ~/repository'
alias c='clear'
alias ga='git add --all && git commit'

# 環境依存のショートカット
if [ -r ~/.local_config.sh ]; then
  source ~/.local_config.sh
fi

# lsコマンドのカラー（Fish shellの設定に合わせて更新）
export LSCOLORS="CxGxBxDxCxEgEdxbxgxcxd"

# Fish shellから移植された環境変数
export EZA_COLORS="di=1;32"
export LESS="-R"

# FZF設定（Fish shellから移植）
export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"

# ツール設定
export VOLTA_HOME="$HOME/.volta"
export PNPM_HOME="$HOME/Library/pnpm"
export BUN_INSTALL="$HOME/.bun"

# path（Fish shellの設定に合わせて更新）
export PATH="$HOME/nvim-macos/bin:$VOLTA_HOME/bin:$PNPM_HOME:$BUN_INSTALL/bin:/usr/local/sbin:$HOME/.local/bin:$HOME/node_modules/.bin:$HOME/.composer/vendor/bin:/usr/local/bin:$PATH"

# gitコマンド補完
source /usr/local/etc/bash_completion.d/git-prompt.sh
source /usr/local/etc/bash_completion.d/git-completion.bash

### 関数定義
# パスワードのランダム生成
genpasswd() {
  pwgen -Bsy $1 1 |pbcopy |pbpaste; echo "Has been copied to clipboard"
}

# ssh wrapper
ssh () {
  if [ -d ~/.ssh/config.d ]
  then
    cat ~/.ssh/config.d/*.conf > ~/.ssh/config
    chmod 600 ~/.ssh/config
  fi
  command ssh $@
}

# .editorconfig生成
geneditconf() {
  cp ~/dotfiles/.editorconfig .
  ll .editorconfig
}

# ツール初期化（Fish shellから移植）
eval "$(direnv hook bash)"
eval "$(pyenv init -)"
eval "$(zoxide init bash)"

. "$HOME/.cargo/env"
export PATH=$PATH:$HOME/.maestro/bin
