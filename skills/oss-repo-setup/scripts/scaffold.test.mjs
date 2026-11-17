import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'

import { scaffold, targetPathOf, valuesFor } from './scaffold.mjs'

/** Creates an empty git repository whose origin points at laststance/example. */
function makeRepository() {
  const directory = mkdtempSync(join(tmpdir(), 'oss-repo-setup-'))
  execFileSync('git', ['init', '--quiet'], { cwd: directory })
  execFileSync(
    'git',
    ['remote', 'add', 'origin', 'git@github.com:laststance/example.git'],
    { cwd: directory },
  )
  return directory
}

test('restores the leading dot of hidden template paths', () => {
  // Arrange
  const templatePath = 'dot-github/actions/prepare/action.yml'

  // Act
  const path = targetPathOf(templatePath)

  // Assert
  assert.equal(path, '.github/actions/prepare/action.yml')
})

test('fills owner, repository, project name and the maintainer flag from origin and package.json', () => {
  // Arrange
  const target = makeRepository()
  writeFileSync(join(target, 'package.json'), '{ "name": "example-lib" }')
  writeFileSync(join(target, '.node-version'), '24.20.0\n')

  // Act
  const values = valuesFor(target, { maintainer: 'octocat' })

  // Assert
  assert.deepEqual(values, {
    OWNER: 'laststance',
    REPO: 'example',
    PROJECT_NAME: 'example-lib',
    NODE_VERSION: '24.20.0',
    MAINTAINER: 'octocat',
  })
})

test('writes the CI group with workflows under .github', () => {
  // Arrange
  const target = makeRepository()

  // Act
  const results = scaffold({ group: 'ci', target, values: {} })

  // Assert
  assert.deepEqual(
    results.map(({ path }) => path),
    [
      '.coderabbit.yaml',
      '.github/actions/prepare/action.yml',
      '.github/workflows/build.yml',
      '.github/workflows/fallow.yml',
      '.github/workflows/format.yml',
      '.github/workflows/lint.yml',
      '.github/workflows/scorecard.yml',
      '.github/workflows/security.yml',
      '.github/workflows/socket.yml',
      '.github/workflows/test.yml',
      '.github/workflows/typecheck.yml',
      'codecov.yml',
    ],
  )
})

test('keeps an existing file unless forced, so repository edits survive', () => {
  // Arrange
  const target = makeRepository()
  writeFileSync(join(target, 'SECURITY.md'), '# Existing policy\n')

  // Act
  const results = scaffold({ group: 'docs', target, values: {} })

  // Assert
  const security = results.find(({ path }) => path === 'SECURITY.md')
  assert.equal(security.action, 'kept')
  assert.equal(
    readFileSync(join(target, 'SECURITY.md'), 'utf8'),
    '# Existing policy\n',
  )
})

test('lists placeholders that only a human can fill', () => {
  // Arrange
  const target = makeRepository()
  const values = {
    OWNER: 'laststance',
    REPO: 'example',
    PROJECT_NAME: 'Example',
    MAINTAINER: 'octocat',
  }

  // Act
  const results = scaffold({ group: 'docs', target, values })

  // Assert
  const security = results.find(({ path }) => path === 'SECURITY.md')
  assert.deepEqual(security.unresolved, [
    '{{DISTRIBUTION}}',
    '{{RUNTIME_MODEL}}',
  ])
  assert.match(
    readFileSync(join(target, 'SECURITY.md'), 'utf8'),
    /github\.com\/laststance\/example\/security\/advisories\/new/,
  )
})

test('writes nothing on a dry run', () => {
  // Arrange
  const target = makeRepository()

  // Act
  const results = scaffold({
    group: 'tooling',
    target,
    values: {},
    dryRun: true,
  })

  // Assert
  assert.ok(results.every(({ action }) => action === 'would write'))
  assert.throws(() => readFileSync(join(target, 'eslint.config.mjs')))
})
