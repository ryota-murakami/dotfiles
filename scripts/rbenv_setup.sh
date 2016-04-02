#!/bin/bash

function usage() {
cat <<_EOT_
Usage:
    $0
Description:
    Setup buildin ruby to rbenv.
    This script depend 'rbenv' 'ruby-build'
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
eval "$(rbenv init -)"
rbenv install 2.3.0
rbenv global 2.3.0
ruby -v
