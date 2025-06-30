#!/usr/local/bin/fish

alias vi="/usr/bin/vim"
alias c="clear"
alias e="eza --all --long --header --git --icons --color=always"
alias lf="perl -pe 's/\n/\n\n/g'"
alias chrome="/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --guest"
alias wanip="curl https://ipinfo.io/ip"
alias v8="/Applications/Chromium.app/Contents/MacOS/Chromium --auto-open-devtools-for-tabs --incognito --unsafely-disable-devtools-self-xss-warnings"
alias dotfiles="cd ~/dotfiles"
alias nsx="cd ~/nsx"
alias last="cd ~/laststance"
alias io="cd ~/laststance/laststance.io"

set -gx LSCOLORS "CxGxBxDxCxEgEdxbxgxcxd"
set -gx EZA_COLORS "di=1;32"
set -x LESS "-R"
set -x PATH $HOME/nvim-macos/bin $PATH

set -g __fish_git_prompt_shorten_branch_len 30

# -- Use fd instead of fzf --

set -gx FZF_DEFAULT_COMMAND "fd --hidden --strip-cwd-prefix --exclude .git"
set -gx FZF_CTRL_T_COMMAND "$FZF_DEFAULT_COMMAND"
set -gx FZF_ALT_C_COMMAND "fd --type=d --hidden --strip-cwd-prefix --exclude .git"

# Use fd (https://github.com/sharkdp/fd) for listing path candidates.
# - The first argument to the function ($1) is the base path to start traversal
# - See the source code (completion.{bash,zsh}) for the details.
function _fzf_compgen_path
    fd --hidden --exclude .git . $argv
end

# Use fd to generate the list for directory completion
function _fzf_compgen_dir
    fd --type=d --hidden --exclude .git . $argv
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

function remove_chrome_cache
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/Cache
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/Code\ Cache
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/Media\ Cache
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/extensions_crx_cache
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/Shared\ Dictionary
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/IndexedDB
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/WebStorage
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/CacheStorage
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/Service\ Worker
    rm -rf ~/Library/Application\ Support/Google/Chrome/ShaderCache
    rm -rf ~/Library/Application\ Support/Google/Chrome/GrShaderCache
    rm -rf ~/Library/Application\ Support/Google/Chrome/GPUCache
    rm -rf ~/Library/Application\ Support/Google/Chrome/GPUCache
end

function save_vsc_config
  cp ~/Library/Application\ Support/Code/User/keybindings.json ~/dotfiles/vscode
  cp ~/Library/Application\ Support/Code/User/settings.json ~/dotfiles/vscode
end

function save_cursor_config
    cp ~/Library/Application\ Support/Cursor/User/keybindings.json ~/dotfiles/cursor
    cp ~/Library/Application\ Support/Cursor/User/settings.json ~/dotfiles/cursor
    cp -R ~/Library/Application\ Support/Cursor/User/snippets ~/dotfiles/cursor
end

function rollback_cursor_config
    cp ~/dotfiles/cursor/keybindings.json ~/Library/Application\ Support/Cursor/User
    cp ~/dotfiles/cursor/settings.json ~/Library/Application\ Support/Cursor/User
end

function getpr
    gh pr checkout $argv
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

function pid_by_port
    sudo lsof -i :$argv
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

function backup_nsx
    cd ~/nsx
    bash -c './scripts/backup'
    mv backup_*.sql ~/repository/backup-files/nsx/
    cd ~/repository/backup-files/nsx
    git up
    cd ~
end

function flush_dns_cache
    sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
end

function show_claude_md
    grep -v "CLAUDE.md" ~/.gitignore_global > ~/.gitignore_global.tmp
    mv ~/.gitignore_global.tmp ~/.gitignore_global
    echo "Removed CLAUDE.md from .gitignore_global"
end

function hide_claude_md
    if not grep -q "CLAUDE.md" ~/.gitignore_global
        # Check if the file ends with a newline
        if test (tail -c 1 ~/.gitignore_global | wc -l) -eq 0
            # File does not end with newline, add an extra one
            echo "" >> ~/.gitignore_global
        end
        # Now add CLAUDE.md
        echo "CLAUDE.md" >> ~/.gitignore_global
        echo "Added CLAUDE.md to .gitignore_global"
    else
        echo "CLAUDE.md already exists in .gitignore_global"
    end
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

zoxide init fish | source


# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init2.fish 2>/dev/null || :
alias claude="/Users/ryota.murakami/.claude/local/claude"

# uv
fish_add_path "/Users/ryota.murakami/.local/bin"
