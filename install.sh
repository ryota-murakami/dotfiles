#!/bin/bash

for f in .??*
do
    [[ "$f" =~ ^[^\.].* ]] && continue
    [[ "$f" == ".git" ]] && continue
    [[ "$f" == ".DS_Store" ]] && continue

    ln -s ./dotfiles/$f $HOME/$f

    echo "${f} is already setup!!"
done

sleep 0.5s

echo -e "\n"
echo "Complete dotfiles setup!!"
echo -e "\n"

