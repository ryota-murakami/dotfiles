#! /usr/bin/env node

const chalk = require('chalk')
const argv = require('yargs')
const log = console.log
const execSync = require('child_process').execSync
const fs = require('fs')
const jsonFormat = require('json-format')
const CONFIG_FILE_DIR = '/configFiles'

// CLI Interface =========================================================================

const explain = `
$ yarn global add mycra
$ npx create-react-app app
$ cd app
$ mycra
`

   argv
  .usage('Usage: $0')
  .example(explain)
  .help('h')
  .alias('h', 'help')
  .option()
  .epilog('copyright 2018 Ryota Murakami <dojce1048@gmail.com>')
  .argv;

// CLI Interface END =====================================================================

// Main =========================================================================

  execSync('yarn eject', {stdio:[0,1,2]})
  execSync('yarn add -D eslint-plugin-prettier prettier flow-bin', {stdio:[0,1,2]})
  execSync('yarn add emotion react-emotion babel-plugin-emotion', {stdio:[0,1,2]})

  fs.copyFileSync(__dirname + CONFIG_FILE_DIR + '/.babelrc', './.babelrc')
  fs.copyFileSync(__dirname + CONFIG_FILE_DIR + '/.eslintrc', './.eslintrc')
  fs.copyFileSync(__dirname + CONFIG_FILE_DIR + '/.eslintignore', './.eslintignore')
  fs.copyFileSync(__dirname + CONFIG_FILE_DIR + '/.flowconfig', './.flowconfig')

  const text = fs.readFileSync('package.json', 'utf8')
  const obj = JSON.parse(text)
  delete obj.babel
  /* prettier-ignore */
  fs.writeFileSync('package.json', jsonFormat(obj, { type: 'space' }), 'utf8')

  fs.chmodSync('config/webpack.config.dev.js', 0o777)
  fs.chmodSync('config/webpack.config.prod.js', 0o777)
  execSync("cat config/webpack.config.dev.js | sed -i.bak -e '/babelrc: false,/d' config/webpack.config.dev.js && rm config/webpack.config.dev.js.bak", {stdio:[0,1,2]})
  execSync("cat config/webpack.config.prod.js | sed -i.bak -e '/babelrc: false,/d' config/webpack.config.prod.js && rm config/webpack.config.prod.js.bak", {stdio:[0,1,2]})
  execSync('node_modules/.bin/eslint src --fix', {stdio:[0,1,2]})

  log(chalk.green.bold('mycra completed!'))
