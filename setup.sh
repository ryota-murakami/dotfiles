#!/bin/bash

#=========================================================
# ANSIColors
#=========================================================
GREEN="\033[0;32m"
BLUE="\033[0;34m"
RESET_COLOR="\033[0m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
BLACK_BOLD="\033[1;30m"
BG_GREEN="\033[42m"

#=========================================================
# Mac OSX Magic
#=========================================================
echo -e "${GREEN}Disabling press-and-hold for special characters...${RESET_COLOR}"
echo -e "${BLUE}Press-and-hold disabled.${RESET_COLOR}"

echo -e "${GREEN}Enabling visibility of hidden files in Finder...${RESET_COLOR}"
defaults write com.apple.finder AppleShowAllFiles TRUE
echo -e "${BLUE}Hidden files are now visible in Finder.${RESET_COLOR}"

echo -e "${GREEN}Enabling POSIX path in Finder title bar...${RESET_COLOR}"
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
echo -e "${BLUE}POSIX path is now shown in Finder title bar.${RESET_COLOR}"

echo -e "${GREEN}Restarting Finder...${RESET_COLOR}"
killall Finder
echo -e "${BLUE}Finder has been restarted.${RESET_COLOR}"
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true; killall Finder

#=========================================================
# Install essential tools from Brewfile
#=========================================================
echo -e "${GREEN}Starting .Brewfile installations...${RESET_COLOR}"
brew bundle
echo -e "\n${GREEN}.Brewfile install has just completed!!${RESET_COLOR}\n"
sleep 3s
#=========================================================
# Create Symlink
#=========================================================
echo -e "${GREEN}Creating symlinks for dotfiles...${RESET_COLOR}"
cd $HOME/dotfiles 
for f in .??*
do
    [[ "$f" =~ ^[^\.].* ]] && continue
    [[ "$f" == ".git" ]] && continue
    [[ "$f" == ".DS_Store" ]] && continue

    if [ -e "$HOME/$f" ]; then
        read -p "File $HOME/$f exists. Overwrite? (y/n) " -n 1 -r
        echo    # move to a new line
        if [[ ! $REPLY =~ ^[Yy]$ ]]
        then
            continue
        fi
    fi

    ln -sf $HOME/dotfiles/$f $HOME/$f

    echo -e "$Created {BLACK_BOLD}${BG_GREEN}${f}${RESET_COLOR} symlink."
done
echo -e "${BLACK_BOLD}${BG_GREEN}Symlink creation task completed!${RESET_COLOR}"
sleep 1s
#=========================================================
# Setup fish-shell (fish-shell is contained in Brewfile)
#=========================================================
grep -E "/usr/local/bin/fish" /etc/shells || echo "/usr/local/bin/fish" | sudo tee -a /etc/shells # If there is no fish in the shell listing file, add it to the end of the line.
chsh -s /usr/local/bin/fish

#=========================================================
# Finish
#=========================================================
sleep 0.5s

echo -e "\n"
echo -e "${GREEN}Setup has just completed!!${RESET_COLOR}"
