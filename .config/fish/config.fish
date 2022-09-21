#!/usr/local/bin/fish

alias vi="/usr/bin/vim"
alias c="clear"
alias lf="perl -pe 's/\n/\n\n/g'"
alias delete_all_vscode_settings="rm -rf ~/Library/Application\ Support/Code/"
alias chrome="/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --guest"
alias wanip="curl https://ipinfo.io/ip"

set -x VOLTA_HOME $HOME/.volta
set -x PATH $VOLTA_HOME/bin $HOME/.nodebrew/current/bin $HOME/.volta/bin $HOME/.rbenv/bin $HOME/.deno/bin $HOME/.cargo/bin $HOME/Library/Python/2.7/bin $PATH
status --is-interactive; and source (rbenv init -|psub)

# Color of 'ls' output
set -U LSCOLORS gxfxcxdxbxegedabagacad
direnv hook fish | source

function weather
    if [ -z $argv ]
        set locate tokyo
    else
        set locate $argv
    end

    curl wttr.in/$locate
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

function disc_usage
    sudo du -g -x -d 5 / | awk '$1 >= 5{print}'
end

function port_usage
    sudo lsof -PiTCP -sTCP:LISTEN
end

function get_pid_by_name
  ps -e | grep -m1 $argv | awk '{print $1}'
end

# ==> sqlite
# sqlite is keg-only, which means it was not symlinked into /usr/local
# because macOS already provides this software and installing another version in
# parallel can cause all kinds of trouble.

# If you need to have sqlite first in your PATH, run:
#  echo 'set -g fish_user_paths "/usr/local/opt/sqlite/bin" $fish_user_paths' >> ~/.config/fish/config.fish

#For compilers to find sqlite you may need to set:
#  set -gx LDFLAGS "-L/usr/local/opt/sqlite/lib"
#  set -gx CPPFLAGS "-I/usr/local/opt/sqlite/include"

#For pkg-config to find sqlite you may need to set:
#  set -gx PKG_CONFIG_PATH "/usr/local/opt/sqlite/lib/pkgconfig"
set -g fish_user_paths "/usr/local/opt/sqlite/bin" $fish_user_paths

fish_add_path /usr/local/sbin
