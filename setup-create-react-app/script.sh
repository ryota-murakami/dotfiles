#!/bin/bash
if [[ -z $1 ]]; then
    echo 'need repository name string as first argument!'
    exit 1
fi

SCRIPT_DIR=$(cd $(dirname $0); pwd)

npx create-react-app $1 --template typescript

cd ./$1

yarn add -D eslint-config-prettier eslint-config-typescript eslint-plugin-prettier prettier

cp $SCRIPT_DIR/.eslintrc .eslintrc
cp $SCRIPT_DIR/.eslintignore .eslintignore
cp $SCRIPT_DIR/.prettierrc .prettierrc
cp $SCRIPT_DIR/.prettierignore .prettierignore
cp $SCRIPT_DIR/.env .env

