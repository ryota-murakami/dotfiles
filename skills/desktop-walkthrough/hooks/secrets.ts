/**
 * Secrets never reach the HUD: every text the Bridge writes for it passes {@link maskSecrets}.
 *
 * Why it is a file of its own: the feed, the status line and the Mirror's documents are written by
 * different parts of the Bridge, and all of them must hide the same values the same way.
 */
/**
 * Values that must never reach the HUD, each written out literally, paired with what is shown
 * instead. A reference such as `$TOKEN`, `"$(op read …)"` or `op://…` does not match, so a command
 * that fetches a secret stays readable.
 *
 * Why it exists: the mirror shows every Bash command in full, and a signed email-verification link
 * once reached it inside a command. Applied by {@link maskSecrets} to everything this module writes
 * for the HUD. The PreToolUse hook `~/.claude/hooks/block-literal-secrets.py` refuses Bash commands
 * that spell a secret out; keep its list in step with this one.
 */
const SECRET_PATTERNS: ReadonlyArray<readonly [RegExp, string]> = [
  // Private key blocks, whole
  [/-----BEGIN ([A-Z ]*)PRIVATE KEY-----[\s\S]*?-----END \1PRIVATE KEY-----/g, '-----BEGIN $1PRIVATE KEY-----•••-----END $1PRIVATE KEY-----'],
  // Signed links and tokens in a query string: the parameter name stays, its value goes
  [/([?&](?:signature|sig|token|access_token|refresh_token|id_token|api_key|apikey|key|secret|client_secret|password|code)=)[^&#\s'"`]{6,}/gi, '$1•••'],
  // Authorization headers that carry the credential itself
  [/\b(Bearer|Authorization: *Basic) +(?![$`])[A-Za-z0-9._~+/=-]{12,}/g, '$1 •••'],
  // JSON Web Tokens: header and payload both start with base64 `{"`
  [/\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g, 'eyJ•••'],
  // API keys known by their prefix: OpenAI/Anthropic, GitHub, GitLab, Slack, Stripe, 1Password service accounts
  [/\b(sk-(?:ant-|proj-)?|gh[pousr]_|github_pat_|glpat-|xox[abprs]-|(?:sk|rk)_(?:live|test)_|ops_eyJ)[A-Za-z0-9_-]{16,}/g, '$1•••'],
  // AWS access key ids, Google API keys, Resend keys
  [/\bAKIA[0-9A-Z]{16}\b/g, 'AKIA•••'],
  [/\bAIza[0-9A-Za-z_-]{35}/g, 'AIza•••'],
  [/\bre_[A-Za-z0-9]{6,}_[A-Za-z0-9]{16,}/g, 're_•••'],
  // NAME=value where the name says secret, unless the value is a reference ($X, $(…), `…`)
  [/\b([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|APIKEY|ACCESS_KEY|PRIVATE_KEY))=(["']?)(?![$`])[^\s"'`;&|]{6,}\2/g, '$1=$2•••$2'],
]

/**
 * Hide every literal secret in a text shown on the HUD (see {@link SECRET_PATTERNS}).
 *
 * Called by {@link pushFeed} for every mirror entry and by the `tool.call` hook for the status
 * line, so no path to the screen skips it.
 *
 * @param text - A prompt, an agent message or a tool call description.
 * @returns The same text with each secret value replaced by `•••`.
 *
 * @example
 * maskSecrets('open https://app.test/verify?expires=1&signature=abc123def') // '…&signature=•••'
 */
export function maskSecrets(text: string): string {
  return SECRET_PATTERNS.reduce((shown, [pattern, replacement]) => shown.replace(pattern, replacement), text)
}
