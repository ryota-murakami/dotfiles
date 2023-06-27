#!/usr/local/bin/fish

alias vi="/usr/bin/vim"
alias c="clear"
alias lf="perl -pe 's/\n/\n\n/g'"
alias chrome="/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --guest"
alias wanip="curl https://ipinfo.io/ip"
alias engine="/Applications/Chromium.app/Contents/MacOS/Chromium --auto-open-devtools-for-tabs"
alias ds="du -sh"
alias strage="sudo du -hd3 ~ 2>&1 | sort -hr | head -n 20"

set -x PATH /opt/homebrew/bin $HOME/.deno/bin $HOME/.cargo/bin $HOME/Library/Python/2.7/bin $HOME/nvim-macos/bin $PATH

# Color of 'ls' output
set -U LSCOLORS gxfxcxdxbxegedabagacad

set -g __fish_git_prompt_shorten_branch_len 30

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

function show_all_commands
  for dir in (echo $PATH | string split " ")
    if test $dir != "/Users/ryota.murakami/Library/pnpm"
        echo $dir
        tree -fiC --noreport $dir | grep -v '/$'
        echo ""
     end
  end
end

function mov2gif
  set out (echo $argv | sed 's/\.mov$/\.gif/')
  set max_width "650"
  set frames_per_second "20"
  ffmpeg -i $argv -vf "scale=min(iw\,$max_width):-1" -r "$frames_per_second" -sws_flags lanczos -f image2pipe -vcodec ppm - \
    | convert -delay 5 -layers Optimize -loop 0 - "$out" &&
  echo (tput setaf 2)output file: $out(tput sgr 0) &&
  open -a Google\ Chrome $out
end

function jsx_to_tsx
    find ./src -name "*.jsx" -exec bash -c 'mv "$0" "${0%.jsx}.tsx"' {} \;
end

function awsdir
    switch $argv[1]
        case "laststance"
            ln -sf ~/asw-laststance ~/.aws
            echo "Linked to asw-laststance"
        case "customer"
            ln -sf ~/aws-customer ~/.aws
            echo "Linked to aws-customer"
        case "*"
            set linked_dir (readlink ~/.aws)
            switch $linked_dir
                case "*asw-laststance*"
                    echo "Currently linked to asw-laststance"
                case "*aws-customer*"
                    echo "Currently linked to aws-customer"
                case "*"
                    echo "Not linked to a valid directory: $linked_dir"
            end
    end
end

alias exbk="cd /Users/ryota.murakami/repository/excalidraw-backup && git up"
alias cdl="cd /Users/ryota.murakami/laststance"
alias cdutils="cd /Users/ryota.murakami/laststance/react-node-utils"

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
