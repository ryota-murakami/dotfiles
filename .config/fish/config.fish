#!/usr/local/bin/fish

alias vi="/usr/bin/vim"
alias c="clear"
alias lf="perl -pe 's/\n/\n\n/g'"
alias chrome="/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --guest"
alias wanip="curl https://ipinfo.io/ip"
alias v8="/Applications/Chromium.app/Contents/MacOS/Chromium --auto-open-devtools-for-tabs --incognito"
alias home="cd ~"
alias dotfiles="cd ~/dotfiles"
alias nsx="cd ~/nsx"
alias utils="cd ~/utils"
alias react-utils="cd ~/react-utils"
alias oss-react-app="cd ~/oss-react-app"
alias last="cd ~/laststance"
alias repo="cd ~/repository"
alias exp="cd ~/react-experimental-workspace"
alias vscode-conf-dir="cd /Users/ryota.murakami/Library/Application\ Support/Code/User"
alias clone="cd ~/clone"
alias geek="cd ~/laststance/geek-infiltration"
alias fork="cd ~/fork"
alias io="cd ~/laststance/laststance.io"
alias react-next-tailwind-ui="cd ~/react-next-tailwind-ui"
alias ui-library="cd ~/ui-library"
alias corelive="cd ~/corelive"

set -x LESS "-R"
set -x PATH $HOME/nvim-macos/bin $PATH

# Color of 'ls' output
set -U LSCOLORS gxfxcxdxbxegedabagacad

set -g __fish_git_prompt_shorten_branch_len 30

function i --description 'alias i=SHELL=(which bash) interpreter'
    SHELL=(which bash) interpreter $argv
end

# function function name -d explanation -a argument
#     command ...
# end

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

function fd
    command fd $argv --exclude /System/
end

function save_vsc_config
  cp ~/Library/Application\ Support/Code/User/keybindings.json ~/dotfiles/vscode
  cp ~/Library/Application\ Support/Code/User/settings.json ~/dotfiles/vscode
end

function save_cursor_config
    cp ~/Library/Application\ Support/Cursor/User/keybindings.json ~/dotfiles/cursor
    cp ~/Library/Application\ Support/Cursor/User/settings.json ~/dotfiles/cursor
end

function rollback_cursor_config
    cp ~/dotfiles/cursor/keybindings.json ~/Library/Application\ Support/Cursor/User
    cp ~/dotfiles/cursor/settings.json ~/Library/Application\ Support/Cursor/User
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

function volta-dir
  cd (which volta | awk -F/ 'BEGIN {OFS="/"} {$NF=""; print $0}')
end

function print_argv
    echo "\$argv: $argv"
    echo "\$argv[1]: $argv[1]"
    echo "\$argv[2]: $argv[2]"
end

function fd_dust_ignore_system_volumes
    set name $argv[1]
    sudo fd $name / | grep -v '^/System/Volumes/Data' | while read -l line
        echo $line
        # echo ""
        # set_color bg_white
        # echo $line
        # set_color normal
        # sudo dust --no-percent-bars --depth 1 $line
    end
end

function backup_readlist
    cd ~/nsx
    bash -c './scripts/backup'
    mv backup_*.sql ~/repository/backup-files/readlist/
    cd ~/repository/backup-files/readlist
    git up
    cd ~
end

set -gx VOLTA_HOME "$HOME/.volta"
set -gx PATH "$VOLTA_HOME/bin" $PATH

fish_add_path /usr/local/sbin

# pnpm
set -gx PNPM_HOME "/Users/ryota.murakami/Library/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end

# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH

eval "$(direnv hook fish)"

pyenv init - | source




