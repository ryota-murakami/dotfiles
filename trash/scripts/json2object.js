#!/usr/bin/env node
// @TODO terminal can't handle multiple line json without "\" how to handle it jq?
// I have to change read file base implementation
const json = process.argv[2]
console.log(json)
console.log()
console.log()
console.log()
console.log(JSON.parse(json))
console.log()
console.log()
