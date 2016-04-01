#!/bin/bash

DOTFILES_DIR=$(cd $(dirname $(readlink $BASH_SOURCE || echo $BASH_SOURCE))/..;pwd)
SCRIPTS_DIR=$DOTFILES_DIR/scripts
