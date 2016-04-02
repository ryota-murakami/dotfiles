#!/bin/bash

function usage() {
cat <<_EOT_
Usage:
    $0
Description:
    Install Homebrew.
Options:
    There is no option.
_EOT_
exit 1
}

if [[ "$OPTIND" = 1 ]]; then
    while getopts h OPT
    do
        case $OPT in
            h)
                usage
                ;;
            \?)
                echo "Try to enter the h option." 1>&2
                ;;
        esac
    done
else
    echo "No installed getopts-command." 1>&2
    exit 1
fi

# Main
[[ $DOTFILES_DIR == "" ]] && source "$HOME/dotfiles/scripts/directory_variables.sh"

if [[ ! -x $(which brew) ]]; then
    # Install Homebrew
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    # Enable brewdle
    brew tap Homebrew/brewdler
    # Install Brewfile contain packages
    cd $DOTFILES_DIR
    brew brewdle
else
    echo "brew has been installd."
fi
