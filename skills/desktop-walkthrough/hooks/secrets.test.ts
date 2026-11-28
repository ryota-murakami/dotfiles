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

test('an HTTP trace with a lower-case basic Authorization header has its credential found, digits or not', () => {
  // Arrange
  // base64 of a user and password, which has no digit
  const credential = ['dXNlcjpw', 'YXNzd29yZA=='].join('')
  const trace = `> GET /me HTTP/1.1\n> authorization: basic ${credential}\n`

  // Act
  const findings = findSecrets(trace)
  const masked = maskSecrets(trace)

  // Assert
  expect(findings.map((finding) => finding.pattern)).toEqual(['authorization-header'])
  expect(masked).toBe('> GET /me HTTP/1.1\n> authorization: basic •••\n')
})

test('a short Basic credential (twelve characters) is found and masked, while prose about Basic auth is not', () => {
  // Arrange
  // base64 of a nine-byte user:password, under the sixteen characters a Bearer token needs
  const credential = ['dTpwYXNz', 'd29yZA=='].join('').slice(0, 12)
  const trace = `> GET /me HTTP/1.1\n> Authorization: Basic ${credential}\n`
  const prose = 'Authorization: Basic auth sends base64(user:pass), never Authorization: Basic <credentials>.'

  // Act
  const findings = findSecrets(trace)
  const masked = maskSecrets(trace)
  const inProse = findSecrets(prose)

  // Assert
  expect(findings).toEqual([{ pattern: 'authorization-header', index: 21, line: 2 }])
  expect(masked).toBe('> GET /me HTTP/1.1\n> Authorization: Basic •••\n')
  expect(inProse).toEqual([])
})

test('capitalised prose after Basic and camelCase placeholders after Bearer are not taken for credentials', () => {
  // Arrange
  // The placeholders are assembled at run time, so a scanner reading this file sees no header value
  const placeholders = [['YourGitHub', 'TokenHere'].join(''), ['myPersonal', 'AccessToken'].join('')]
  const texts = [
    'Set Authorization: Basic Auth only over HTTPS.',
    'Authorization: Basic AuthData',
    `curl -H "Authorization: Bearer ${placeholders[0]}" https://api.test/me`,
    `Authorization: Bearer ${placeholders[1]}`,
  ]

  // Act
  const findings = texts.map((text) => findSecrets(text))

  // Assert
  expect(findings).toEqual([[], [], [], []])
})

test('a bearer token of letters alone is found, while prose about bearer tokens is not', () => {
  // Arrange
  const token = ['AbCdEfGhIj', 'KlMnOpQrSt'].join('')
  const header = `curl -H "Authorization: bearer ${token}" https://api.test/me`
  const prose = 'Bearer authentication sends a token in the header.'

  // Act
  const inHeader = findSecrets(header)
  const inProse = findSecrets(prose)

  // Assert
  expect(inHeader.map((finding) => finding.pattern)).toEqual(['authorization-header'])
  expect(inProse).toEqual([])
})

test('a signed link whose signature begins with an escaped + is found; a %s placeholder is not', () => {
  // Arrange
  const signed = `https://cdn.test/v.mp4?Expires=1&Signature=%2B${'0f3a'.repeat(8)}`
  const placeholder = 'https://cdn.test/v.mp4?Expires=1&Signature=%s'

  // Act
  const inSigned = findSecrets(signed)
  const inPlaceholder = findSecrets(placeholder)

  // Assert
  expect(inSigned.map((finding) => finding.pattern)).toEqual(['signed-url-parameter'])
  expect(inPlaceholder).toEqual([])
})

test('a long run of letters after Bearer is read in about the time it takes to read it, not its square', () => {
  // Arrange
  const text = `Authorization: Bearer ${'a'.repeat(120_000)}`
  const started = performance.now()

  // Act
  const findings = findSecrets(text)

  // Assert
  expect(findings).toEqual([])
  // gstack-timing-ok: the bound is the contract; the quadratic lookahead took about 7 s here, a linear read takes milliseconds
  expect(performance.now() - started).toBeLessThan(1500)
})

test('long dotted, hyphenated and sk- runs are read without rescanning the run at every boundary', () => {
  // Arrange
  const runs = ['a-'.repeat(150_000), 'a.'.repeat(150_000), 'sk-'.repeat(70_000)]
  const started = performance.now()

  // Act
  const findings = runs.flatMap((run) => findSecrets(run))

  // Assert
  expect(findings).toEqual([])
  // gstack-timing-ok: the bound is the contract; the unbounded scheme run and key lookahead took seconds per run
  expect(performance.now() - started).toBeLessThan(1500)
})

test('a text quoting thousands of keys reports each on its own line, in time that grows with the text', () => {
  // Arrange
  const lines = Array.from({ length: 40_000 }, () => `key: ${AWS_KEY_ID}`)
  const text = lines.join('\n')
  const started = performance.now()

  // Act
  const findings = findSecrets(text)

  // Assert
  expect(findings.length).toBe(40_000)
  expect(findings[0]).toEqual({ pattern: 'aws-access-key-id', index: 5, line: 1 })
  expect(findings[39_999]?.line).toBe(40_000)
  // gstack-timing-ok: the bound is the contract; checking every earlier finding and re-splitting the prefix took about 10 s here
  expect(performance.now() - started).toBeLessThan(1500)
})
