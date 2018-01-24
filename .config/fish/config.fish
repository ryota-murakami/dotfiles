alias vi="/usr/local/bin/vim"
alias c="clear"
alias cp="rsync -ah --progress"
alias lf="perl -pe 's/\n/\n\n/g'"

set -x PATH /usr/local/opt/ruby/bin /usr/local/bin $PATH
set -x NODE_PATH /usr/local/lib/node_modules
set -x ANDROID_HOME /Users/ryota.murakami/Library/Android/sdk

set -x GCE_INI_PATH $HOME/repository/ansible/gce/gce.ini

# lsコマンドのカラー
set -U LSCOLORS gxfxcxdxbxegedabagacad

eval (direnv hook fish)
status --is-interactive; and . (pyenv init -|psub)

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

function ssdinfo
    sudo du -hs * | gsort -hr
end

function dc
    docker rm (docker ps -a -q)
end

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/ryota.murakami/google-cloud-sdk/path.fish.inc' ]; if type source > /dev/null; source '/Users/ryota.murakami/google-cloud-sdk/path.fish.inc'; else; . '/Users/ryota.murakami/google-cloud-sdk/path.fish.inc'; end; end
