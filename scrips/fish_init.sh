#!/bin/bash

password(){
    if ! ${password+:} false
    then
        printf "password: "
        read -s password
    fi
}

# シェルの一覧ファイルにfishが無ければ行末に追記
grep -E "/usr/local/bin/fish" /etc/shells || echo "/usr/local/bin/fish" | sudo tee -a /etc/shells

chsh -s /usr/local/bin/fish
