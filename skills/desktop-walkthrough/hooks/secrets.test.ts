import { expect, test } from 'claude-code/testing'
import { findSecrets, maskSecrets } from './secrets'

// Fake credentials are assembled at run time so secret scanners (gitleaks, gstack-redact) do not
// flag this public file; each one has the shape of the real thing.
const SIGNATURE = '0f3a'.repeat(16)
const GITHUB_TOKEN = ['ghp', 'y'.repeat(36)].join('_')
const AWS_KEY_ID = ['AKIA', 'Q'.repeat(16)].join('')
const PRIVATE_KEY = [
  ['-----BEGIN', 'RSA PRIVATE', 'KEY-----'].join(' '),
  'M'.repeat(64),
  ['-----END', 'RSA PRIVATE', 'KEY-----'].join(' '),
].join('\n')

test('the Handout export finds a signed link hidden behind harmless link text', () => {
  // Arrange
  const page = `# 設計\n\n詳しくは [設計メモ](https://docs.test/a?signature=${SIGNATURE}) を見てください。\n`

  // Act
  const findings = findSecrets(page)

  // Assert
  expect(findings).toEqual([{ pattern: 'signed-url-parameter', index: 37, line: 3 }])
})

test('the Handout export names the shape and line of a token, never the token itself', () => {
  // Arrange
  const page = `# 手順\n\n1. clone する\n2. git remote set-url origin https://${GITHUB_TOKEN}@github.com/o/r\n`

  // Act
  const findings = findSecrets(page)

  // Assert
  expect(findings).toEqual([{ pattern: 'prefixed-api-key', index: 55, line: 4 }])
  expect(JSON.stringify(findings)).not.toContain(GITHUB_TOKEN)
})

test('the Handout export finds a secret inside a diagram source', () => {
  // Arrange
  const page = ['# 構成', '', '```mermaid', 'flowchart LR', `  A[${AWS_KEY_ID}] --> B[S3]`, '```', ''].join('\n')

  // Act
  const findings = findSecrets(page)

  // Assert
  expect(findings).toEqual([{ pattern: 'aws-access-key-id', index: 34, line: 5 }])
})

test('a private key is reported once, not once for every shape that matches it', () => {
  // Arrange
  const page = `鍵は次のとおりです。\n\n${PRIVATE_KEY}\n`

  // Act
  const findings = findSecrets(page)

  // Assert
  expect(findings).toEqual([{ pattern: 'private-key', index: 12, line: 3 }])
})

test('a page that only says where a secret comes from exports without findings', () => {
  // Arrange
  const page = [
    '# 設定',
    '',
    '```sh',
    'export API_TOKEN="$(op read op://vault/api/token)"',
    'curl -H "Authorization: Bearer $API_TOKEN" https://api.test/me',
    '```',
    '',
  ].join('\n')

  // Act
  const findings = findSecrets(page)

  // Assert
  expect(findings).toEqual([])
})

test('the export finds exactly the values the mirror masks', () => {
  // Arrange
  const text = [
    `open 'https://app.test/verify?expires=1&signature=${SIGNATURE}'`,
    `git push https://${GITHUB_TOKEN}@github.com/o/r`,
    'POSTGRES_PASSWORD=postgres psql',
  ].join('\n')

  // Act
  const findings = findSecrets(text)
  const masked = maskSecrets(text)

  // Assert
  expect(findings.map((finding) => finding.pattern)).toEqual(['signed-url-parameter', 'prefixed-api-key'])
  expect(masked.split('•••').length - 1).toBe(2)
})

test('the example in the finder documentation holds', () => {
  // Arrange
  const text = `[設計メモ](https://docs.test/a?signature=${'0f3a'.repeat(16)})`

  // Act
  const findings = findSecrets(text)

  // Assert
  expect(findings).toEqual([{ pattern: 'signed-url-parameter', index: 26, line: 1 }])
})
