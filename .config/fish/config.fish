alias vi="/usr/local/bin/vim"

set -U fish_user_paths $fish_user_paths $HOME/.rbenv/shims
set -U fish_user_paths $fish_user_paths /usr/local/bin
set -U fish_user_paths $fish_user_paths $HOME/node_modules/.bin
set -U fish_user_paths $fish_user_paths $HOME/.composer/vendor/bin

# lsコマンドのカラー
set -U LSCOLORS gxfxcxdxbxegedabagacad

# fish用のphpbrew初期化ファイル
if [ -f ~/.phpbrew/phpbrew.fish ]
  source ~/.phpbrew/phpbrew.fish
end

# Brewfile controller
function brewfile
  [ ! -r ~/dotfiles/Brewfile ] and echo "Brewfile not found(◎-◎；)" and return 1

  [ $1 = "update" ] and brew bundle dump --force --file=~/dotfiles/Brewfile and echo "Brewfile has been updated." and return 0
end

# .editorconfig生成
function geneditconf
  cp ~/dotfiles/.editorconfig .
  ll .editorconfig
end
