alias vi="/usr/local/bin/vim"
alias c="clear"
alias cp="rsync -ah --progress"
alias lf="perl -pe 's/\n/\n\n/g'"

set -x PATH $HOME/.nodebrew/current/bin /usr/local/opt/ruby/bin /usr/local/bin $PATH

# lsコマンドのカラー
set -U LSCOLORS gxfxcxdxbxegedabagacad

eval (direnv hook fish)

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

function collectDiscUsage
    sudo du -g -x -d 5 / | awk '$1 >= 5{print}'
end

