/**
 * Secrets never reach the HUD: every text the Bridge writes for it passes {@link maskSecrets}. They
 * never reach a Handout either: `dw handout` stops on any {@link findSecrets} finds in a page.
 *
 * Why it is a file of its own: the feed, the status line and the Mirror's documents are written by
 * different parts of the Bridge, and all of them must hide the same values the same way; the Handout
 * builder (packages/handout) bundles this file at build time, so an export refuses what the Mirror hides.
 *
 * The shapes are those of the `secret-guard` plugin (github.com/laststance/claude-plugins, the file
 * plugins/secret-guard/hooks/constants.ts). That plugin keeps the same values out of the conversation
 * itself: it refuses a shell command that spells one out and masks them in what tools return, so with
 * it installed most of what reaches the Bridge is masked already. What the person types is not, and
 * not everyone has the plugin, so the Bridge masks on its own. A hooks module may import only its
 * own files: the list here is a copy, and a change to one is made in the other too.
 */

/** What a masked value is replaced with. A prefix or a name that says what it was stays in front of it. */
const MASK = '•••'

/** A value that stands for a secret without being one: a variable, a command substitution, a placeholder. */
const REFERENCE = '(?![$`{<%])'

/**
 * A name that ends in `token` and is no secret: the place to continue a listing from
 * (`nextPageToken`, `continuation_token`, `sync-token`).
 */
const NOT_A_PAGE_TOKEN = '(?![A-Za-z0-9_.-]*(?:page|next|continuation|cursor|sync)[_-]?token\\b)'

/** The characters a value takes in a link's query. Anything else (a bracket, a pipe) is code, not a link. */
const URL_VALUE = '[A-Za-z0-9._~%+/=-]'

/**
 * The characters of a value that only its variable's name gives away. A bracket, a dot or a backslash
 * means the text is code, which is shown as it is.
 */
const NAMED_VALUE = '[A-Za-z0-9_+/=~@%!^#*-]'

/** A value that looks made by a machine: it has a letter and a digit. Words such as `postgres` or `changeme` do not. */
const mixed = (chars: string) => `(?=${chars}*\\d)(?=${chars}*[A-Za-z])`

/**
 * A value in a link's query that stands for a secret without being one. A `%` followed by two
 * hexadecimal digits is an escaped character of the value itself (`%2B` is `+`, which a signature
 * may begin with); any other `%` starts a placeholder (`%s`, `%TOKEN%`).
 */
const URL_REFERENCE = '(?![$`{<]|%(?![0-9A-Fa-f]{2}))'

/** The characters of an Authorization header's credential. */
const CREDENTIAL = '[A-Za-z0-9._~+/=-]'

/**
 * A credential that looks made by a machine: it has a digit, or, letters alone, two capitals at most
 * one small letter apart beside small letters (random letters, `AbCd`, `dXNl`). A word of prose after
 * `Bearer` has neither, and neither has a camelCase placeholder (`YourGitHubTokenHere`), whose capitals
 * each start a word. Each look reads the credential once from where it starts, so a long run of
 * letters costs as much as reading it, never its square.
 */
const machineMade = `(?:(?=${CREDENTIAL}*\\d)|(?=${CREDENTIAL}*?[A-Z][a-z]?[A-Z])(?=[A-Z0-9._~+/=-]*[a-z]))`

/**
 * The credential of an explicit `Authorization: Basic` header, at any length: base64 of
 * `user:password`, whole groups of four with their padding, and not followed by more of a word (a
 * full stop that ends the sentence may follow).
 * `a:b` encodes to four characters, so no length floor applies. It must look encoded (a digit, `+`,
 * `/` or `=`, or, letters alone, two capitals at most one small letter apart beside small letters):
 * a word of prose (`Basic auth`, `Basic Auth`, `Basic AuthData`) does not.
 */
const BASIC_CREDENTIAL =
  '(?:(?=[A-Za-z]*[0-9+/=])|(?=[A-Za-z0-9+/]*?[A-Z][a-z]?[A-Z])(?=[A-Z0-9+/=]*[a-z]))' +
  '(?:[A-Za-z0-9+/]{4}){1,256}(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?(?![A-Za-z0-9_~+/=-]|\\.[A-Za-z0-9._~+/=-])'

/** A word as a pattern that matches it in any case (HTTP header names and schemes are case-insensitive). */
const anyCase = (word: string) =>
  word.replace(/[A-Za-z]/g, (letter) => `[${letter.toUpperCase()}${letter.toLowerCase()}]`)

/**
 * The shapes a secret takes in text, each with what is shown in its place (`$1`, `$2` are the
 * pattern's groups), in the order they are applied: a later one never matches what an earlier one left.
 *
 * Why it exists: the Mirror shows every command and result of the Session, and a signed
 * email-verification link once reached it inside a command. A reference such as `$TOKEN`,
 * `"$(op read …)"` or `op://…` does not match, so a command that fetches a secret stays readable.
 * Shapes that go only by a name (`PASSWORD=`, `"token":`) ask for a value that looks made by a
 * machine, so a local `POSTGRES_PASSWORD=postgres` stays readable. Applied by {@link maskSecrets};
 * searched by {@link findSecrets}, which reports a shape by its name (the first element), a stable
 * word a message can print where the value must not be.
 */
const SECRET_PATTERNS: ReadonlyArray<readonly [name: string, pattern: RegExp, replacement: string]> = [
  // Private key blocks, whole; then the head of one whose end was cut off
  ['private-key', /-----BEGIN ([A-Z ]*)PRIVATE KEY-----[\s\S]*?-----END \1PRIVATE KEY-----/g, `-----BEGIN $1PRIVATE KEY-----${MASK}-----END $1PRIVATE KEY-----`],
  ['private-key-head', /-----BEGIN ([A-Z ]*)PRIVATE KEY-----[A-Za-z0-9+/=\s]{40,}/g, `-----BEGIN $1PRIVATE KEY-----${MASK}`],
  // Authorization headers that carry the credential itself: a Bearer token, or a Basic credential of
  // any length (only one of the two groups takes part, so `$1$2` is the header that matched)
  [
    'authorization-header',
    new RegExp(
      // HTTP allows a tab as well as spaces around the scheme (an HTTP trace keeps it)
      `\\b(?:(${anyCase('Bearer')})[ \\t]+${REFERENCE}${machineMade}${CREDENTIAL}{16,}` +
        // A short padded credential, or one as long as a Bearer token in any spelling (unpadded, base64url)
        `|(${anyCase('Authorization')}:[ \\t]*${anyCase('Basic')})[ \\t]+${REFERENCE}` +
        `(?:${BASIC_CREDENTIAL}|${machineMade}${CREDENTIAL}{16,}))`,
      'g',
    ),
    `$1$2 ${MASK}`,
  ],
  // JSON Web Tokens: header and payload both begin with base64 `{"`
  ['json-web-token', /\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g, `eyJ${MASK}`],
  // API keys known by a prefix whose body is letters and digits alone: GitHub, npm, Hugging Face, Groq,
  // Replicate, Linear, Notion, Supabase, PostHog, Shopify, Stripe, Tavily, xAI, Perplexity, DigitalOcean
  [
    'prefixed-api-key',
    /\b(gh[pousr]_|npm_|hf_|gsk_|r8_|lin_api_|ntn_|sbp_|phx_|shp(?:at|ss|ca|pa)_|whsec_|(?:sk|rk)_(?:live|test)_|tvly-(?:dev-)?|xai-|pplx-|dop_v1_)[A-Za-z0-9]{20,}/g,
    `$1${MASK}`,
  ],
  // API keys known by a prefix whose body also has `-` and `_`: OpenAI, Anthropic, GitHub fine-grained,
  // GitLab, Slack, 1Password service accounts, Sentry, Figma
  [
    'prefixed-api-key-with-dashes',
    /\b(sk-(?:ant-|proj-|svcacct-)?|github_pat_|glpat-|xox[abeprs]-|ops_eyJ|sntry[su]_|figd_)(?=[A-Za-z0-9_-]{0,256}\d)[A-Za-z0-9_-]{20,}/g,
    `$1${MASK}`,
  ],
  // Keys whose prefix is short, so the whole shape is asked for: Google API keys, Google OAuth access
  // tokens, SendGrid keys (two parts), Resend keys (two parts)
  [
    'short-prefix-api-key',
    /\b(AIza(?=[0-9A-Za-z_-]{35})|ya29\.(?=[A-Za-z0-9._-]{30})|SG\.(?=[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16})|re_(?=[A-Za-z0-9]{6,}_[A-Za-z0-9]{16}))[A-Za-z0-9._-]{16,}/g,
    `$1${MASK}`,
  ],
  // AWS access key ids
  ['aws-access-key-id', /\b(AKIA|ASIA)[0-9A-Z]{16}\b/g, `$1${MASK}`],
  // Incoming webhooks of Slack and Discord: the address is the credential
  [
    'webhook-url',
    /(https:\/\/hooks\.slack\.com\/services\/T[A-Z0-9]+\/B[A-Z0-9]+\/|https:\/\/(?:ptb\.|canary\.)?discord(?:app)?\.com\/api\/webhooks\/\d+\/)[A-Za-z0-9_-]{20,}/g,
    `$1${MASK}`,
  ],
  // Signed links and tokens in a query string, also under a service's own name (`?exampleApiKey=`):
  // the parameter's name stays, its value goes
  [
    'signed-url-parameter',
    new RegExp(
      `([?&]${NOT_A_PAGE_TOKEN}[A-Za-z0-9_.-]*(?:signature|sig|token|api[_-]?key|secret|password|passwd|credentials?)=)${URL_REFERENCE}${mixed(URL_VALUE)}${URL_VALUE}{16,}`,
      'gi',
    ),
    `$1${MASK}`,
  ],
  // The password of a connection string: `scheme://user:password@host`
  ['connection-string-password', new RegExp(`(\\b[a-z][a-z0-9+.-]{0,31}:\\/\\/[^\\s:@/]+:)${REFERENCE}${mixed('[^\\s@/]')}[^\\s@/]{8,}(@)`, 'gi'), `$1${MASK}$2`],
  // NAME=value where the name says secret, the value ending where the assignment does
  [
    'secret-variable',
    new RegExp(
      `\\b(?![A-Za-z0-9_]*(?:PAGE|NEXT|CONTINUATION|CURSOR|SYNC)_?TOKEN=)([A-Za-z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|ACCESS_KEY|PRIVATE_KEY|CREDENTIALS?))=(["']?)${REFERENCE}${mixed(NAMED_VALUE)}${NAMED_VALUE}{12,}\\2(?=$|[\\s;&|)\\]},])`,
      'gm',
    ),
    `$1=$2${MASK}$2`,
  ],
  // `"apiKey": "value"` in JSON, where the key says secret
  [
    'json-secret-field',
    new RegExp(
      `("${NOT_A_PAGE_TOKEN}[A-Za-z0-9_.-]*(?:api[_-]?key|private[_-]?key|token|secret|password|passwd|credentials?)"\\s*:\\s*")${REFERENCE}${mixed('[^"\\s]')}[^"\\s]{12,}(")`,
      'gi',
    ),
    `$1${MASK}$2`,
  ],
]

/**
 * Hide every literal secret in a text shown on the HUD (see {@link SECRET_PATTERNS}).
 *
 * Called by {@link pushFeed} for every mirror entry, by the `tool.call` hook for the status line and
 * by the Mirror's row builder, so no path to the screen skips it.
 *
 * @param text - A prompt, an agent message, a tool call or its result.
 * @returns The same text with each secret value replaced by `•••`.
 *
 * @example
 * maskSecrets('open https://app.test/verify?expires=1&signature=0f3a9c…') // '…&signature=•••'
 */
export function maskSecrets(text: string): string {
  return SECRET_PATTERNS.reduce((shown, [, pattern, replacement]) => shown.replace(pattern, replacement), text)
}

/** Where a secret shape was found in a text: which shape, and where it begins. Never the value. */
export interface SecretFinding {
  /** The shape's name from {@link SECRET_PATTERNS} (`signed-url-parameter`), safe to print. */
  readonly pattern: string
  /** Offset of the match in the text, from 0. */
  readonly index: number
  /** Line of the match in the text, from 1. */
  readonly line: number
}

/**
 * Find every literal secret in a text, by shape name and position, without carrying any value.
 *
 * Why it exists: `dw handout` refuses to export a page that holds a secret (DX D8), and names the
 * page, line and shape so the agent can fix the source. It must find exactly what the Mirror masks,
 * so it walks the same {@link SECRET_PATTERNS}: a match that overlaps one of an earlier shape is not
 * counted again, as {@link maskSecrets} never re-masks what an earlier shape already hid. The
 * Handout builder (packages/handout) bundles this file at build time.
 *
 * @param text - A page's Markdown source, a title or a section name.
 * @returns The findings in the order they appear in the text; empty when the text holds no secret.
 *
 * @example
 * findSecrets(`[設計メモ](https://docs.test/a?signature=${'0f3a'.repeat(16)})`) // [{ pattern: 'signed-url-parameter', index: 26, line: 1 }]
 * findSecrets('export TOKEN="$(op read op://vault/api/token)"')     // []
 */
export function findSecrets(text: string): SecretFinding[] {
  // Which characters a shape already found, and where each line starts: both read in time that grows
  // with the text, however many findings it holds (a picture's metadata may hold thousands)
  const claimed = new Uint8Array(text.length)
  const lineStarts = [0]
  for (let index = text.indexOf('\n'); index !== -1; index = text.indexOf('\n', index + 1)) lineStarts.push(index + 1)
  const findings: SecretFinding[] = []
  for (const [name, pattern] of SECRET_PATTERNS) {
    // matchAll works on a copy of the pattern: its lastIndex stays untouched for maskSecrets
    for (const match of text.matchAll(pattern)) {
      const start = match.index ?? 0
      const end = start + match[0].length
      // A shape never counts text an earlier shape already found, as maskSecrets never re-masks it
      if (claimed.subarray(start, end).includes(1)) continue
      claimed.fill(1, start, end)
      findings.push({ pattern: name, index: start, line: lineOf(lineStarts, start) })
    }
  }
  // Sorted in place: the array is this call's own, and toSorted is newer than the WebKit the Handout's
  // builder targets (Safari 15)
  findings.sort((first, second) => first.index - second.index)
  return findings
}

/**
 * The line (from 1) a position of a text is on, found by halving the list of line starts. Called by
 * {@link findSecrets} for each finding.
 *
 * @param lineStarts - Where each line of the text starts, in order (the first is 0).
 * @param position - An index into the text.
 * @returns The number of the line holding it.
 *
 * @example
 * lineOf([0, 4, 9], 5) // 2
 */
function lineOf(lineStarts: readonly number[], position: number): number {
  let low = 0
  let high = lineStarts.length - 1
  while (low < high) {
    const middle = Math.ceil((low + high) / 2)
    if ((lineStarts[middle] ?? 0) <= position) low = middle
    else high = middle - 1
  }
  return low + 1
}
