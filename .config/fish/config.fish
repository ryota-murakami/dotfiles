#!/usr/local/bin/fish

alias vi="/usr/bin/vim"
alias c="clear"
alias lf="perl -pe 's/\n/\n\n/g'"
alias chrome="/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --guest"
alias wanip="curl https://ipinfo.io/ip"
alias desktopjs="/Applications/Chromium.app/Contents/MacOS/Chromium --auto-open-devtools-for-tabs"

set -x PATH /opt/homebrew/bin $HOME/.deno/bin $HOME/.cargo/bin $HOME/Library/Python/2.7/bin $PATH

# Color of 'ls' output
set -U LSCOLORS gxfxcxdxbxegedabagacad

function base64rand
    openssl rand -base64 32
end

function genpasswd 
    pwgen -Bsy $argv 1 |pbcopy |pbpaste; echo “Has been copied to clipboard”
end

function ssh-swh
    ssh-add -D
    if [ -z $argv ]
      return
    else  
      ssh-add $argv
    end
end

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

alias remove_all_vscode_settings="rm -rf ~/Library/Application\ Support/Code/"
alias edit_vsc_keybindings="code ~/Library/Application\ Support/Code/User/keybindings.json"
alias show_vsc_keybindings="view ~/Library/Application\ Support/Code/User/keybindings.json"
alias edit_vsc_settings="code ~/Library/Application\ Support/Code/User/settings.json"
alias show_vsc_settings="view ~/Library/Application\ Support/Code/User/settings.json"

set -gx VOLTA_HOME "$HOME/.volta"
set -gx PATH "$VOLTA_HOME/bin" $PATH
fish_add_path /opt/homebrew/sbin
fish_add_path /usr/local/sbin

source /Users/ryota.murakami/.docker/init-fish.sh || true # Added by Docker Desktop

# pnpm
set -gx PNPM_HOME "/Users/ryota.murakami/Library/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end
