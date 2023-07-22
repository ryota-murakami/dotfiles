#!/bin/bash

#=========================================================
# Mac OSX Magic
#=========================================================
defaults write -g ApplePressAndHoldEnabled -bool false
defaults write com.apple.finder AppleShowAllFiles TRUE
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true; killall Finder
# Key Repeat
#defaults write -g InitialKeyRepeat -int 10
#defaults write -g KeyRepeat -int 1


#=========================================================
# Install essential tools from Brewfile
#=========================================================
brew bundle

#=========================================================
# Create Symlink
#=========================================================
cd $HOME/dotfiles 
for f in .??*
do
    [[ "$f" =~ ^[^\.].* ]] && continue
    [[ "$f" == ".git" ]] && continue
    [[ "$f" == ".DS_Store" ]] && continue
    [[ -e $HOME/$f ]] && echo "${f} is already exists." && continue

    ln -s $HOME/dotfiles/$f $HOME/$f

    echo "${f} setup successfully."
done

#=========================================================
# Setup fish-sell (fish-shell is contained in Brewfile)
#=========================================================
grep -E "/usr/local/bin/fish" /etc/shells || echo "/usr/local/bin/fish" | sudo tee -a /etc/shells # If there is no fish in the shell listing file, add it to the end of the line.
chsh -s /usr/local/bin/fish

#=========================================================
# Install Bundler
#=========================================================
gem install bundler

#=========================================================
# Finish
#=========================================================
sleep 0.5s

echo -e "\n"
echo -e "\033[32mSetup has just completed!!"
