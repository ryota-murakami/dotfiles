#!/bin/bash

for f in .??*
do
    [[ "$f" =~ ^[^\.].* ]] && continue
    [[ "$f" == ".git" ]] && continue
    [[ "$f" == ".DS_Store" ]] && continue
    cd ~
    [[ -e "$f" ]] && echo "${f} already exists." && continue

    ln -s ./dotfiles/$f $HOME/$f

    echo "${f} setup successfully!!"
done

sleep 0.5s

echo -e "\n"
echo "Completed dotfiles setup!!"
echo -e "\n"

