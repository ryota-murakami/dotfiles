#!/usr/local/bin/fish

alias vi="/usr/bin/vim"
alias c="clear"
alias lf="perl -pe 's/\n/\n\n/g'"
alias chrome="/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --guest"
alias wanip="curl https://ipinfo.io/ip"
alias v8="/Applications/Chromium.app/Contents/MacOS/Chromium --auto-open-devtools-for-tabs"
alias ds="du -sh"
alias npbp="npm outdated | grep -v Package | awk '{print $1}' | xargs -I% npm install --force %@latest"
alias h="cd ~"
alias nsx="cd ~/nsx"
alias util="cd ~/utils"
alias l="cd ~/laststance"
alias r="cd ~/repository"

set -x LESS "-R"
set -x PATH /opt/homebrew/bin $HOME/.deno/bin $HOME/.cargo/bin $HOME/Library/Python/2.7/bin $HOME/nvim-macos/bin $PATH

# Color of 'ls' output
set -U LSCOLORS gxfxcxdxbxegedabagacad

set -g __fish_git_prompt_shorten_branch_len 30

function find-file
  find $argv[1] -type f -name $argv[2] 2>/dev/null
end

function base64rand
    openssl rand -base64 32
end

function genpasswd 
    pwgen -Bsy $argv 1 |pbcopy |pbpaste; echo "Has been copied to clipboard"
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
            test -L ~/.aws; and unlink ~/.aws
            ln -sf ~/aws-laststance ~/.aws
            echo "Linked to asw-laststance"
        case "customer"
            test -L ~/.aws; and unlink ~/.aws
            ln -sf ~/aws-customer ~/.aws
            echo "Linked to aws-customer"
        case "prod"
            test -L ~/.aws; and unlink ~/.aws
            ln -sf ~/aws-prod ~/.aws
            echo "Linked to aws-prod"
        case "*"
            set linked_dir (readlink ~/.aws)
            switch $linked_dir
                case "*aws-laststance*"
                    echo "Currently linked to aws-laststance"
                case "*aws-customer*"
                    echo "Currently linked to aws-customer"
                case "*"
                    echo "Not linked to a valid directory: $linked_dir"
            end
    end
end

function storage_usage
    if not test -n $argv[1]
        echo 'Expected delectory path as first argument.'
        return 1
    else
        sudo du -hd3 $argv[1] 2>&1 | sort -hr | head -n 20
    end
end

function print_argv
    echo "\$argv: $argv"
    echo "\$argv[1]: $argv[1]"
    echo "\$argv[2]: $argv[2]"
end

set -gx VOLTA_HOME "$HOME/.volta"
set -gx PATH "$VOLTA_HOME/bin" $PATH
fish_add_path /opt/homebrew/sbin
fish_add_path /usr/local/sbin

# pnpm
set -gx PNPM_HOME "/Users/ryota.murakami/Library/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end

# Created by `pipx` on 2023-08-09 12:25:13
set PATH $PATH /Users/ryota.murakami/.local/bin

# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH
