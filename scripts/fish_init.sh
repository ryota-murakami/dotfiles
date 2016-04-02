#!/bin/bash

function usage() {
cat <<_EOT_
Usage:
    $0
Description:
    Enable fish shell. And switch default shell to fish.
Options:
    There is no option.
_EOT_
exit 1
}

if [[ "$OPTIND" = 1 ]]; then
    while getopts h OPT
    do
        case $OPT in
            h)
                usage
                ;;
            \?)
                echo "Try to enter the h option." 1>&2
                ;;
        esac
    done
else
    echo "No installed getopts-command." 1>&2
    exit 1
fi

# /etc/shellsの書き換え時、sudoを使うのでそのパスワードをターミナルで入力して取得する
password(){
    if ! ${password+:} false
    then
        printf "password: "
        read -s password
    fi
}

# Main
# シェルの一覧ファイルにfishが無ければ行末に追記
grep -E "/usr/local/bin/fish" /etc/shells || echo "/usr/local/bin/fish" | sudo tee -a /etc/shells

chsh -s /usr/local/bin/fish
