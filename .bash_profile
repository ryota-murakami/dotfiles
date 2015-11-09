# ショーカット
alias ll="ls -l"
alias d='cd ~/repository'
alias c='clear'

# path
export PATH="$HOME/node_modules/.bin:$HOME/.composer/vendor/bin:$HOME/.rbenv/bin:$HOME/.rbenv/versions/2.2.0/bin:$PATH"
export PATH="/usr/local/bin:$PATH"
export PATH="$(brew --prefix homebrew/php/php56)/bin:$PATH"
eval "$(rbenv init -)"

# gitコマンド補完
source /usr/local/etc/bash_completion.d/git-prompt.sh
source /usr/local/etc/bash_completion.d/git-completion.bash

genpasswd() { pwgen -Bs $1 1 |pbcopy |pbpaste; echo “Has been copied to clipboard”
}
