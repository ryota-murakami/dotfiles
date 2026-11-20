import type { EngineInterface, Register } from 'claude-code'

/**
 * hud-bridge: connects a Claude Code session to the desktop-walkthrough HUD through plain files,
 * so the person can read the conversation, talk to the agent and stop it from any desktop
 * without switching to the terminal that hosts the session.
 *
 * It exists because the first HUD mirrored the terminal as an image and typed messages into it,
 * which was unreadable and collided with focus. It ships as this plugin's hooks module, so it
 * loads in every Claude Code session; it stays dormant unless a HUD is running and `dw start`
 * named this session as the walkthrough's owner.
 *
 * Files under the state folder (`$DW_HOME`, default `~/.local/state/desktop-walkthrough`):
 * - `bridge/feed.jsonl`    mod → HUD  the conversation: prompts, the agent's text, one line per tool call
 * - `bridge/owner`         dw → mod   id of the session the walkthrough belongs to
 * - `bridge/mod.log`       mod → dw   one line per load: time and session id
 * - `bridge/state.json`    mod → HUD  `{ busy, turnId, stopped, sessionId, at }`
 * - `bridge/inbox.jsonl`   HUD → mod  `{"text": "..."}` lines typed in the HUD's message box
 * - `bridge/control.jsonl` HUD → mod  `{"cmd": "stop" | "resume"}` lines from the stop button or shortcut
 * - `bridge/stop`          both       "on" / "off": the one source of truth for stop
 * - `bridge/tool-class`    mod → HUD  what the newest tool call of the running turn is: "skill", "waiting" or "other"
 * - `status.txt`           mod → HUD  the status line, for tools that do not narrate through `dw say`
 * - `typing`, `hud.alive`   HUD → mod  message being typed, heartbeat
 */
const FEED_LIMIT = 300
/** A heartbeat older than this means the HUD is gone and its typing flag is stale. */
const HUD_STALE_MS = 8000
/** Bash commands that drive the GUI: these wait while the person has taken over the Mac. */
const GUI_COMMAND = /agent-desktop|desktop-walkthrough|(^|[\s;&|(])dw\s/

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

type Paths = {
  feed: string
  state: string
  inbox: string
  control: string
  stop: string
  owner: string
  log: string
  errors: string
  status: string
  ask: string
  typing: string
  alive: string
  toolClass: string
}

type FeedEntry = { role: 'you' | 'agent' | 'tool' | 'hud'; text: string; ts: number }

/** Bridge state; module variables start over on every reload, the files carry what the HUD needs. */
const S = {
  paths: undefined as Paths | undefined,
  feed: [] as FeedEntry[],
  seenMessage: undefined as string | undefined,
  inboxOffset: -1,
  controlOffset: -1,
  runningTurn: undefined as string | undefined,
  wasActive: false,
  polling: false,
}

/**
 * Resolve the state folder once per load, from the same variables the `dw` script uses.
 *
 * @returns Absolute paths of every file shared with the HUD.
 */
async function paths($: EngineInterface): Promise<Paths> {
  if (S.paths) return S.paths
  const custom = await $.env.get('DW_HOME')
  const home = custom ?? `${(await $.env.get('HOME')) ?? ''}/.local/state/desktop-walkthrough`
  const bridge = `${home}/bridge`
  S.paths = {
    feed: `${bridge}/feed.jsonl`,
    state: `${bridge}/state.json`,
    inbox: `${bridge}/inbox.jsonl`,
    control: `${bridge}/control.jsonl`,
    stop: `${bridge}/stop`,
    owner: `${bridge}/owner`,
    log: `${bridge}/mod.log`,
    errors: `${bridge}/errors.txt`,
    status: `${home}/status.txt`,
    ask: `${home}/ask.json`,
    typing: `${home}/typing`,
    alive: `${home}/hud.alive`,
    toolClass: `${bridge}/tool-class`,
  }
  return S.paths
}

/** True while a HUD is running: it rewrites its heartbeat file every second. */
async function isHudAlive($: EngineInterface): Promise<boolean> {
  try {
    const { mtimeMs } = await $.fs.stat((await paths($)).alive)
    return Date.now() - mtimeMs < HUD_STALE_MS
  } catch {
    return false
  }
}

/**
 * True when this session owns the running walkthrough.
 *
 * The plugin loads in every Claude Code session, so each session's copy of the mod must ignore
 * a HUD started from another session. `dw start` records `CLAUDE_CODE_SESSION_ID` in the owner
 * file; called before anything that reads or answers the HUD.
 */
async function isOwner($: EngineInterface): Promise<boolean> {
  try {
    const { owner } = await paths($)
    if (!(await $.fs.exists(owner))) return false
    const id = String(await $.fs.read(owner)).trim()
    return id !== '' && id === (await $.session.id())
  } catch {
    return false
  }
}

/** Active = a HUD is running and it belongs to this session. */
async function isActive($: EngineInterface): Promise<boolean> {
  return (await isHudAlive($)) && (await isOwner($))
}

/** Leave a trace that the mod loaded here: `dw start` reads it to tell "not loaded" from "not answering". */
async function logLoaded($: EngineInterface) {
  const { log } = await paths($)
  let lines: string[] = []
  try {
    if (await $.fs.exists(log)) lines = String(await $.fs.read(log)).split('\n').filter(l => l !== '')
  } catch {
    lines = []
  }
  lines.push(`${new Date().toISOString()} ${await $.session.id()}`)
  await $.fs.write(log, lines.slice(-50).join('\n') + '\n')
}

/** Read the shared stop switch; hooks and timers may not share memory, so the file decides. */
async function isStopOn($: EngineInterface): Promise<boolean> {
  try {
    const { stop } = await paths($)
    return (await $.fs.exists(stop)) && String(await $.fs.read(stop)).trim() === 'on'
  } catch {
    return false
  }
}

/** True while a live HUD asks GUI automation to wait: the person is typing a message in it. */
async function shouldWait($: EngineInterface): Promise<boolean> {
  const p = await paths($)
  if (!(await $.fs.exists(p.typing))) return false
  return isHudAlive($)
}

/** End the main loop's running turn, the id taken from memory or from the state file. */
async function abortRunningTurn($: EngineInterface) {
  const p = await paths($)
  let turnId = S.runningTurn
  if (turnId === undefined) {
    try {
      turnId = (JSON.parse(String(await $.fs.read(p.state))) as { turnId?: string }).turnId
    } catch {
      turnId = undefined
    }
  }
  if (turnId === undefined) return
  await $.turn.abort({ turnId }).catch(async (err: unknown) => {
    // Recorded, not swallowed: a stop that did not stop must be diagnosable
    await $.fs.write(p.errors, `${new Date().toISOString()} turn.abort(${turnId}) failed: ${String(err)}\n`).catch(() => undefined)
  })
}

/**
 * Rewrite the feed file with the newest entries (the HUD re-reads it on change).
 *
 * @param force - Write even without new entries: used when this session takes the HUD over,
 *   so a feed left by another session is replaced.
 */
async function pushFeed($: EngineInterface, entries: FeedEntry[], force = false) {
  if (entries.length === 0 && !force) return
  // Secrets are hidden here, the one place every mirror entry passes through
  const shown = entries.map(entry => ({ ...entry, text: maskSecrets(entry.text) }))
  S.feed = [...S.feed, ...shown].slice(-FEED_LIMIT)
  await $.fs.write((await paths($)).feed, S.feed.map(e => JSON.stringify(e)).join('\n') + '\n')
}

async function writeState($: EngineInterface) {
  const state = {
    busy: S.runningTurn !== undefined,
    turnId: S.runningTurn,
    stopped: await isStopOn($),
    sessionId: await $.session.id(),
    at: Date.now(),
  }
  await $.fs.write((await paths($)).state, JSON.stringify(state))
}

/** Tools that only look: a line about them tells the person nothing about what is happening on screen. */
const QUIET_TOOLS: ReadonlySet<string> = new Set(['Read', 'Grep', 'Glob', 'ToolSearch', 'TodoWrite'])

/**
 * Whether a tool call may replace the status line of the bar with its own description.
 *
 * Why it exists: the bar showed `Read: /tmp/…png` for minutes while the person was meant to answer a
 * question, because every un-narrated tool call overwrote the narration. Called by the `tool.call` hook.
 *
 * @param tool - Name of the tool being called.
 * @param isGuiCommand - True for `dw` / agent-desktop commands, which narrate through `dw say`.
 * @param questionPending - True while a `dw ask` / `dw wait-user` question is open: its line stays.
 * @returns False when the line already on the bar should stay.
 *
 * @example
 * showsToolOnBar('Read', false, false) // false: the last narration stays
 * showsToolOnBar('Bash', false, false) // true: an un-narrated command is shown
 */
export function showsToolOnBar(tool: string, isGuiCommand: boolean, questionPending: boolean): boolean {
  return !isGuiCommand && !questionPending && !QUIET_TOOLS.has(tool)
}

/** What a tool call is, for the state the bar shows at its trailing end. */
export type ToolClass = 'skill' | 'waiting' | 'other'

/** Files of this skill: its source, wherever it is installed or checked out, and its private notes. */
const SKILL_FILE = /skills\/desktop-walkthrough\/|\.config\/desktop-walkthrough\/notes\.md/
/**
 * A Bash command that works on the skill rather than with it: it names a source folder of the
 * skill, changes into the skill folder, builds or runs the HUD binary, or drives a scratch HUD.
 * Merely calling `…/desktop-walkthrough/scripts/dw` is using the skill and does not match.
 */
const SKILL_COMMAND =
  /desktop-walkthrough\/(hud|hooks|explainer|references|\.claude-plugin|SKILL\.md|README\.md|scripts\/check)|cd\s+\S*skills\/desktop-walkthrough(?![\w/.-])|\bStatusHUD\b|\bDW_HOME=/
/** A Bash command that blocks until the user answers on the HUD. */
const WAIT_COMMAND = /(^|[\s;&|(/])dw["']?\s+(wait-user|ask)\b|\$\{?DW\}?["']?\s+(wait-user|ask)\b/
/** Tools that exist to wait: for the user, for a timer, for a background task. */
const WAITING_TOOLS: ReadonlySet<string> = new Set(['AskUserQuestion', 'Monitor', 'ScheduleWakeup'])

/**
 * Class of a tool call, so the HUD can tell "updating the skill" and "waiting" from other work.
 * Whether the walkthrough itself is acting is not decided here: `dw` reports that when it runs.
 *
 * Why it exists: the bar showed a stop button all the time, also while the agent edited its own
 * skill or waited for an answer. Called by the `tool.call` hook, which writes the result for the HUD.
 *
 * @param tool - Name of the tool being called.
 * @param input - Its input (`command`, `file_path`, `run_in_background`, …).
 * @returns The class, or undefined for a tool that only looks at something outside the skill:
 *   the class of the call before it stays.
 *
 * @example
 * classifyTool('Edit', { file_path: '/x/skills/desktop-walkthrough/hud/Bar.swift' }) // 'skill'
 * classifyTool('Bash', { command: '$DW wait-user "読んでください"' })                  // 'waiting'
 * classifyTool('Bash', { command: 'git status' })                                    // 'other'
 */
export function classifyTool(tool: string, input: Record<string, unknown>): ToolClass | undefined {
  const text = (key: string) => (typeof input[key] === 'string' ? (input[key] as string) : '')
  if (WAITING_TOOLS.has(tool)) return 'waiting'
  if (tool === 'Bash') {
    const command = text('command')
    // A wait in the background returns at once: the agent goes on working
    if (input.run_in_background !== true && WAIT_COMMAND.test(command)) return 'waiting'
    return SKILL_COMMAND.test(command) ? 'skill' : 'other'
  }
  const target = text('file_path') || text('path') || text('notebook_path')
  if (SKILL_FILE.test(target)) return 'skill'
  // Looking at a file outside the skill says nothing about what the agent is busy with
  return QUIET_TOOLS.has(tool) ? undefined : 'other'
}

/** One line describing a tool call: the Bash description when the model gave one. */
function describeTool(tool: string, input: Record<string, unknown>): string {
  const pick = (k: string) => (typeof input[k] === 'string' ? (input[k] as string) : undefined)
  // Bash: the description and the whole command, never shortened, so the user can follow every step
  if (tool === 'Bash') {
    const desc = pick('description')
    const command = pick('command') ?? ''
    return `${tool}${desc ? `: ${desc}` : ''}\n$ ${command}${input.run_in_background === true ? '\n(background)' : ''}`
  }
  const detail = pick('description') ?? pick('file_path') ?? pick('pattern') ?? pick('url') ?? pick('query') ?? pick('name_path_pattern') ?? pick('relative_path') ?? pick('prompt') ?? ''
  return `${tool}${detail ? `: ${detail}` : ''}`
}

/** Read the bytes appended to a HUD → mod file since the last poll, as parsed JSON lines. */
async function readNewLines($: EngineInterface, path: string, offset: number) {
  if (!(await $.fs.exists(path))) return { lines: [] as Record<string, unknown>[], offset: 0 }
  const { size } = await $.fs.stat(path)
  // First poll (or a truncated file): start at the end so old lines are not replayed
  if (offset < 0 || size < offset) return { lines: [] as Record<string, unknown>[], offset: size }
  if (size === offset) return { lines: [] as Record<string, unknown>[], offset }
  const added = await $.fs.read(path, { offset, length: size - offset })
  const lines = String(added)
    .split('\n')
    .filter(l => l.trim() !== '')
    .flatMap(l => {
      try {
        return [JSON.parse(l) as Record<string, unknown>]
      } catch {
        return []
      }
    })
  return { lines, offset: size }
}

/** Pull the conversation rows stored since the last poll into the feed. */
async function syncFeed($: EngineInterface) {
  const fresh = await $.session.messages(S.seenMessage === undefined ? { last: 60 } : { after: S.seenMessage })
  if (!Array.isArray(fresh)) return
  const entries: FeedEntry[] = []
  for (const m of fresh) {
    if (m.uuid) S.seenMessage = m.uuid
    const text = m.text.trim()
    // The person's prompts; reminders and tool results are left out of the mirror
    if (m.role === 'user' && text !== '' && !text.startsWith('<') && (m.toolResults ?? []).length === 0) {
      entries.push({ role: 'you', text, ts: Date.now() })
    }
    if (m.role === 'assistant') {
      if (text !== '') entries.push({ role: 'agent', text, ts: Date.now() })
      for (const use of m.toolUses) entries.push({ role: 'tool', text: describeTool(use.tool, use.input), ts: Date.now() })
    }
  }
  await pushFeed($, entries)
}

/** Apply ⏹ stop / resume requests and deliver messages typed in the HUD. */
async function pollHud($: EngineInterface) {
  const p = await paths($)
  const control = await readNewLines($, p.control, S.controlOffset)
  S.controlOffset = control.offset
  for (const c of control.lines) {
    if (c.cmd === 'stop') {
      await pushFeed($, [{ role: 'hud', text: '⏹ 停止ボタンが押されました（処理を中断）', ts: Date.now() }])
      // Immediate stop: end the running turn; tool.call refuses everything while the switch is on
      await abortRunningTurn($)
    }
    await writeState($)
  }

  const inbox = await readNewLines($, p.inbox, S.inboxOffset)
  S.inboxOffset = inbox.offset
  for (const m of inbox.lines) {
    const text = typeof m.text === 'string' ? m.text.trim() : ''
    if (text === '') continue
    await pushFeed($, [{ role: 'hud', text: `✉️ HUDから送信: ${text}`, ts: Date.now() }])
    if (S.runningTurn !== undefined && !(await isStopOn($))) {
      // Mid-turn: reaches the agent with its next request, like a message typed while it works
      await $.session.append({
        message: { type: 'user', content: [{ type: 'text', text: `The user sent this message from the HUD while you were working:\n${text}` }] },
      })
    } else {
      // Idle (or stopped): a new turn in the person's own words; speaking lifts the stop
      await $.fs.write(p.stop, 'off')
      await writeState($)
      void $.prompt.submit({ text, asUser: true })
    }
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await logLoaded($).catch(() => undefined)
    // One poll loop for the feed and the HUD's inbox/control files; idle unless this session owns a live HUD
    $.clock.every(600, () => {
      // A slow tick must not overlap the next one
      if (S.polling) return
      S.polling = true
      void (async () => {
        if (!(await isActive($))) {
          S.wasActive = false
          return
        }
        const p = await paths($)
        const taking = !S.wasActive
        S.wasActive = true
        // `dw start` deletes the state file and waits for the owning session to write it back
        if (taking || !(await $.fs.exists(p.state))) await writeState($)
        await syncFeed($).catch(() => undefined)
        if (taking) await pushFeed($, [], true)
        await pollHud($).catch(() => undefined)
      })()
        .catch(() => undefined)
        .finally(() => {
          S.polling = false
        })
    })
    return started
  })

  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) {
      S.runningTurn = e.turnId
      if (await isActive($)) {
        // A new turn starts as "other work" until a tool call or `dw` says more
        await $.fs.write((await paths($)).toolClass, 'other').catch(() => undefined)
        await writeState($)
      }
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined) {
      S.runningTurn = undefined
      if (await isActive($)) {
        await writeState($)
        await syncFeed($).catch(() => undefined)
      }
    }
    return done
  })

  // A prompt from the person (typed or sent from the HUD) lifts a stop, in the owning session only
  on('prompt.submit', async ($, e, next) => {
    if ((await isStopOn($)) && (await isOwner($))) {
      await $.fs.write((await paths($)).stop, 'off')
      await writeState($)
    }
    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    // Other sessions' tools are never touched: only the walkthrough's owner is gated
    if (e.agentId === undefined && (await isOwner($))) {
      if (await isStopOn($)) {
        await abortRunningTurn($)
        return { deny: `${$.plugin.name}: the user pressed ⏹ Stop on the HUD. Do not continue; wait for their message.` }
      }
      const input = e as unknown as Record<string, unknown>
      const command = e.tool === 'Bash' && typeof input.command === 'string' ? input.command : ''
      const isGuiCommand = GUI_COMMAND.test(command)
      // GUI automation waits while the person types a message in the HUD
      if (isGuiCommand) {
        while (await shouldWait($)) {
          await $.clock.sleep(500, { signal: next.signal })
          if (await isStopOn($)) return { deny: `${$.plugin.name}: stopped from the HUD while waiting.` }
        }
      }
      // `dw say` narrates in the person's language; only un-narrated tools get this generic line,
      // never over an open question and never for a tool that only looks
      const p = await paths($)
      // The class of this call, for the state badge of the bar
      const toolClass = classifyTool(e.tool, input)
      if (toolClass !== undefined && (await isHudAlive($))) await $.fs.write(p.toolClass, toolClass).catch(() => undefined)
      if ((await isHudAlive($)) && showsToolOnBar(e.tool, isGuiCommand, await $.fs.exists(p.ask))) {
        await $.fs.write(p.status, maskSecrets(describeTool(e.tool, input))).catch(() => undefined)
      }
    }
    return next(e)
  })
}
