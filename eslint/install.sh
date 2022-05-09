#!/bin/bash

SCRIPT_DIR=$(cd $(dirname $0); pwd)

yarn add -D eslint eslint-config-prettier eslint-config-typescript eslint-plugin-prettier prettier @typescript-eslint/eslint-plugin @typescript-eslint/parser eslint-plugin-import eslint-plugin-jsx-a11y eslint-plugin-react-hooks eslint-import-resolver-typescript eslint-plugin-sort-keys-fix

cp $SCRIPT_DIR/.eslintrc .eslintrc
cp $SCRIPT_DIR/.eslintignore .eslintignore
cp $SCRIPT_DIR/.prettierrc .prettierrc
cp $SCRIPT_DIR/.prettierignore .prettierignore
