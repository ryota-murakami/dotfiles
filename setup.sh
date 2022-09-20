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
grep -E "/usr/local/bin/fish" /etc/shells || echo "/usr/local/bin/fish" | sudo tee -a /etc/shells # シェルの一覧ファイルにfishが無ければ行末に追記
chsh -s /usr/local/bin/fish

#=========================================================
# Setup neobundle.vim
#=========================================================
git submodule init
git submodule update

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
