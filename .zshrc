# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git zsh-syntax-highlighting zsh-autosuggestions)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
alias zshconfig="mate ~/.zshrc"
alias ohmyzsh="mate ~/.oh-my-zsh"
alias c clear
alias chrome /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --guest
alias clone 'cd ~/clone'
alias dotfiles 'cd ~/dotfiles'
alias exp 'cd ~/react-experimental-workspace'
alias fork 'cd ~/fork'
alias geek 'cd ~/laststance/geek-infiltration'
alias home 'cd ~'
alias last 'cd ~/laststance'
alias lf perl -pe 's/n/nn/g'
alias npbp npm outdated | grep -v Package | awk '{print $1}' | xargs -I% npm install --force %@latest
alias nsx 'cd ~/nsx'
alias pr '~/pr'
alias repo 'cd ~/repository'
alias utils 'cd ~/utils'
alias v8 '/Applications/Chromium.app/Contents/MacOS/Chromium --auto-open-devtools-for-tabs'
alias vi /usr/bin/vim
alias vscode-conf-dir cd /Users/ryota.murakami/Library/Application Support/Code/User
alias wanip 'curl https://ipinfo.io/ip'

# Fish shellから移植された環境変数
export LSCOLORS="CxGxBxDxCxEgEdxbxgxcxd"
export EZA_COLORS="di=1;32"
export LESS="-R"

# FZF設定（Fish shellから移植）
export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"

# ツール設定（Fish shellから移植）
export VOLTA_HOME="$HOME/.volta"
export PNPM_HOME="/Users/ryota.murakami/Library/pnpm"
export BUN_INSTALL="$HOME/.bun"

# Enabile autocomplete
autoload -U compinit; compinit

# PATH（Fish shellの設定に合わせて更新）
export PATH="$HOME/.cargo/bin:$HOME/nvim-macos/bin:$VOLTA_HOME/bin:$PNPM_HOME:$BUN_INSTALL/bin:/usr/local/sbin:$HOME/.local/bin:$PATH"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# ツール初期化（Fish shellから移植）
eval "$(direnv hook zsh)"
eval "$(pyenv init -)"
eval "$(zoxide init zsh)"

 source $ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

[[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"
