#!/bin/bash

for f in .??*
do
    [[ "$f" =~ ^[^\.].* ]] && continue
    [[ "$f" == ".git" ]] && continue
    [[ "$f" == ".DS_Store" ]] && continue
    [[ -e ~/${f} ]] && echo "${f} already exists." && continue

    ln -s ./dotfiles/$f $HOME/$f

    echo "${f} setup successfully."
done

sleep 0.5s

echo -e "\n"
echo "Setup dotfiles is now complete!!"
echo -e "\n"

