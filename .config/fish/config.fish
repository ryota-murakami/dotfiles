alias vi="/usr/local/bin/vim"

set -U fish_user_paths $fish_user_paths /usr/local/bin
set -U fish_user_paths $fish_user_paths $HOME/.rbenv/versions/2.2.3/bin
set -U fish_user_paths $fish_user_paths $HOME/node_modules/.bin
set -U fish_user_paths $fish_user_paths $HOME/.composer/vendor/bin

# lsコマンドのカラー
set -U LSCOLORS gxfxcxdxbxegedabagacad

# Brewfile controller
function brewfile
  [[ ! -r ~/dotfiles/Brewfile ]] and echo "Brewfile not found(◎-◎；)" and return 1

  [[ $1 = "update" ]] and brew bundle dump --force --file=~/dotfiles/Brewfile and echo "Brewfile has been updated." and return 0
end


# .editorconfig生成
function geneditconf
  cp ~/dotfiles/.editorconfig .
  ll .editorconfig
end
