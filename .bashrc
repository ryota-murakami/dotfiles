[ -f ~/.fzf.bash ] && source ~/.fzf.bash
eval "$(pyenv init -)"
. "$HOME/.cargo/env"
source ~/.bash_completion/alacritty

[[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path bash)"
