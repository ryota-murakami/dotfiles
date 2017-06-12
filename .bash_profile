# ショーカット
alias ll="ls -lG"
alias d='cd ~/repository'
alias c='clear'
alias ga='git add --all && git commit'

# 環境依存のショートカット
if [ -r ~/.local_config.sh ]; then
  source ./.local_config.sh
fi

# lsコマンドのカラー
export LSCOLORS="gxfxcxdxbxegedabagacad"

# path
export PATH="$HOME/node_modules/.bin:$HOME/.composer/vendor/bin"
export PATH="/usr/local/bin:$PATH"

# gitコマンド補完
source /usr/local/etc/bash_completion.d/git-prompt.sh
source /usr/local/etc/bash_completion.d/git-completion.bash



### 関数定義
# パスワードのランダム生成
genpasswd() {
  pwgen -Bsy $1 1 |pbcopy |pbpaste; echo “Has been copied to clipboard”
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
