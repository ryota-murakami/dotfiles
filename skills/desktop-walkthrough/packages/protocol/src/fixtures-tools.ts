/**
 * Sample tool rows for the Mirror's gallery and the specs of its tool rows: every state of a call,
 * every tool the terminal words a result for, and the folded runs. All content is invented.
 */
import type { GalleryFixture } from './fixtures'
import type { Row, ToolCall, ToolGroupRow, ToolRow } from './index'

/** Flags of a call that has not resolved: queued, or running when `isRunning` is set. */
const unresolved = { isRunning: false, isErrored: false, isInterrupted: false }

/** A finished tool Row. */
function done(id: string, tool: string, input: unknown, output: unknown): ToolRow {
  return { kind: 'tool', id, tool, input, output, ...unresolved }
}

/** A tool Row that failed; `output` is the error text the tool gave. */
function failed(id: string, tool: string, input: unknown, output: unknown): ToolRow {
  return { kind: 'tool', id, tool, input, output, ...unresolved, isErrored: true }
}

/** A tool Row the user interrupted. */
function interrupted(id: string, tool: string, input: unknown, output?: unknown): ToolRow {
  const row: ToolRow = { kind: 'tool', id, tool, input, ...unresolved, isErrored: true, isInterrupted: true }
  return output === undefined ? row : { ...row, output }
}

/** A tool Row that is running now. */
function running(id: string, tool: string, input: unknown): ToolRow {
  return { kind: 'tool', id, tool, input, ...unresolved, isRunning: true }
}

/** A tool Row that was queued: no result and not running. */
function queued(id: string, tool: string, input: unknown): ToolRow {
  return { kind: 'tool', id, tool, input, ...unresolved }
}

/** A call of a folded run: a tool Row without its Row fields. */
function call({ kind: _kind, id: _id, ...rest }: ToolRow): ToolCall {
  return rest
}

/** A folded run of calls. */
function group(id: string, isActive: boolean, calls: ToolRow[]): ToolGroupRow {
  return { kind: 'tool-group', id, isActive, calls: calls.map(call) }
}

/** The text of a command's output as the Bridge clips it: five lines of a longer whole. */
const clippedOutput = {
  head: 'src/app.ts:12: parse(input)\nsrc/app.ts:40: parse(value)\nsrc/lib/read.ts:7: parse(text)\nsrc/lib/read.ts:19: parse(raw)\nsrc/lib/write.ts:3: parse(json)',
  lines: 49,
  chars: 2310,
}

/** The first lines of a file a Write created, as the Bridge clips them. */
const clippedSource = {
  head: [
    "import { readFile } from 'node:fs/promises'",
    '',
    '/** Count the words of a text file. */',
    'export async function countWords(path: string): Promise<number> {',
    "  const text = await readFile(path, 'utf8')",
    '  // Words are runs of non-space characters',
    '  return text.split(/\\s+/).filter(Boolean).length',
    '}',
    '',
    'export const LIMIT = 4096',
    "export const LABEL = 'words'",
    '',
  ].join('\n'),
  lines: 95,
  chars: 7200,
}

/** An Edit's structured patch: one changed line with context, one hunk. */
const editPatch = [
  {
    oldStart: 8,
    oldLines: 7,
    newStart: 8,
    newLines: 7,
    lines: [
      ' export function parseCount(text: string): number {',
      '   const trimmed = text.trim()',
      '-  const value = Number(trimmed || 0)',
      '+  const value = Number.parseInt(trimmed || "0", 10)',
      '   if (Number.isNaN(value)) {',
      '     return 0',
      '   }',
    ],
  },
  {
    oldStart: 30,
    oldLines: 5,
    newStart: 30,
    newLines: 6,
    lines: [
      '   return value',
      ' }',
      '+',
      '+export const DEFAULT_COUNT = 10',
      ' ',
      ' export function label(count: number): string {',
    ],
  },
]

/** Bash: every state of a shell call and its output. */
const bashFixture: GalleryFixture = {
  title: 'Tools: Bash',
  note: 'Queued, running (the bullet blinks), done with short and long output, stderr, no output, background, failed, interrupted.',
  rows: [
    queued('bash-queued', 'Bash', { command: 'pnpm install', description: 'Install dependencies' }),
    running('bash-running', 'Bash', { command: 'pnpm test --run', timeout: 120_000 }),
    done(
      'bash-short',
      'Bash',
      { command: 'git status --short' },
      { stdout: ' M src/app.ts\n?? notes.md', stderr: '', interrupted: false },
    ),
    done(
      'bash-four',
      'Bash',
      { command: 'ls' },
      { stdout: 'README.md\npackage.json\nsrc\ntests', stderr: '', interrupted: false },
    ),
    done(
      'bash-long',
      'Bash',
      { command: 'rg "parse\\(" src', timeout: 300_000 },
      { stdout: clippedOutput, stderr: '', interrupted: false },
    ),
    done(
      'bash-cwd',
      'Bash',
      { command: 'cd /tmp/build && ls' },
      { stdout: 'out\nlog.txt\nShell cwd was reset to /home/user/project', stderr: '', interrupted: false },
    ),
    done(
      'bash-stderr',
      'Bash',
      { command: 'node scripts/check.js' },
      { stdout: 'checked 12 files', stderr: 'warning: 2 files have no header', interrupted: false },
    ),
    done(
      'bash-empty',
      'Bash',
      { command: 'mkdir -p out/cache' },
      { stdout: '', stderr: '', interrupted: false },
    ),
    done(
      'bash-background',
      'Bash',
      { command: 'pnpm dev', run_in_background: true },
      { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b3f9a1' },
    ),
    done(
      'bash-grep-none',
      'Bash',
      { command: 'grep -r TODO docs' },
      { stdout: '', stderr: '', interrupted: false, returnCodeInterpretation: 'No matches found' },
    ),
    failed(
      'bash-failed',
      'Bash',
      { command: 'pnpm build' },
      'Exit code 2\nerror TS2322: Type string is not assignable to type number.\n  src/app.ts:14:7',
    ),
    interrupted('bash-interrupted', 'Bash', { command: 'sleep 600' }),
    done(
      'bash-multiline',
      'Bash',
      {
        command:
          'python3 - <<EOF\nimport json\nprint(json.dumps({"a": 1}))\nprint("a second statement that goes on")\nEOF',
      },
      { stdout: '{"a": 1}\na second statement that goes on', stderr: '', interrupted: false },
    ),
  ],
}

/** Read, Grep, Glob and the failures of file tools. */
const readFixture: GalleryFixture = {
  title: 'Tools: Read and search',
  note: 'Read of text, an image, a PDF and a notebook; Grep in its three modes; Glob; failures with their fixed rows.',
  rows: [
    done(
      'read-text',
      'Read',
      { file_path: '/Users/sample/project/src/app.ts' },
      {
        type: 'text',
        file: {
          filePath: '/Users/sample/project/src/app.ts',
          content: 'x',
          numLines: 120,
          startLine: 1,
          totalLines: 120,
        },
      },
    ),
    done(
      'read-one',
      'Read',
      { file_path: '/Users/sample/project/notes.md' },
      {
        type: 'text',
        file: {
          filePath: '/Users/sample/project/notes.md',
          content: 'x',
          numLines: 1,
          startLine: 1,
          totalLines: 1,
        },
      },
    ),
    done(
      'read-image',
      'Read',
      { file_path: '/tmp/screenshot.png' },
      { type: 'image', file: { base64: '', type: 'image/png', originalSize: 482_113 } },
    ),
    done(
      'read-pdf',
      'Read',
      { file_path: '/tmp/spec.pdf', pages: '1-3' },
      { type: 'pdf', file: { filePath: '/tmp/spec.pdf', base64: '', originalSize: 2_410_000 } },
    ),
    done(
      'read-notebook',
      'Read',
      { file_path: '/Users/sample/project/analysis.ipynb' },
      { type: 'notebook', file: { filePath: '/Users/sample/project/analysis.ipynb', cells: [{}, {}, {}] } },
    ),
    failed('read-missing', 'Read', { file_path: '/Users/sample/project/gone.ts' }, 'File does not exist.'),
    done(
      'grep-files',
      'Grep',
      { pattern: 'parseCount', path: 'src' },
      { mode: 'files_with_matches', numFiles: 4, filenames: ['a.ts', 'b.ts', 'c.ts', 'd.ts'] },
    ),
    done(
      'grep-content',
      'Grep',
      { pattern: 'TODO', output_mode: 'content' },
      { mode: 'content', numFiles: 2, numLines: 17, content: 'a.ts:3: TODO' },
    ),
    done(
      'grep-count',
      'Grep',
      { pattern: 'import', output_mode: 'count' },
      { mode: 'count', numFiles: 9, numMatches: 31, filenames: [] },
    ),
    done(
      'glob-one',
      'Glob',
      { pattern: '**/*.spec.ts' },
      { numFiles: 1, filenames: ['src/app.spec.ts'], durationMs: 12, truncated: false },
    ),
    failed('grep-failed', 'Grep', { pattern: '(' }, 'regex parse error: unclosed group'),
  ],
}

/** Edit and the diff view. */
const editFixture: GalleryFixture = {
  title: 'Tools: Edit and diff',
  note: 'Update with word-level highlights and two hunks; a creating Edit; an interrupted edit; a plan file.',
  rows: [
    done(
      'edit-two-hunks',
      'Edit',
      { file_path: '/Users/sample/project/src/count.ts', old_string: 'x', new_string: 'y' },
      {
        filePath: '/Users/sample/project/src/count.ts',
        structuredPatch: editPatch,
        userModified: false,
        replaceAll: false,
      },
    ),
    done(
      'edit-removed-only',
      'Edit',
      { file_path: '/Users/sample/project/src/util.ts', old_string: 'x', new_string: '' },
      {
        filePath: '/Users/sample/project/src/util.ts',
        structuredPatch: [
          {
            oldStart: 3,
            oldLines: 4,
            newStart: 3,
            newLines: 2,
            lines: [' const a = 1', '-// a note that is no longer true', '-const unused = 2', ' const b = 3'],
          },
        ],
        userModified: false,
        replaceAll: false,
      },
    ),
    done(
      'edit-create',
      'Edit',
      { file_path: '/Users/sample/project/src/new.ts', old_string: '', new_string: 'export {}\n' },
      {
        filePath: '/Users/sample/project/src/new.ts',
        structuredPatch: [{ oldStart: 1, oldLines: 0, newStart: 1, newLines: 1, lines: ['+export {}'] }],
        userModified: false,
        replaceAll: false,
      },
    ),
    done(
      'edit-wrapped',
      'Edit',
      { file_path: '/Users/sample/project/docs/guide.md', old_string: 'x', new_string: 'y' },
      {
        filePath: '/Users/sample/project/docs/guide.md',
        structuredPatch: [
          {
            oldStart: 40,
            oldLines: 2,
            newStart: 40,
            newLines: 2,
            lines: [
              ' Keep the heading short.',
              '-A paragraph in a guide is easier to read when its sentences stay short, so the reader can follow the argument without going back.',
              '+A paragraph in a guide is easier to scan when its sentences stay short, so the reader can follow the whole argument without going back.',
            ],
          },
        ],
        userModified: false,
        replaceAll: false,
      },
    ),
    interrupted('edit-interrupted', 'Edit', {
      file_path: '/Users/sample/project/src/count.ts',
      old_string: 'x',
      new_string: 'y',
    }),
    failed(
      'edit-failed',
      'Edit',
      { file_path: '/Users/sample/project/src/count.ts', old_string: 'x', new_string: 'y' },
      '<tool_use_error>String to replace not found in file.</tool_use_error>',
    ),
    done(
      'edit-plan',
      'Edit',
      { file_path: '/Users/sample/.claude/plans/sample-plan.md', old_string: 'a', new_string: 'b' },
      {
        filePath: '/Users/sample/.claude/plans/sample-plan.md',
        structuredPatch: [],
        userModified: false,
        replaceAll: false,
      },
    ),
  ],
}

/** Write: a new file, an update with a diff, an update without one. */
const writeFixture: GalleryFixture = {
  title: 'Tools: Write',
  note: 'A new file with its preview and the hint; an overwritten file with a diff; one too large to diff.',
  rows: [
    done(
      'write-create',
      'Write',
      { file_path: '/tmp/count-words.ts', content: clippedSource },
      {
        type: 'create',
        filePath: '/tmp/count-words.ts',
        content: clippedSource,
        structuredPatch: [],
        originalFile: null,
      },
    ),
    done(
      'write-small',
      'Write',
      { file_path: '/Users/sample/project/.gitignore', content: 'dist\nnode_modules\n' },
      {
        type: 'create',
        filePath: '/Users/sample/project/.gitignore',
        content: 'dist\nnode_modules\n',
        structuredPatch: [],
        originalFile: null,
      },
    ),
    done(
      'write-update',
      'Write',
      { file_path: '/Users/sample/project/src/count.ts', content: 'x' },
      {
        type: 'update',
        filePath: '/Users/sample/project/src/count.ts',
        content: 'x',
        structuredPatch: editPatch,
        originalFile: 'y',
      },
    ),
    done(
      'write-too-large',
      'Write',
      { file_path: '/Users/sample/project/data/table.json', content: '{\n  "rows": []\n}\n' },
      {
        type: 'update',
        filePath: '/Users/sample/project/data/table.json',
        content: '{\n  "rows": []\n}\n',
        structuredPatch: [],
        originalFile: null,
      },
    ),
    interrupted('write-interrupted', 'Write', { file_path: '/tmp/notes.md', content: 'draft' }),
    failed('write-failed', 'Write', { file_path: '/root/x.ts', content: 'a' }, 'EACCES: permission denied'),
  ],
}

/** Web tools, Skill, MCP and the fallback. */
const otherFixture: GalleryFixture = {
  title: 'Tools: web, skill, MCP and others',
  note: 'WebFetch, WebSearch, Skill, MCP in its states, and a tool the terminal has no name for.',
  rows: [
    done(
      'web-fetch',
      'WebFetch',
      { url: 'https://example.com/docs/intro', prompt: 'Summarize the page' },
      {
        bytes: 18_432,
        code: 200,
        codeText: 'OK',
        result: 'A summary',
        durationMs: 640,
        url: 'https://example.com/docs/intro',
      },
    ),
    running('web-fetch-running', 'WebFetch', { url: 'https://example.com/slow', prompt: 'Read it' }),
    done(
      'web-search',
      'WebSearch',
      { query: 'terminal bell escape sequence', mode: 'standard' },
      { query: 'terminal bell escape sequence', results: [], durationSeconds: 4, searchCount: 2 },
    ),
    done(
      'skill',
      'Skill',
      { skill: 'sample-skill' },
      { success: true, commandName: 'sample-skill', allowedTools: ['Read', 'Grep'], status: 'inline' },
    ),
    done(
      'mcp-text',
      'mcp__docs__search_pages',
      { query: 'rate limits', limit: 5 },
      'Page one: Limits\nPage two: Quotas\nPage three: Retries',
    ),
    done(
      'mcp-long',
      'mcp__docs__read_page',
      { id: 'page-42', options: { format: 'markdown', includeLinks: true, language: 'english', depth: 3 } },
      { head: 'Title\n\nIntro line\nSecond line\nThird line', lines: 380, chars: 52_000 },
    ),
    running('mcp-running', 'mcp__docs__search_pages', { query: 'webhooks' }),
    done('mcp-empty', 'mcp__docs__list_pages', {}, ''),
    done('unknown', 'FrobnicateTool', { target: 'alpha', depth: 2 }, { message: 'Frobnicated alpha twice' }),
    failed('tool-failed', 'mcp__docs__read_page', { id: 'missing' }, 'Error: page missing was not found'),
  ],
}

/** Agent calls and the agent tree. */
const agentFixture: GalleryFixture = {
  title: 'Tools: Agent',
  note: 'An agent that finished, one in the background, one running; the fetch helper; several agents folded into a tree.',
  rows: [
    done(
      'agent-done',
      'Agent',
      { description: 'Find   the\nconfig loader', subagent_type: 'Explore', prompt: 'Look for it' },
      {
        status: 'completed',
        agentId: 'a1',
        totalToolUseCount: 7,
        totalTokens: 41_200,
        totalDurationMs: 65_000,
        content: [],
        resolvedModel: 'sonnet',
      },
    ),
    done(
      'agent-async',
      'Agent',
      { description: 'Run the long audit', prompt: 'Audit everything' },
      {
        status: 'async_launched',
        agentId: 'a2',
        description: 'Run the long audit',
        prompt: 'Audit everything',
        outputFile: '/tmp/a2.output',
      },
    ),
    running('agent-running', 'Agent', {
      description: 'Review the diff',
      subagent_type: 'reviewer',
      prompt: 'Review it',
    }),
    done(
      'agent-fetch',
      'Agent',
      { description: 'Read the release notes', subagent_type: 'web-fetch', prompt: 'Fetch it' },
      {
        status: 'completed',
        agentId: 'a3',
        totalToolUseCount: 1,
        totalTokens: 900,
        totalDurationMs: 2000,
        content: [{ type: 'text', text: 'x'.repeat(3300) }],
      },
    ),
    group('agents-running', true, [
      running('g1', 'Agent', { description: 'Check the parser', subagent_type: 'reviewer', prompt: 'p' }),
      done(
        'g2',
        'Agent',
        { description: 'Check the writer', subagent_type: 'reviewer', prompt: 'p' },
        {
          status: 'completed',
          agentId: 'a5',
          totalToolUseCount: 3,
          totalTokens: 8000,
          totalDurationMs: 9000,
          content: [],
        },
      ),
      running('g3', 'Agent', { description: 'Check the tests', subagent_type: 'reviewer', prompt: 'p' }),
    ]),
    group('agents-done', false, [
      done(
        'h1',
        'Agent',
        { description: 'Check the parser', subagent_type: 'reviewer', prompt: 'p' },
        {
          status: 'completed',
          agentId: 'a6',
          totalToolUseCount: 3,
          totalTokens: 8000,
          totalDurationMs: 9000,
          content: [],
        },
      ),
      failed(
        'h2',
        'Agent',
        { description: 'Check the writer', subagent_type: 'reviewer', prompt: 'p' },
        'Agent stopped: out of turns',
      ),
    ]),
  ],
}

/** Folded runs of calls. */
const groupFixture: GalleryFixture = {
  title: 'Tools: folded runs',
  note: 'A live run with its latest file, a finished one, one with a failure, edits and git, calls that did not run.',
  rows: [
    group('fold-live', true, [
      done(
        'f1',
        'Grep',
        { pattern: 'parseCount' },
        { mode: 'files_with_matches', numFiles: 2, filenames: [] },
      ),
      done('f2', 'Grep', { pattern: 'label' }, { mode: 'files_with_matches', numFiles: 1, filenames: [] }),
      running('f3', 'Read', { file_path: '/Users/sample/project/src/count.ts' }),
    ]),
    group('fold-done', false, [
      done('d1', 'Grep', { pattern: 'a' }, { mode: 'files_with_matches', numFiles: 2, filenames: [] }),
      done('d2', 'Grep', { pattern: 'b' }, { mode: 'files_with_matches', numFiles: 1, filenames: [] }),
      done('d3', 'Grep', { pattern: 'c' }, { mode: 'files_with_matches', numFiles: 1, filenames: [] }),
      done(
        'd4',
        'Read',
        { file_path: '/p/a.ts' },
        {
          type: 'text',
          file: { filePath: '/p/a.ts', content: '', numLines: 3, startLine: 1, totalLines: 3 },
        },
      ),
      done(
        'd5',
        'Read',
        { file_path: '/p/b.ts' },
        {
          type: 'text',
          file: { filePath: '/p/b.ts', content: '', numLines: 3, startLine: 1, totalLines: 3 },
        },
      ),
      done('d6', 'Bash', { command: 'ls src' }, { stdout: 'a.ts', stderr: '', interrupted: false }),
      done('d7', 'Bash', { command: 'pnpm test' }, { stdout: 'ok', stderr: '', interrupted: false }),
      done('d8', 'mcp__docs__search_pages', { query: 'x' }, 'text'),
      done('d9', 'mcp__docs__read_page', { id: 'x' }, 'text'),
    ]),
    group('fold-failed', false, [
      done('e1', 'Bash', { command: 'pnpm lint' }, { stdout: 'ok', stderr: '', interrupted: false }),
      failed('e2', 'Bash', { command: 'pnpm build' }, 'Exit code 1'),
    ]),
    group('fold-edits', false, [
      done(
        'x1',
        'Edit',
        { file_path: '/p/count.ts', old_string: 'a', new_string: 'b' },
        { filePath: '/p/count.ts', structuredPatch: editPatch, userModified: false, replaceAll: false },
      ),
      done(
        'x2',
        'Bash',
        { command: 'git commit -m "count words"' },
        {
          stdout: '',
          stderr: '',
          interrupted: false,
          gitOperation: { commit: { sha: '3f9c2a41b7', kind: 'committed' } },
        },
      ),
      done(
        'x3',
        'Bash',
        { command: 'git push' },
        { stdout: '', stderr: '', interrupted: false, gitOperation: { push: { branch: 'feature/count' } } },
      ),
    ]),
    group('fold-notrun', false, [
      done(
        'n1',
        'Read',
        { file_path: '/p/a.ts' },
        {
          type: 'text',
          file: { filePath: '/p/a.ts', content: '', numLines: 3, startLine: 1, totalLines: 3 },
        },
      ),
      interrupted('n2', 'Read', { file_path: '/p/b.ts' }),
    ]),
  ],
}

/** The calls whose row the terminal does not draw, and the ones that draw result rows only. */
const hiddenFixture: GalleryFixture = {
  title: 'Tools: rows the terminal draws differently',
  note: 'TodoWrite, ToolSearch and task tools draw nothing; question and plan tools draw result rows without a call row; worktree tools.',
  rows: [
    {
      kind: 'reply',
      id: 'hid-lead',
      text: 'Nothing is drawn between this line and the next.',
      isFirstOfReply: true,
    },
    done(
      'todo',
      'TodoWrite',
      { todos: [{ content: 'a', status: 'pending', activeForm: 'a' }] },
      { oldTodos: [], newTodos: [] },
    ),
    done('tool-search', 'ToolSearch', { query: 'select:Read' }, { matches: [] }),
    done('task-create', 'TaskCreate', { subject: 'Write it' }, { task: { id: '1' } }),
    done(
      'ask',
      'AskUserQuestion',
      {
        questions: [
          {
            question: 'Which format?',
            header: 'Format',
            options: [{ label: 'JSON' }, { label: 'YAML' }],
            multiSelect: false,
          },
        ],
      },
      {
        questions: [
          {
            question: 'Which format?',
            header: 'Format',
            options: [
              { label: 'JSON', description: '' },
              { label: 'YAML', description: '' },
            ],
            multiSelect: false,
          },
        ],
        answers: { 'Which format?': 'YAML' },
      },
    ),
    interrupted('ask-declined', 'AskUserQuestion', {
      questions: [
        {
          question: 'Which port?',
          header: 'Port',
          options: [{ label: '3000' }, { label: '8080' }],
          multiSelect: false,
        },
      ],
    }),
    done('plan-enter', 'EnterPlanMode', {}, { message: 'Entered plan mode' }),
    done(
      'plan-exit',
      'ExitPlanMode',
      {},
      {
        plan: '## Plan\n\n- Parse the input\n- Write the output',
        isAgent: false,
        filePath: '/Users/sample/.claude/plans/sample-plan.md',
      },
    ),
    done(
      'worktree-enter',
      'EnterWorktree',
      { name: 'feature-count' },
      {
        worktreePath: '/Users/sample/project/.claude/worktrees/feature-count',
        worktreeBranch: 'feature-count',
        message: 'ok',
      },
    ),
    done(
      'worktree-exit',
      'ExitWorktree',
      { action: 'remove' },
      { action: 'remove', originalCwd: '/Users/sample/project', worktreePath: '/x', message: 'ok' },
    ),
  ],
}

/** The tool fixtures, for the gallery and for the specs. */
export const toolGalleryFixtures: GalleryFixture[] = [
  bashFixture,
  readFixture,
  editFixture,
  writeFixture,
  otherFixture,
  agentFixture,
  groupFixture,
  hiddenFixture,
]

/** Every Row of {@link toolGalleryFixtures}, flat. */
export const toolRows: Row[] = toolGalleryFixtures.flatMap((fixture) => fixture.rows)
