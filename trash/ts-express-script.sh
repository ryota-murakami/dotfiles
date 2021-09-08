#!/bin/bash

SCRIPT_DIR=$(cd $(dirname $0); pwd)

yarn add express cors
yarn add -D @types/express @types/cors typescript nodemon ts-node ts-node-dev
  