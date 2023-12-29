#!/bin/bash

#=========================================================
# Mac OSX Magic
#=========================================================
defaults write -g ApplePressAndHoldEnabled -bool false
defaults write com.apple.finder AppleShowAllFiles TRUE
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true; killall Finder
# Key Repeat(Don't need anymore recent OSX)
#defaults write -g InitialKeyRepeat -int 10
#defaults write -g KeyRepeat -int 1
# @TODO Add finished message with seelptime

#=========================================================
# Install essential tools from Brewfile
#=========================================================
brew bundle
echo -e "\n"
echo -e "\033[32mbrew install form Brewfile has just completed!!"
sleep 3s
#=========================================================
# Create Symlink
#=========================================================
# @TODO Add what start task message with seelptime
cd $HOME/dotfiles 
for f in .??*
do
    [[ "$f" =~ ^[^\.].* ]] && continue
    [[ "$f" == ".git" ]] && continue
    [[ "$f" == ".DS_Store" ]] && continue

    ln -sf $HOME/dotfiles/$f $HOME/$f

    echo "${f} setup successfully."
done
# @TODO Add finish task message with seelptime
#=========================================================
# Setup fish-sell (fish-shell is contained in Brewfile)
#=========================================================
grep -E "/usr/local/bin/fish" /etc/shells || echo "/usr/local/bin/fish" | sudo tee -a /etc/shells # If there is no fish in the shell listing file, add it to the end of the line.
chsh -s /usr/local/bin/fish

#=========================================================
# Finish
#=========================================================
sleep 0.5s

echo -e "\n"
echo -e "\033[32mSetup has just completed!!"
