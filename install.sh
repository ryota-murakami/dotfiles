#!/bin/bash

# Main
source "./scripts/directory_variables.sh" && echo -e "\n\n"

# Create Symlink
[[ -f "$SCRIPTS_DIR/create_symlink.sh" ]] && source "$SCRIPTS_DIR/create_symlink.sh" && echo -e "\n\n"

# Homebrew Install
[[ -f "$SCRIPTS_DIR/brew_install.sh" ]] && source "$SCRIPTS_DIR/brew_install.sh" && echo -e "\n\n"

# Finish
sleep 0.5s

echo "Setup dotfiles is now complete!!"
echo -e "\n\n"

