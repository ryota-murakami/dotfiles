alias vi="/usr/local/bin/vim"
alias c="clear"
alias cp="rsync -ah --progress"

set -U fish_user_paths $fish_user_paths $HOME/.rbenv/shims
set -U fish_user_paths $fish_user_paths /usr/local/bin
set -U fish_user_paths $fish_user_paths $HOME/node_modules/.bin
set -U fish_user_paths $fish_user_paths $HOME/.composer/vendor/bin

set -x NODE_PATH /usr/local/lib/node_modules

# lsコマンドのカラー
set -U LSCOLORS gxfxcxdxbxegedabagacad

eval (direnv hook fish)

# fish用のphpbrew初期化ファイル
if [ -f ~/.phpbrew/phpbrew.fish ]
  source ~/.phpbrew/phpbrew.fish
end

function weather
  if [ -z $argv ]
    set locate tokyo
  else
    set locate $argv
  end

  curl wttr.in/$locate
end

function rh
    git rev-parse --short HEAD | pbcopy
end
