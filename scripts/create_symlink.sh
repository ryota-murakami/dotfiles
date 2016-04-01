#!/bin/bash

function usage() {
cat <<_EOT_
Usage:
    $0
Description:
    Create symlink starting from "." files to home directory.
Options:
    There is no option.
_EOT_
exit 1
}

if [ "$OPTIND" = 1 ]; then
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

# Main
[[ $DOTFILES_DIR == "" ]] && source "directory_variables.sh"
cd $DOTFILES_DIR
for f in .??*
do
    [[ "$f" =~ ^[^\.].* ]] && continue
    [[ "$f" == ".git" ]] && continue
    [[ "$f" == ".DS_Store" ]] && continue
    [[ -e $HOME/$f ]] && echo "${f} already exists." && continue

    ln -s $DOTFILES_DIR/$f $HOME/$f

    echo "${f} setup successfully."
done


