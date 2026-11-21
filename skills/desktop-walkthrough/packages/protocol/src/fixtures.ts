/** Sample documents: what a Session looks like to the Mirror at a few moments. Used by tests and by the Mirror's gallery. */
import type { LiveDocument, Row, TranscriptDocument } from './index'

/** A turn in progress: a Prompt, the start of a reply, one finished tool call and one still running. */
export const turnInProgress: TranscriptDocument = {
  v: 1,
  sessionId: 'sample-session',
  dropped: 0,
  rows: [
    { kind: 'prompt', id: 'p1', text: 'run the tests', origin: 'composer' },
    { kind: 'reply', id: 'r1', text: 'Running the **unit tests** now.', isFirstOfReply: true },
    {
      kind: 'tool',
      id: 't1',
      tool: 'Bash',
      input: { command: 'git status --short', description: 'Show working tree status' },
      isRunning: false,
      isErrored: false,
      isInterrupted: false,
      output: { stdout: ' M src/app.ts\n?? notes.md', stderr: '', interrupted: false },
    },
    {
      kind: 'tool',
      id: 't2',
      tool: 'Bash',
      input: { command: 'pnpm test', description: 'Run the unit tests' },
      isRunning: true,
      isErrored: false,
      isInterrupted: false,
    },
  ],
}

/** The same turn's live state: the spinner while a tool runs, 42 seconds in. */
export const liveWhileToolRuns: LiveDocument = {
  v: 1,
  isBusy: true,
  startedAt: 1_795_000_000_000,
  spinner: { word: 'Puzzling', suffix: '…', mode: 'tool-use' },
  responseLength: 5_200,
  effort: 'high',
  hint: 'esc to interrupt',
}

/** Nothing runs: the Session waits for a Prompt. */
export const liveIdle: LiveDocument = {
  v: 1,
  isBusy: false,
  hint: '? for shortcuts',
}

/** A named set of Rows for the Mirror's gallery: one look to check in a browser. */
export type GalleryFixture = {
  title: string
  /** What to compare it with in the terminal. */
  note: string
  rows: Row[]
}

const longPrompt = Array.from(
  { length: 260 },
  (_, line) => `line ${line + 1}: a pasted log line that is long enough to take most of its row`,
).join('\n')

/** Every Row kind and state of the foundation, with invented content: what the gallery draws at two widths. */
export const galleryFixtures: GalleryFixture[] = [
  {
    title: 'Prompt: the user types',
    note: 'Grey background to the right edge on every wrapped line, pointer in grey, 2-column hanging indent.',
    rows: [
      { kind: 'prompt', id: 'g-p1', text: 'run the tests', origin: 'composer' },
      {
        kind: 'prompt',
        id: 'g-p2',
        text: 'Please rename the **session store** to `liveStore`, update every import, and tell me which files you touched when you are done.\n\nAfter that, check that the build still passes.',
        origin: 'composer',
      },
      { kind: 'prompt', id: 'g-p3', text: '/model opus', origin: 'composer' },
      {
        kind: 'prompt',
        id: 'g-p4',
        text: '> a quote and a table stay literal here\n| a | b |\n|---|---|\n| 1 | 2 |\n[a link](https://example.com)',
        origin: 'composer',
      },
      { kind: 'prompt', id: 'g-p5', text: 'ultrathink about the cache invalidation', origin: 'composer' },
    ],
  },
  {
    title: 'Prompt: other origins',
    note: 'A prompt from the HUD hangs under a dim "From the … plugin" line; a task notification has a coloured bullet; a peer message is one dim line.',
    rows: [
      {
        kind: 'prompt',
        id: 'g-o1',
        text: 'Open the Explainer on the second page',
        origin: 'plugin',
        from: 'desktop-walkthrough',
      },
      {
        kind: 'prompt',
        id: 'g-o2',
        text: 'Background task "build docs" finished',
        origin: 'task-notification',
        status: 'completed',
        durationMs: 66_000,
      },
      {
        kind: 'prompt',
        id: 'g-o3',
        text: 'Background task "lint" failed',
        origin: 'task-notification',
        status: 'failed',
        durationMs: 12_000,
      },
      {
        kind: 'prompt',
        id: 'g-o4',
        text: 'Background task "watch" was stopped',
        origin: 'task-notification',
        status: 'killed',
      },
      {
        kind: 'prompt',
        id: 'g-o5',
        text: 'The migration is ready for review on my side.',
        origin: 'peer',
        from: 'reviewer',
      },
    ],
  },
  {
    title: 'Prompt: very long',
    note: 'Over 10,000 characters: head, a dim rule titled "(N lines, ~X KB hidden)", tail.',
    rows: [{ kind: 'prompt', id: 'g-l1', text: longPrompt, origin: 'composer' }],
  },
  {
    title: 'Reply: prose, emphasis, code, links',
    note: 'White bullet, 2-column indent, bold bare, inline code in periwinkle, links in bright blue, summary tag dim.',
    rows: [
      { kind: 'reply', id: 'g-r1', text: 'Running the **unit tests** now.', isFirstOfReply: true },
      {
        kind: 'reply',
        id: 'g-r2',
        text: 'The store keeps the newest transcript and the newest live state. A document that does not fit the protocol is refused, and the last good one stays on screen, so a half-written file never blanks the panel. See `receiveTranscript` in `store.ts`, or the [protocol notes](https://example.com/protocol) for the shape of a Row.\n\nSecond paragraph with *italic*, ~~struck~~ and a long path /Users/example/project/packages/mirror/src/rows/ReplyRow.tsx that cannot break at a space.',
        isFirstOfReply: false,
      },
      {
        kind: 'reply',
        id: 'g-r3',
        text: '日本語の返信も同じ列に収まります。長い文は端で折り返され、続きの行は印の分だけ字下げされます。`/verify` のようなコードも色が付きます。',
        isFirstOfReply: true,
      },
      {
        kind: 'reply',
        id: 'g-r4',
        text: 'Checking the plugin config before the commit.',
        isFirstOfReply: true,
        isSummary: true,
      },
    ],
  },
  {
    title: 'Reply: headings, rules, quotes',
    note: 'H1 bold italic underlined, deeper headings bold, a blank row after each; a rule is the three characters; quotes have a dim bar and italic text.',
    rows: [
      {
        kind: 'reply',
        id: 'g-h1',
        text: '# Plan\n\nFirst the schema.\n\n## Steps\n\n### Detail\n\nText under a detail heading.\n\n---\n\nAfter the rule.\n\n> A quoted line that is long enough to wrap onto a second row of the panel.\n>\n> > A nested quote.\n\nBack to prose.',
        isFirstOfReply: true,
      },
    ],
  },
  {
    title: 'Reply: lists',
    note: 'Marker cell of 2 columns, nested lists indent by the parent marker; ordered lists number 1. a. i.; task items show [ ] and [x].',
    rows: [
      {
        kind: 'reply',
        id: 'g-li1',
        text: 'Changes:\n- the store refuses documents that do not fit the protocol, and keeps the last good one so the panel never blanks\n- the host\n  - nested item with a long text that wraps under its own first character, not under the dash\n  - another\n    - third level\n- last\n\nSteps:\n1. Read the reference\n2. Build the layout\n   1. Rows\n   2. Markdown\n      1. Tables\n      2. Fences\n10. Check it\n\n- [x] done item\n- [ ] open item',
        isFirstOfReply: true,
      },
      {
        kind: 'reply',
        id: 'g-li2',
        text: '- first item\n\n- second item after a blank line\n- third item\n- fourth item runs on for long enough that it has to wrap onto more than one line',
        isFirstOfReply: true,
      },
    ],
  },
  {
    title: 'Reply: code',
    note: 'No frame or background. Known language: coloured; no language: periwinkle; unknown language: dim label line then plain.',
    rows: [
      {
        kind: 'reply',
        id: 'g-c1',
        text: 'A typed example:\n```ts\n// Count the rows of a kind\nexport function count(rows: Row[], kind: string): number {\n  const pattern = /^[a-z-]+$/\n  return rows.filter((row) => row.kind === kind && pattern.test(kind)).length + 1\n}\n```\nA shell line:\n```bash\npnpm --filter @dw/mirror dev # open /gallery.html\n```\n\n```json\n{ "name": "mirror", "private": true, "version": 1, "tags": ["a", null] }\n```\n\n```diff\n- const old = 1\n+ const next = 2\n```\n\n```\nplain fence with no language\n```\n\n```mermaid\ngraph TD\n```\n\n    indented code\n',
        isFirstOfReply: true,
      },
    ],
  },
  {
    title: 'Reply: tables',
    note: 'Box-drawing grid, header centred, a line after every row. When a cell would need more than four lines the table becomes one "Header: value" line per column.',
    rows: [
      {
        kind: 'reply',
        id: 'g-t1',
        text: '| Kind | Marker | Colour |\n|:-----|:------:|-------:|\n| prompt | ❯ | grey |\n| reply | ⏺ | white |\n| notice | none | dim |',
        isFirstOfReply: true,
      },
      {
        kind: 'reply',
        id: 'g-t2',
        text: 'Wider than a narrow panel:\n\n| Row | What it shows | When it appears |\n|---|---|---|\n| turn-duration | the verb and the elapsed time of the finished turn | when a turn finishes normally |\n| notice | a dim note with an optional slash command | at the start of a session |\n| `a\\|b` | pipes in code | stay in the cell |',
        isFirstOfReply: true,
      },
      {
        kind: 'reply',
        id: 'g-t3',
        text: '| 名前 | 説明 |\n|---|---|\n| 図面 | 全角の文字は二列分の幅で数えます |\n| 組図 | 表は端末と同じ手順で幅を決めます |',
        isFirstOfReply: true,
      },
    ],
  },
  {
    title: 'Slash command output',
    note: 'Echo is a normal prompt; output hangs under it in the ⎿ gutter, no blank row between; errors in the error colour; empty output draws nothing.',
    rows: [
      { kind: 'prompt', id: 'g-s1', text: '/model', origin: 'composer' },
      {
        kind: 'command-output',
        id: 'g-s2',
        command: 'model',
        args: '',
        text: 'Set model to **Opus** (effort: `high`)\nUse `/model` again to change it, or press a number below.',
        isErrored: false,
      },
      { kind: 'prompt', id: 'g-s3', text: '/compact now', origin: 'composer' },
      {
        kind: 'command-output',
        id: 'g-s4',
        command: 'compact',
        args: 'now',
        text: 'Error: Not enough messages to compact. Try again once the conversation has grown a little longer than this.',
        isErrored: true,
      },
      { kind: 'prompt', id: 'g-s5', text: '/clear', origin: 'composer' },
      {
        kind: 'command-output',
        id: 'g-s6',
        command: 'clear',
        args: '',
        text: '(no content)',
        isErrored: false,
      },
    ],
  },
  {
    title: 'Turn duration and notices',
    note: 'Dim ✻ line with a blank row above; notices dim, two columns in, with an optional · /command.',
    rows: [
      { kind: 'turn-duration', id: 'g-d1', word: 'Baked', durationMs: 3_400 },
      { kind: 'turn-duration', id: 'g-d2', word: 'Worked', durationMs: 66_000 },
      { kind: 'turn-duration', id: 'g-d3', word: 'Cooked', durationMs: 3_723_000 },
      { kind: 'turn-duration', id: 'g-d4', word: 'Brewed', durationMs: 0 },
      { kind: 'notice', id: 'g-n1', text: 'Using Opus with high effort', command: '/model' },
      { kind: 'notice', id: 'g-n2', text: 'Auto-compact is on', command: null },
    ],
  },
]
