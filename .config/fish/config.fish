alias vi="/usr/local/bin/vim"
alias c="clear"
alias cp="rsync -ah --progress"
alias lf="perl -pe 's/\n/\n\n/g'"

set -x PATH /usr/local/Cellar/ruby/2.4.1_1/bin /usr/local/bin $HOME/node_modules/.bin $HOME/.composer/vendor/bin $PATH
set -x NODE_PATH /usr/local/lib/node_modules

set -x GCE_INI_PATH $HOME/repository/ansible/gce/gce.ini

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

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/ryota.murakami/google-cloud-sdk/path.fish.inc' ]; if type source > /dev/null; source '/Users/ryota.murakami/google-cloud-sdk/path.fish.inc'; else; . '/Users/ryota.murakami/google-cloud-sdk/path.fish.inc'; end; end
