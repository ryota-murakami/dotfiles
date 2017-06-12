alias vi="/usr/local/bin/vim"
alias c="clear"
alias cp="rsync -ah --progress"
alias lf="perl -pe 's/\n/\n\n/g'"

set -x PATH $PATH $HOME/.rbenv/shims
set -x PATH $PATH /usr/local/bin
set -x PATH $PATH $HOME/node_modules/.bin
set -x PATH $PATH $HOME/.composer/vendor/bin

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

function cpuinfo
    system_profiler SPHardwareDataType
end
