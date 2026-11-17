#!/usr/bin/env node
/**
 * Copies one group of oss-repo-setup templates into a target repository.
 *
 * Why: the templates live under `assets/<group>/` with `dot-` standing in for a leading dot,
 * so hidden files survive skill publishing. This script restores the real paths, fills the
 * placeholders it can derive, keeps existing files, and lists what still needs a human.
 * Called by the agent once per commit-sized group: tooling, then ci, then docs.
 *
 * Usage: node scaffold.mjs --group <tooling|ci|docs> [--target dir] [--owner o] [--repo r]
 *        [--name "Project"] [--maintainer login] [--skip path]... [--force] [--dry-run]
 */
import { execFileSync } from 'node:child_process'
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  writeFileSync,
} from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'

const assetsRoot = fileURLToPath(new URL('../assets/', import.meta.url))
const groups = ['tooling', 'ci', 'docs']
const placeholderPattern = /\{\{[A-Z_]+\}\}/g

/** Lists every file under a directory as paths relative to it, ordered by their repository path. */
function filesUnder(directory) {
  return readdirSync(directory, { withFileTypes: true, recursive: true })
    .filter((entry) => entry.isFile())
    .map((entry) => relative(directory, join(entry.parentPath, entry.name)))
    .sort((a, b) => targetPathOf(a).localeCompare(targetPathOf(b), 'en'))
}

/**
 * Turns a template path into the repository path it stands for.
 *
 * @example targetPathOf('dot-github/workflows/test.yml') === '.github/workflows/test.yml'
 */
export function targetPathOf(templatePath) {
  return templatePath
    .split(/[\\/]/)
    .map((segment) => segment.replace(/^dot-/, '.'))
    .join('/')
}

/** Reads a command's trimmed output, or undefined when it fails (no git, no remote). */
function outputOf(command, args, cwd) {
  try {
    return execFileSync(command, args, { cwd, encoding: 'utf8' }).trim()
  } catch {
    return undefined
  }
}

/** Reads a JSON file, or undefined when it is missing. */
function jsonOf(path) {
  return existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : undefined
}

/**
 * Derives placeholder values from the target repository, letting flags override each one.
 *
 * @example with origin git@github.com:laststance/foo.git → { OWNER: 'laststance', REPO: 'foo', ... }
 */
export function valuesFor(target, flags) {
  const origin = outputOf('git', ['remote', 'get-url', 'origin'], target) ?? ''
  const [, owner, repo] =
    /github\.com[:/]([^/]+)\/(.+?)(?:\.git)?$/.exec(origin) ?? []
  const manifest = jsonOf(join(target, 'package.json')) ?? {}
  const nodeVersionFile = join(target, '.node-version')
  const values = {
    OWNER: flags.owner ?? owner,
    REPO: flags.repo ?? repo,
    PROJECT_NAME:
      flags.name ?? manifest.displayName ?? manifest.name ?? flags.repo ?? repo,
    NODE_VERSION: existsSync(nodeVersionFile)
      ? readFileSync(nodeVersionFile, 'utf8').trim()
      : undefined,
    // The signed-in gh account maintains the repository unless a flag names someone else.
    MAINTAINER:
      flags.maintainer ?? outputOf('gh', ['api', 'user', '--jq', '.login'], target),
  }
  // An underivable value stays a placeholder, so it shows up in the manual list.
  return Object.fromEntries(
    Object.entries(values).filter(([, value]) => value !== undefined),
  )
}

/** Replaces every known {{KEY}} in a template's text. */
function fill(text, values) {
  return text.replaceAll(placeholderPattern, (token) => {
    const key = token.slice(2, -2)
    return values[key] ?? token
  })
}

/**
 * Copies one template group and returns what happened to each file.
 *
 * @example scaffold({ group: 'ci', target: '/repo', values }) →
 *   [{ path: '.github/workflows/test.yml', action: 'written', unresolved: [] }, ...]
 */
export function scaffold({ group, target, values, skip = [], force, dryRun }) {
  const groupRoot = join(assetsRoot, group)
  return filesUnder(groupRoot).map((templatePath) => {
    const path = targetPathOf(templatePath)
    const destination = join(target, path)
    if (skip.includes(path)) return { path, action: 'skipped', unresolved: [] }
    // Never clobber the repository's own version unless asked; the agent merges by hand.
    if (existsSync(destination) && !force)
      return { path, action: 'kept', unresolved: [] }
    const text = fill(
      readFileSync(join(groupRoot, templatePath), 'utf8'),
      values,
    )
    const unresolved = [...new Set(text.match(placeholderPattern) ?? [])]
    if (!dryRun) {
      mkdirSync(dirname(destination), { recursive: true })
      writeFileSync(destination, text)
    }
    return { path, action: dryRun ? 'would write' : 'written', unresolved }
  })
}

/** Prints the per-file result and the placeholders the agent still has to fill. */
function report(results) {
  for (const { path, action } of results)
    process.stdout.write(`${action.padEnd(11)} ${path}\n`)
  const manual = results.filter(({ unresolved }) => unresolved.length > 0)
  if (manual.length === 0) return
  process.stdout.write('\nFill manually:\n')
  for (const { path, unresolved } of manual)
    process.stdout.write(`  ${path}: ${unresolved.join(' ')}\n`)
}

/** Parses the command line, runs one group, and reports. */
function main() {
  const { values: flags } = parseArgs({
    options: {
      group: { type: 'string' },
      target: { type: 'string', default: process.cwd() },
      owner: { type: 'string' },
      repo: { type: 'string' },
      name: { type: 'string' },
      maintainer: { type: 'string' },
      skip: { type: 'string', multiple: true, default: [] },
      force: { type: 'boolean', default: false },
      'dry-run': { type: 'boolean', default: false },
    },
  })
  if (!groups.includes(flags.group)) {
    process.stderr.write(`--group must be one of: ${groups.join(', ')}\n`)
    process.exitCode = 1
    return
  }
  const target = resolve(flags.target)
  report(
    scaffold({
      group: flags.group,
      target,
      values: valuesFor(target, flags),
      skip: flags.skip,
      force: flags.force,
      dryRun: flags['dry-run'],
    }),
  )
}

// Run only as a CLI, so the test file can import the functions.
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
)
  main()
