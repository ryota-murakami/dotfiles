#!/usr/local/bin/fish

alias vi="/usr/bin/vim"
alias c="clear"
alias lf="perl -pe 's/\n/\n\n/g'"

set -x PATH $HOME/.nodebrew/current/bin $HOME/.rbenv/bin $HOME/Library/Python/2.7/bin $PATH
status --is-interactive; and source (rbenv init -|psub)

# Color of 'ls' output
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

function chrome 
  /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --guest
end

function gh-actions
  mkdir .github
  cd .github
  mkdir workflows
  cd workflows
  touch ci.yml
  cd ../../
end

function copy_head_commit_hash
    git rev-parse --short HEAD | pbcopy
end

function cpuinfo
    system_profiler SPHardwareDataType
end

function ssdinfo
    sudo du -hs * | gsort -hr
end

function kill_all_docker_container
    docker rm (docker ps -a -q)
end

function remove_all_docker_images
  docker rmi (docker images -q)
end

function collectDiscUsage
    sudo du -g -x -d 5 / | awk '$1 >= 5{print}'
end

