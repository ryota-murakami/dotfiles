#!/bin/bash

# Main
source "./scripts/directory_variables.sh"

# Create Symlink
[[ -f "$SCRIPTS_DIR/create_symlink.sh" ]] && source "$SCRIPTS_DIR/create_symlink.sh"

# Finish
sleep 0.5s

echo -e "\n"
echo "Setup dotfiles is now complete!!"
echo -e "\n"

