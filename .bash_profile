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
export PATH="$HOME/node_modules/.bin:$HOME/.composer/vendor/bin:$HOME/.rbenv/versions/2.2.0/bin:$PATH"
export PATH="/usr/local/bin:$PATH"
export PATH="$(brew --prefix homebrew/php/php56)/bin:$PATH"
eval "$(rbenv init -)"

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

# Brewfile controller
brewfile() {
  [[ ! -r ~/dotfiles/Brewfile ]] && echo "Brewfile not found(◎-◎；)" && return 1

  [[ $1 = "update" ]] && brew bundle dump --force --file=~/dotfiles/Brewfile && echo "Brewfile has been updated." && return 0
}

# .editorconfig生成
geneditconf() {
  cp ~/dotfiles/.editorconfig .
  ll .editorconfig
}
