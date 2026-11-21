import { expect, test } from 'claude-code/testing'
import { classifyTool, maskSecrets, showsToolOnBar } from './register'

// Fake credentials are assembled at run time so secret scanners (gitleaks, gstack-redact) do not
// flag this public file; each one has the shape of the real thing.
const SIGNATURE = '0123456789abcdef'.repeat(4)
const TOKEN = ['abcdefgh', 'ijklmnop', 'qrstuvwx'].join('')
const ANTHROPIC_KEY = ['sk', 'ant', 'api03', 'x'.repeat(32)].join('-')
const GITHUB_TOKEN = ['ghp', 'y'.repeat(36)].join('_')

test('the mirror hides the signature of a signed verification link', () => {
  // Arrange
  const command = `open 'https://app.test/email/verify/1/abc?expires=1&signature=${SIGNATURE}'`

  // Act
  const shown = maskSecrets(command)

  // Assert
  expect(shown).toBe("open 'https://app.test/email/verify/1/abc?expires=1&signature=•••'")
})

test('the mirror hides a bearer token written into a curl command', () => {
  // Arrange
  const command = `curl -H 'Authorization: Bearer ${TOKEN}' https://api.test/me`

  // Act
  const shown = maskSecrets(command)

  // Assert
  expect(shown).toBe("curl -H 'Authorization: Bearer •••' https://api.test/me")
})

test('the mirror keeps a command that reads its token from 1Password readable', () => {
  // Arrange
  const command = `API_TOKEN="$(op read 'op://Personal/item/credential')" && curl -H "Authorization: Bearer $API_TOKEN" https://api.test/me`

  // Act
  const shown = maskSecrets(command)

  // Assert
  expect(shown).toBe(command)
})

test('the mirror hides an Anthropic API key but keeps its prefix', () => {
  // Arrange
  const text = `export ANTHROPIC_KEY_FILE=/dev/null; echo ${ANTHROPIC_KEY}`

  // Act
  const shown = maskSecrets(text)

  // Assert
  expect(shown).toBe('export ANTHROPIC_KEY_FILE=/dev/null; echo sk-ant-•••')
})

test('the mirror hides a GitHub token pasted into a remote URL', () => {
  // Arrange
  const command = `git remote set-url origin https://${GITHUB_TOKEN}@github.com/acme/app.git`

  // Act
  const shown = maskSecrets(command)

  // Assert
  expect(shown).toBe('git remote set-url origin https://ghp_•••@github.com/acme/app.git')
})

test('the mirror hides the value of a password variable and keeps its name', () => {
  // Arrange
  const command = 'PGPASSWORD=engawa-local-only psql -h 127.0.0.1 -p 55432'

  // Act
  const shown = maskSecrets(command)

  // Assert
  expect(shown).toBe('PGPASSWORD=••• psql -h 127.0.0.1 -p 55432')
})

test('the mirror leaves commit hashes and ordinary commands unchanged', () => {
  // Arrange
  const command = 'git show 85c2a72f1e0b9d3c4a5b6c7d8e9f0a1b2c3d4e5f --stat && php artisan test --filter=Chapter10'

  // Act
  const shown = maskSecrets(command)

  // Assert
  expect(shown).toBe(command)
})

test('the bar keeps the narration while the agent only reads a file', () => {
  // Arrange
  const tool = 'Read'

  // Act
  const shown = showsToolOnBar(tool, false, false)

  // Assert
  expect(shown).toBe(false)
})

test('the bar keeps the question the person has yet to answer', () => {
  // Arrange
  const questionPending = true

  // Act
  const shown = showsToolOnBar('Bash', false, questionPending)

  // Assert
  expect(shown).toBe(false)
})

test('the bar shows a command the agent runs without narrating', () => {
  // Arrange
  const tool = 'Bash'

  // Act
  const shown = showsToolOnBar(tool, false, false)

  // Assert
  expect(shown).toBe(true)
})

test('the bar says the skill is being updated while a HUD source file is edited', () => {
  // Arrange
  const input = { file_path: '/Users/someone/dotfiles/skills/desktop-walkthrough/hud/Bar.swift' }

  // Act
  const toolClass = classifyTool('Edit', input)

  // Assert
  expect(toolClass).toBe('skill')
})

test('the bar says the skill is being updated while the HUD is built', () => {
  // Arrange
  const input = { command: 'cd ~/dotfiles/skills/desktop-walkthrough && swiftc hud/*.swift -o /tmp/x/StatusHUD' }

  // Act
  const toolClass = classifyTool('Bash', input)

  // Assert
  expect(toolClass).toBe('skill')
})

test('running the dw helper is not taken for updating the skill', () => {
  // Arrange
  const input = { command: '~/.claude/skills/desktop-walkthrough/scripts/dw say "次の場所を開きます"' }

  // Act
  const toolClass = classifyTool('Bash', input)

  // Assert
  expect(toolClass).toBe('other')
})

test('the bar says waiting while a question blocks the turn', () => {
  // Arrange
  const input = { command: 'DW_ASK_WAIT=600 $DW wait-user "解説を読んでください" --ok "次へ"' }

  // Act
  const toolClass = classifyTool('Bash', input)

  // Assert
  expect(toolClass).toBe('waiting')
})

test('a question left waiting in the background does not count as waiting', () => {
  // Arrange
  const input = { command: '$DW wait-user "解説を読んでください"', run_in_background: true }

  // Act
  const toolClass = classifyTool('Bash', input)

  // Assert
  expect(toolClass).toBe('other')
})

test('looking at a file outside the skill keeps the state already shown', () => {
  // Arrange
  const input = { file_path: '/tmp/screenshot.png' }

  // Act
  const toolClass = classifyTool('Read', input)

  // Assert
  expect(toolClass).toBeUndefined()
})
