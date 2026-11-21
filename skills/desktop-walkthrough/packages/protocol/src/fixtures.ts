/** Sample documents: what a Session looks like to the Mirror at a few moments. Used by tests and by the Mirror's gallery. */
import type { MirrorDocument } from './index'

/** A turn in progress: one Prompt, the start of a reply, a tool call still running. */
export const turnInProgress: MirrorDocument = {
  v: 1,
  sessionId: 'sample-session',
  rows: [
    { kind: 'prompt', id: 'p1', text: 'run the tests', origin: 'user' },
    { kind: 'reply', id: 'r1', text: 'Running the **unit tests** now.', isFirstOfReply: true },
    { kind: 'tool', id: 't1', tool: 'Bash', input: { command: 'pnpm test' }, state: 'running' },
  ],
  live: {
    isBusy: true,
    startedAt: 1_795_000_000_000,
    spinner: { word: 'Puzzling', suffix: '…', mode: 'tool-use' },
    hint: 'esc to interrupt',
  },
}
