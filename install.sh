#!/bin/bash

function abort() {
    echo "$@" 1>&2
    exit 1
}

# Main
if [ -f "./scripts/directory_variables.sh" ]; then
    source "./scripts/directory_variables.sh" && echo -e "\n\n"
else
    abort "no such directory_variables.sh"
fi

# Create Symlink
if [[ -f "$SCRIPTS_DIR/create_symlink.sh" ]]; then
    source "$SCRIPTS_DIR/create_symlink.sh" && echo -e "\n\n"
else
    abort "no such create_symlink.sh"
fi

# Homebrew Install
if [[ -f "$SCRIPTS_DIR/brew_install.sh" ]]; then
    source "$SCRIPTS_DIR/brew_install.sh" && echo -e "\n\n"
else
    abort "no such brew_install.sh"
fi

# Fishshell Setup
if [[ -f "$SCRIPTS_DIR/fish_init.sh" ]]; then
    source "$SCRIPTS_DIR/fish_init.sh" && echo -e "\n\n"
else
    abort "no such fish_init.sh"
fi

# 本当はここでrbenvの設定処理を入れたいが、現状上手くshell scriptが動作しないﾐ(´┏ω┓｀)/

# Gem install
sudo gem install bundle
sudo bundle install

# Contain Submodules... {"neobundle.vim"}
git submodule init
git submodule update

sudo composer global install

# Finish
sleep 0.5s

echo "Setup dotfiles is now complete!!"
echo -e "\n\n"
:
