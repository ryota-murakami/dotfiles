#!/bin/bash

# Create Symlink
cd $HOME/dotfiles 
for f in .??*
do
    [[ "$f" =~ ^[^\.].* ]] && continue
    [[ "$f" == ".git" ]] && continue
    [[ "$f" == ".DS_Store" ]] && continue
    [[ -e $HOME/$f ]] && echo "${f} already exists." && continue

    ln -s $HOME/dotfiles/$f $HOME/$f

    echo "${f} setup successfully."
done

# Homebrew Install
if [[ ! -x $(which brew) ]]; then
    # Install Homebrew
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    # Enable brewdle
    brew tap Homebrew/brewdler
    # Install Brewfile contain packages
    cd $HOME/dotfiles 
    brew brewdle
else
    echo "brew has been installd."
fi

# Fish Setup
grep -E "/usr/local/bin/fish" /etc/shells || echo "/usr/local/bin/fish" | sudo tee -a /etc/shells # シェルの一覧ファイルにfishが無ければ行末に追記
chsh -s /usr/local/bin/fish

# Contain Submodules... {"neobundle.vim"}
git submodule init
git submodule update

# Install Bundler
gem install bundler

# Install Composer Global Package.(Installed Composer From brew)
sudo composer global install

# Finish
sleep 0.5s

echo "\e[32mSetup dotfiles is now complete!!"
echo -e "\n\n"
