#!/bin/bash

SCRIPT_DIR=$(cd $(dirname $0); pwd)

yarn add -D eslint-config-prettier eslint-config-typescript eslint-plugin-prettier prettier eslint-config-react-app @typescript-eslint/eslint-plugin @typescript-eslint/parser babel-eslint eslint eslint-plugin-flowtype eslint-plugin-import eslint-plugin-jsx-a11y eslint-plugin-react eslint-plugin-react-hooks

cp $SCRIPT_DIR/.eslintrc .eslintrc
cp $SCRIPT_DIR/.eslintignore .eslintignore
cp $SCRIPT_DIR/.prettierrc .prettierrc
cp $SCRIPT_DIR/.prettierignore .prettierignore
