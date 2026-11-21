/** Sample documents: what a Session looks like to the Mirror at a few moments. Used by tests and by the Mirror's gallery. */
import type { LiveDocument, TranscriptDocument } from './index'

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
