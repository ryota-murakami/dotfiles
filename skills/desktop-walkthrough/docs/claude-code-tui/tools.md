# Claude Code 2.1.330 terminal UI: tool call rows and their results

Scope: how the dark-theme terminal UI draws a tool call (the "call row"), what hangs under it (the "result
block", progress, hints), and how consecutive read/search calls fold into one line. Written for the Mirror,
which gets, per call, the tool name, `input`, `isRunning`, `isErrored`, `isInterrupted` and the stored
`output` (the plugin API's `ToolUse`, `ToolResult`, `ToolGroup` and `ToolProgress` rows).

Evidence tags: `[2.1.330]` read in the extracted modules (chunk file + search string), `[screen]` seen on the
real terminal (glyphs, colours, layout only; no content copied), `[old]` only in the older readable tree.
All chunk names are under `/tmp/rea-cc/extracted/$bunfs/root/`.

Conventions used below: "col" = terminal column (monospace cell), "row" = terminal line. `W` = terminal width
in columns. "dim gray" = RGB(153,153,153). "faint" = SGR 2 (half intensity of the default foreground).

## 0. Dark theme colours used by tool rows

`[2.1.330]` chunk-1tyxkk56.js, search `success:"rgb(78,186,101)"` (first palette object, white `text`).

| Name                                | RGB                    | Used for                                                    |
| ----------------------------------- | ---------------------- | ----------------------------------------------------------- |
| text                                | 255,255,255            | normal text                                                 |
| inactive                            | 153,153,153            | "dim" text, the result prefix, hints                        |
| success                             | 78,186,101             | finished-OK marker                                          |
| error                               | 255,107,128            | errored marker, error result text                           |
| warning                             | 255,193,7              | warning result rows                                         |
| claude                              | 215,119,87             | in-progress task glyph                                      |
| planMode                            | 72,150,140             | plan-mode rows                                              |
| diffAdded / diffRemoved             | 34,92,43 / 122,41,54   | whole-line diff backgrounds                                 |
| diffAddedWord / diffRemovedWord     | 56,166,96 / 179,89,107 | changed-word backgrounds                                    |
| diffAddedDimmed / diffRemovedDimmed | 71,88,74 / 105,72,77   | diff backgrounds in a dimmed (rejected/interrupted) preview |

"Dim" has two looks in the program. A `Text` with the dim flag is painted in `inactive` (153 gray)
`[2.1.330]` chunk-8bkqeb5d.js, search `Y.inactive`. Some hints (for example `… +N lines (ctrl+o to expand)` under
Bash) are written with SGR 2 on the default colour `[screen]`. The result prefix `⎿` was gray 153 without
faint `[screen]`. In HTML, use gray 153 for prefix glyphs and ~60% opacity of the default text colour (or gray 153) for
hints; the two are hard to tell apart.

## 1. Anatomy of a tool call row

`[2.1.330]` chunk-zprqxvft.js, search `userFacingToolNameBackgroundColor:Oe,isTransparentWrapper:Ce` (the row)
and chunk-we3cag6x.js, search `aria-label":t&&!n?"tool error:"` (the marker).

Left to right, all on one row, no wrapping between parts:

1. Marker box, 2 cols wide: the glyph then one space. Glyph is `⏺` U+23FA on macOS and `●` U+25CF elsewhere
   (chunk-xcgcdx61.js, search `x()==="macos"?"⏺"`). `[screen]` showed `⏺ ` then the name.
2. Display name, bold, never shrinks, truncated with an ellipsis only if it alone exceeds the row.
3. `(`, argument summary, `)` in the normal text colour (not bold), no space between name and `(`.
4. Optional ` · on <host>` in dim gray after `)` when the call runs on a remote host.
5. Optional tag (dim, one space before it). Only the Agent tool uses one: the model name in dim, or
   `a → b` when several models were used (`[2.1.330]` chunk-zprqxvft.js, search `.map(yi).join(" → ")`).

If the tool's argument summary is the empty string, the `(`...`)` is omitted. If the summary function returns
nothing (null), no row is drawn at all (see section 2: TodoWrite, ToolSearch, AskUserQuestion, task tools).
If the display name is the empty string, no row is drawn either.

Blank row: one empty row above a call row when it follows other content (`[screen]`: a blank row between the
previous line and `⏺ Bash`, none between the call row and its result block).

### Marker state table

| State (Mirror prop)                                                                   | Glyph | Colour                              | Blink                                                                                              |
| ------------------------------------------------------------------------------------- | ----- | ----------------------------------- | -------------------------------------------------------------------------------------------------- |
| Queued (not started, no result; `isRunning` false and no output)                      | `⏺`   | dim gray (153)                      | no                                                                                                 |
| Running (`isRunning`)                                                                 | `⏺`   | dim gray (153)                      | yes: glyph alternates with a blank, half-period 600 ms (visible 600 ms, blank 600 ms, cycle 1.2 s) |
| Succeeded                                                                             | `⏺`   | success green 78,186,101 `[screen]` | no                                                                                                 |
| Errored (`isErrored`)                                                                 | `⏺`   | error 255,107,128                   | no, always visible                                                                                 |
| Interrupted by the user (`isInterrupted`; counted as errored)                         | `⏺`   | error 255,107,128                   | no                                                                                                 |
| Neutral end (a call that ended by the user's choice, for example a declined question) | `⏺`   | dim gray                            | no                                                                                                 |

Rules behind the table:

- Blink exists only while unresolved, animation is allowed, the terminal has focus, and reduced motion is off.
  Without terminal focus the running marker stays steady (dim, visible). With the reduced-motion setting on, the
  running marker is solid white (255,255,255) with no blink. `[2.1.330]` chunk-we3cag6x.js (`d=600`), chunk-0t7st4dz.js
  (`prefersReducedMotion`), chunk-ddk99w14.js (terminal focus).
- Queued is told apart from running by "has no result and is not in the in-progress set"; the queued marker is
  drawn dim and does not blink (`[2.1.330]` chunk-zprqxvft.js, search `dimColor:Ze,children:Fc`).
- State classes the program computes (search `waiting:{isError:!1`): waiting, running, done, failed, refused,
  blocked, skipped, stopped, denied, unanswered. Error-coloured marker for: failed, refused, blocked, skipped,
  stopped, denied. Dim for the rest. `refused` (user said no), `blocked` (rule) and `skipped` map to the
  wording "not run"; `stopped` is "interrupted".

### Argument summary: cut and wrap

- The summary is a normal wrapping text. It wraps at the right edge of the terminal, and continuation rows start
  at the column of the `(`, that is col `2 + width(name)`. `[screen]`: for `Bash` the continuation started at
  col 6 (2 + 4); for a longer name (for example `Update`) it starts at col 8.
- Path-like arguments are shortened to the cwd-relative form (see Read below). In the non-expanded view, when the
  summary has file-path parts and would exceed `max(W - (marker 2) - width(name) - 2, 20)` columns, paths are
  middle-shortened to share the budget; if any path would get fewer than 12 columns, or the budget is 20 or less,
  the whole summary is left unshortened. At most 8 path parts take part. `[2.1.330]` chunk-zprqxvft.js, search `Aw=12,Lw=20,P0=8`.
- Bash summaries are cut by lines and characters (section 3, Bash). Other tools do not cut the summary;
  they show it whole and let it wrap.
- Collapse every run of whitespace in a description to a single space (Agent does this).

## 2. Per tool: the call row title

Display names come from each tool's `userFacingName`. "Summary" is what goes inside `( )`. Paths use the
display-path rule: if the path is inside the working directory show it relative; else if inside the home folder
show `~/...`; else show it absolute; a path containing a NUL byte shows `Path hidden (unsupported characters)`.
`[2.1.330]` chunk-2yx6c1y2.js, search `function Po(`. In the expanded transcript the full path is shown instead.

| Tool (input `name`)                          | Display name                                                                                                                                                                        | Summary in parentheses                                                                                                                                                                                      | Source                                                                                                                                                           |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Bash                                         | `Bash` (`SandboxedBash` when the sandbox-indicator env flag is on and the command is sandboxed)                                                                                     | the `command`; first 2 lines only and at most 160 chars; when cut, trimmed and followed by `…`                                                                                                              | chunk-c3wcapr4.js `var T=2,g=160`; chunk-bzyb60p0.js `userFacingName(e){if(!e)return"Bash"`                                                                      |
| Bash with `run_in_background` or `timeout`   | same as Bash                                                                                                                                                                        | same; the background/timeout facts show in the result and progress rows, not in the title                                                                                                                   | chunk-c3wcapr4.js                                                                                                                                                |
| PowerShell                                   | `PowerShell`                                                                                                                                                                        | the command                                                                                                                                                                                                 | chunk-e5txm7fq.js `userFacingName(){return"PowerShell"}`                                                                                                         |
| Read                                         | `Read` (`Reading Plan` for the plan file, `Read agent output` for a background task's output file)                                                                                  | display path; with `pages` ` · pages 1-3`; expanded view adds ` · lines a-b` or ` · from line n`                                                                                                            | chunk-d3cshc6y.js, chunk-p0p19erm.js `_Ya`                                                                                                                       |
| Edit                                         | `Update` (`Create` when `old_string` is empty; `Updated plan` for the plan file)                                                                                                    | display path                                                                                                                                                                                                | chunk-bzyb60p0.js `function R1o(`, chunk-c6sqp12q.js `function se(`                                                                                              |
| Write                                        | `Write` (`Updated plan` for the plan file)                                                                                                                                          | display path (as given, e.g. `/tmp/x.md` stayed absolute `[screen]`)                                                                                                                                        | chunk-bzyb60p0.js `function fHn(`                                                                                                                                |
| NotebookEdit                                 | `Edit Notebook`                                                                                                                                                                     | display path, then `@<cell id>` when a cell id is given (id shortened); expanded adds `, content: <first 30 chars>…, cell_type: …, edit_mode: …`                                                            | chunk-8003m6z4.js `function ie(`                                                                                                                                 |
| Grep                                         | `Search`                                                                                                                                                                            | `pattern: "<pat>"` then `, path: "<display path>"` when a path is given                                                                                                                                     | chunk-bzyb60p0.js `function X$e(`                                                                                                                                |
| Glob                                         | `Search`                                                                                                                                                                            | same as Grep (`pattern: "…", path: "…"`)                                                                                                                                                                    | same                                                                                                                                                             |
| Agent (older name Task)                      | the `subagent_type` as typed (for example the name of a custom or built-in agent); `Agent` when no type or the default general-purpose type; `Fetch` for the web-fetch helper agent | the `description`, whitespace-collapsed                                                                                                                                                                     | chunk-kb3nnh8q.js `function _Go(`, chunk-zprqxvft.js `function W9l(`                                                                                             |
| Skill                                        | `Skill`                                                                                                                                                                             | the skill name, e.g. `Skill(<skill-name>)` `[screen]`                                                                                                                                                       | screen; tool object not located                                                                                                                                  |
| TodoWrite                                    | empty name: no row                                                                                                                                                                  | none                                                                                                                                                                                                        | chunk-aw5nczax.js (`userFacingName(){return""}` with `renderToolUseMessage(){return null}`, search `toAutoClassifierInput(e){return\`${e.todos.length} items\``) |
| TaskCreate / TaskUpdate / TaskGet / TaskList | `TaskCreate` etc., but the summary function returns null so no row is drawn                                                                                                         | none                                                                                                                                                                                                        | chunk-aw5nczax.js `userFacingName(){return"TaskCreate"}` and neighbours                                                                                          |
| TaskOutput                                   | summary is the `task_id`; row hidden while the task is still working unless expanded                                                                                                |                                                                                                                                                                                                             | chunk-aw5nczax.js, search `userFacingName(){return Fk}`                                                                                                          |
| TaskStop                                     | `Stop Task`                                                                                                                                                                         |                                                                                                                                                                                                             | chunk-aw5nczax.js `userFacingName:()=>"Stop Task"`                                                                                                               |
| WebFetch                                     | `Fetch`                                                                                                                                                                             | the url (expanded: `url: "…", prompt: "…"`, `, offset: n`)                                                                                                                                                  | chunk-ww0784kh.js `xbo="Fetch"`; chunk-bzyb60p0.js `renderToolUseMessage({url:e,prompt:o,offset:r}`                                                              |
| WebSearch                                    | `Web Search`                                                                                                                                                                        | `"<query>"` in double quotes; expanded adds `, only allowing domains: a, b` and `, blocking domains: …`                                                                                                     | chunk-aw5nczax.js `userFacingName(){return"Web Search"}`                                                                                                         |
| ToolSearch                                   | empty name: no row                                                                                                                                                                  |                                                                                                                                                                                                             | chunk-bzyb60p0.js, search `userFacingName:()=>"",mapToolResultToToolResultBlockParam(e,o){if(e.matches.length===0)`                                              |
| AskUserQuestion                              | empty name: no call row (the answer shows as a result-style row, section 3)                                                                                                         |                                                                                                                                                                                                             | chunk-g44r9njd.js `userFacingName(){return""}`                                                                                                                   |
| EnterPlanMode / ExitPlanMode                 | empty name: no call row (result rows only)                                                                                                                                          |                                                                                                                                                                                                             | chunk-1ymj1rfb.js, chunk-gc5a361p.js                                                                                                                             |
| EnterWorktree / ExitWorktree                 | `Creating worktree` or `Entering worktree` (input has `path`); `Cleaning up worktree` when `action` is `remove`, else `Exiting worktree`                                            |                                                                                                                                                                                                             | chunk-aw5nczax.js                                                                                                                                                |
| Monitor                                      | `Monitor`                                                                                                                                                                           | the description, cut                                                                                                                                                                                        | chunk-18mwdpr8.js                                                                                                                                                |
| LSP                                          | `LSP`                                                                                                                                                                               |                                                                                                                                                                                                             | chunk-aw5nczax.js                                                                                                                                                |
| MCP tool `mcp__<server>__<tool>`             | `<server> - <tool title or tool name> (MCP)`, whitespace collapsed (the tool's own title annotation wins over its name)                                                             | every input key as `key: <JSON value>`, joined by `, `, no key shown if the input is empty; a value longer than 80 chars is cut and ends with `…` when not expanded `[old]`; verify cap in 2.1.330 not done | chunk-54d1gdxa.js `userFacingName(){let re=(Pe.annotations?.title                                                                                                |     | Pe.name)`; chunk-n6v2whwr.js |
| Unknown tool (not in the tool list)          | none in 2.1.330: the row is dropped and an internal error is logged (`Tool <name> not found`)                                                                                       |                                                                                                                                                                                                             | chunk-zprqxvft.js `"notFound"in ve?ve.notFound`                                                                                                                  |

Mirror fallback for an unknown tool (our choice, not the program's): draw `<name>(<input as key: JSON pairs joined by ", ">)`
with the same marker rules, so nothing silently disappears.

Agent name background: when the Agent call names a subagent type that has a configured colour, the name is drawn
inverse (black text, colour as background) instead of plain bold. Colours are the `*_FOR_SUBAGENTS_ONLY`
palette entries (red 220,38,38; blue 106,155,204; green 22,163,74; yellow 202,138,4; purple 130,125,189;
orange 217,119,87; pink 196,102,134; cyan 8,145,178). The general-purpose type has none. `[2.1.330]`
chunk-kb3nnh8q.js `function yGo(`, chunk-xfj2cwfv.js `function dct(`.

## 3. Per tool: the result block

### 3.1 Common frame

`[2.1.330]` chunk-b7hj8816.js (search `⎿ \xA0`).

- Prefix: two spaces, `⎿`, one space, one no-break space = 5 cols, dim gray, on the first row of the block. Content
  starts at col 5. Continuation rows of a block are indented 5 spaces with no prefix `[screen]`.
- Nested result frames do not draw a second `⎿`; they share the outer one. Content width is `W - 5` per nesting level.
- A block may hold several stacked parts (they sit under one `⎿` with no blank row between; a part that starts
  with its own `⎿` row appears as a separate row `[screen]`: the Bash timeout note).
- One-row messages (the `oneRow` form) are clipped to a single row.
- Tones: plain (default text colour), dim (default for notes; gray 153), warning (255,193,7), error (255,107,128).
  Chunk-c7hg08xn.js.

### 3.2 Expand hint line (used by almost every truncated block)

`[2.1.330]` chunk-f64qna2j.js `function $y(`, chunk-czdx79v3.js `function hc(`.

Text: `… +N lines` (U+2026, space, plus, count, space, `line` or `lines`; singular only when N is 1). Optionally
` (~K KB)` when the hidden text is 1000+ chars (K = hidden chars / 1000, rounded, at least 1). Then
` (ctrl+o to expand)` in dim. The hint is omitted when the transcript is already expanded or when it is nested in
a block that already shows it. Another unit can replace "line": `… +N tool uses` for agent rows. `[screen]` examples:
`… +21 lines (ctrl+o to expand)` (Bash, faint), `… +89 lines (~7 KB) (ctrl+o to expand)` (Write, gray 153).

### 3.3 Bash

`[2.1.330]` chunk-c3wcapr4.js (search `Running in the background`), chunk-54ceh2ac.js, chunk-6geanr2a.js.

Stack, top to bottom, inside one `⎿` block:

1. stdout, if not empty. Text colour normal.
2. For stored `persistedOutputPath` (very large output saved to a file): `… more output (<size> in all) saved to <path>`
   (only when expanded).
3. stderr, if it has non-blank content, in error colour (255,107,128), after stdout.
4. One status row when there is a background task, or when stdout is empty and stderr is blank:
   - background task: `Running in the background (↓ to manage)` (dim, hint in parentheses).
   - else `Interrupted` when the command was interrupted.
   - else the return-code interpretation string when the tool supplied one (for example a "no matches" exit).
   - else `(No output)`.
5. A timeout note `(timeout 1m 30s)` (dim, in parentheses) when the last progress record carried a timeout. `[screen]`
   showed this as its own `⎿` row after the output rows. It is the same elapsed/timeout formatter as the live row
   (section 5), so only the timeout part appears once the command is done.
6. If the stdout ends with the line `Shell cwd was reset to <dir>` (the tool appends it when the shell ended outside
   the project), the UI shows it as its own `⎿` row `[screen]`, gray 153, after the output.
7. An image result shows `[Image sent to Claude]` in one dim row.

Output truncation (not expanded), per stream:

- Lines are measured after soft-wrapping to width `max(W - 10, 10)` columns.
- Show the first **3** rows. If there are exactly 4 rows, show all 4 (it never writes `+1 line`). Otherwise show 3
  and the hint `… +N lines (ctrl+o to expand)` with N = rows hidden.
- Only the first `3 × width × 4` characters are examined; if the text is longer, the hidden count is estimated from
  newlines and width and is at least 1.
- Underline escape codes (SGR 4) are removed; trailing whitespace of each row is trimmed.
- When every output line is itself valid compact JSON (an object or an array) and the text is under 10,000 chars,
  each line is re-printed with 2-space indentation. URLs in the text become links.
- Expanded view: all rows, no hint.

Non-zero exit: the tool run fails, so the result is an error block (3.9): stdout is kept, then a line
`Exit code N` is appended; it shows as `Error: <output…>` in red, up to 10 rows then the hint. `[2.1.330]`
chunk-bzyb60p0.js, search `Ee.append(\`Exit code ${it.code}\`)`.

Timeout kill and other failures follow the same error path (the message comes from the tool).

### 3.4 Read

`[2.1.330]` chunk-d3cshc6y.js (search `Read PDF (`). One dim-less plain row (tone plain, normal colour):

| Output type                          | Wording                                                                                                                        |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| text                                 | `Read ` + **bold N** + ` line` / ` lines` (N from the returned line count; a trailing newline on the last line is not counted) |
| image                                | `Read image (<size>)`                                                                                                          |
| PDF                                  | `Read PDF (<size>)`                                                                                                            |
| PDF split into page images (`parts`) | `Read ` **bold n** ` page` / ` pages` ` (<size>)`                                                                              |
| notebook                             | `Read ` **bold n** ` cells`; with zero cells, `No cells found in notebook` in error colour                                     |

Size format: under 1024 bytes `N bytes`; otherwise `1.5KB`, `2MB`, `1.2GB` (one decimal, a trailing `.0` dropped,
no space before the unit). Errors: `File not found` (error tone) or `Couldn't read file` (error tone); anything
else goes through the general error block (3.9).

### 3.5 Edit, Write, NotebookEdit

`[2.1.330]` chunk-fzqmkppd.js (search `Added `), chunk-kat5c1mk.js (diff), chunk-vpbb6f67.js (Write), chunk-8003m6z4.js.

Edit result (and Write over an existing file), top to bottom in one block:

1. Summary row: `Added ` **N** ` line(s)` + `, ` + `removed ` **M** ` line(s)`. Counts are bold. Pieces appear only when
   greater than 0. When nothing was added, the removed piece starts with a capital: `Removed M lines`. `line` is singular
   only for 1. N and M count diff lines that start with `+` / `-`.
2. The diff (below), full width `W - 12` columns inside the block.

Plan-file edits show only the dim hint `/plan to preview`. Some collapsed file kinds (memory-style files) show the
summary only plus the expand hint.

Diff view (hunks):

- Context: 3 unchanged lines around each change (`Vtn=3`, chunk-hgbq13xy.js). Hunks are separated by a dim `...`
  row.
- Row layout: `[gutter][marker][code]`. Gutter = the line number right-aligned to the width of the largest line number
  in the hunk, plus one space; marker is `+`, `-` or a space. So row text starts with the number, one space,
  then `+`/`-`/space, then the code. Continuation rows of a wrapped line get a blank gutter and no marker.
- Line numbers: added and context rows use the new-file number; removed rows use the old-file number, and the
  numbering continues so that a run of removed rows is followed by added rows that restart at the same number.
- Colours (dark): added row background 34,92,43; removed row background 122,41,54; text white on those rows;
  context rows have no background and a dim gutter. The background fills the whole row width (the row is padded with
  spaces to the full width).
- Word-level highlight: when a run of removed rows is followed by a run of added rows, rows are paired in order. For
  each pair the changed words get the brighter backgrounds (removed 179,89,107, added 56,166,96). It is skipped when
  more than 40% of the characters differ (ratio of changed chars to total), in which case the whole row keeps the
  plain row colours.
- A line with an over-long single token is cut; the cut is marked with a dim note of how many chars were hidden.
- Syntax highlighting: code is token-coloured by a native highlighter (language from the file extension). Its token
  palette was not read; see Not established. Tabs in leading position are shown as two spaces.
- Not expanded vs expanded: the diff is always drawn in full width; there is no line-count cap on the diff body.
- Interrupted or rejected edits (the call never applied): the block is `Interrupted update to <bold dim path>` (or
  `Rejected update to …` / `Rejected write to …`), all dim, followed by the diff drawn with the dimmed backgrounds
  (71,88,74 / 105,72,77) and dim text.

Write, new file (`type` create): `Wrote ` **N** `line(s) to` **<bold display path>** `[screen]`, then a preview of the
content, then the expand hint `… +M lines (~K KB) (ctrl+o to expand)` `[screen]`.

- Preview: syntax-coloured code with a dim (faint, SGR 2) line-number gutter `[screen]`: one space, number right-aligned,
  one space (so `1` for single-digit numbers; wider if the shown lines reach 10). Wrapped rows have a blank
  gutter of the same width.
- Limit: at most 10 _rows_ (after wrapping at width `W - 12`), so fewer than 10 logical lines show when lines wrap
  `[screen]`: a 95-line file showed 7 logical lines and `+89 lines`, i.e. the count is the lines not fully shown.
  `(No content)` for an empty file.
- The count in the hint is logical lines not fully shown; `(~K KB)` appears when the hidden text is 1000+ chars.
- A Write over a file that was too large to diff shows the same preview plus `previous content replaced, no diff shown`.
- Condensed style (used inside agent progress): only `Wrote N lines to <path>`.
- Write that fails: `Couldn't write file` (error tone). Edit fails: `Couldn't edit file`, `File not found`, or
  `File must be read first` (normal tone), error tone for the first two.

NotebookEdit result: row `Updated cell ` **<cell id>** `:` then the new source as highlighted code (python
for code cells), indented 2 more columns. An error shows the error text in error tone. Failure wording:
`Couldn't edit notebook`. Interrupted/rejected: `Interrupted edit to <bold path> at cell <id>` or
`Rejected <edit_mode> cell in <path> …`, dim, with the new source dimmed below (not for delete).

### 3.6 Grep and Glob

`[2.1.330]` chunk-zprqxvft.js, search `function fd(d)` and `countLabel:"files"`. One plain row (not dim), then the
expand hint on the same row when the count is above 0:

| Mode                            | Wording                                        |
| ------------------------------- | ---------------------------------------------- |
| Glob, Grep `files_with_matches` | `Found ` **N** ` files`                        |
| Grep `content`                  | `Found ` **N** ` lines`                        |
| Grep `count`                    | `Found ` **N** `matches across` **M** ` files` |

The label is singular when N or M is exactly 1 (`1 file`), plural for 0 (`0 files`). The row is followed by a space
and `(ctrl+o to expand)`. Expanded: the header `Found …` (without hint) and below it the full file names or
matched lines. Errors: `File not found` or `Couldn't search files` (error tone).

### 3.7 Agent (older name Task)

`[2.1.330]` chunk-zprqxvft.js, search `Backgrounded agent`, `function EY(`, `function e_a(`.

Results:

- Finished: one row `Done (` parts `)` where parts, in order, are `<n> tool use(s)`, `<tokens> tokens` (compact: `1.2k`,
  `12k`, `1.5m`), and the duration when it is 1 second or more (`1m 5s`, `45s`), joined with `·`. With no parts the
  text is just `Done`. Then (not expanded) a second line, 2 spaces + dim `(ctrl+o to expand)`.
- Launched in the background: `Backgrounded agent` followed by the dim hint `(↓ to manage · ctrl+o to expand)` `[screen]`
  (the second part only when the call had a prompt; with expanded transcript the prompt is shown instead).
- Cloud agent: `Cloud agent launched · <task id> · <session url>`.
- Fetch-type agent: `Received <bold size>`, or `Not fetched (ctrl+o to expand)` when none of its fetches worked,
  and `Fetching in background` when launched async.
- Teammate/named spawn: the title shows `@<name>`.
- Expanded: prompt block, nested rows of everything the agent did, the final response text, then the Done row.

While the agent runs (live nested rows), under the call row:

- Before the first progress record: dim one row `Initializing…`.
- Then the last **7** of the agent's own tool calls, drawn as condensed rows (same title text, no marker, no
  blank rows), then the hint `… +N tool uses (ctrl+o to expand)` (N = earlier calls not shown).
  Runs of read/search calls inside the agent fold into one dim summary row (section 4 wording).
- If the terminal is too short (rows < `9 × parallel calls + 7`), a single dim row `In progress… · <n> tool uses ·
<tokens> tokens · (ctrl+o to expand)` replaces the nested rows (counts in bold).
- When the agent is interrupted or rejected: the nested rows stay, followed by the interrupted row (3.10).

Several agents started together fold into a group (the ToolGroup path, but only for agent calls):
header row `Running ` **n** ` agents…` with the loader marker; when all finished `n agents finished`, or `n background agents
launched (↓ to manage)` when all were async; when all agents share one type and it is not the generic one the word
`agents` is preceded by the type (`<type> agents`). When only some finished it counts `k of n`. Below the header each
agent has a tree row: `├` or `└` connector (2 cols plus space), then bold type name, ` (<description>)`, and while
running ` · N tool uses · 12k tokens`; the line below it, indented under the connector, is a dim `⎿  <last tool or
"Initializing…">`. Finished agents show their outcome word instead (`done`, `failed`, `denied`, `not run`,
`interrupted`, `no result recorded`).

### 3.8 Skill, WebFetch, WebSearch, MCP, question and plan tools, task list

Skill `[2.1.330]` chunk-e90w9jj0.js (search `Loaded skill`):

- Inline skill: one plain row `Loaded skill`, optionally ` · N tool(s) allowed`, optionally ` · <model>`. `[screen]`: `Loaded skill`.
- Forked skill: `Running in the background` or `Done`.
- Progress for a forked skill: `Initializing…` until the first record, then the last 3 nested condensed rows and
  `… +N tool uses`.
- Error: `Claude couldn't run /<name>. It runs only when you type it at the prompt.` for a model call of a user-only command.

WebFetch `[2.1.330]` chunk-8zeqzjk4.js: progress row `Fetching…` (dim). Result: `Received ` **<size>** ` (200 OK)` (status code
and text from the response; the size uses the Read size format). Expanded adds the fetched text below.

WebSearch `[2.1.330]` chunk-zprqxvft.js, search `Did `: result row `Did ` N ` search` / ` searches` (`no` instead of 0) and
` in <duration>` when 1 second or more (`1m 5s`). Progress (dim): `Searching: <query>`, then `Found N result(s) for "<query>"`.

MCP tool result `[2.1.330]` chunk-n6v2whwr.js (search `Large MCP response`):

- Content blocks: an image block is `[Image]` (one row); a text block is drawn exactly like Bash stdout (first 3 rows, `… +N
lines (ctrl+o to expand)`); no content is `(No content)` (one row).
- If the estimated size is over 10,000 tokens, a warning row above: `⚠ Large MCP response (~12.3k tokens) · can fill
context quickly` in warning colour (255,193,7).
- Progress: no data yet `Running…`; a progress number alone `Processing… <n>`; with a total, the message (dim) and below it a
  20-cell bar plus ` NN%` (dim); a download shows a file-transfer line instead.
- Slack-style "send message" results compress to `Sent a message to <channel link>`.

AskUserQuestion `[2.1.330]` chunk-zprqxvft.js (search `Answered Claude's questions:`): no call row. When answered, a marker row (the normal
assistant-row glyph, normal colour) `Answered Claude's questions:` followed by a `⎿` block, one row per question, gray
(`inactive`): `· <question> → <answer>`. Declined: marker row `Declined to answer Claude's questions:` (or `Interrupted · no
answer saved for Claude's questions:`) with `· <question> (<option labels joined by " / ">)` rows. When the question timed out:
`<glyph> No response after <duration> · continued without an answer`.

Plan tools: EnterPlanMode shows marker row `Entered plan mode` (marker colour planMode 72,150,140) with a `⎿` dim row
`Claude is exploring and planning an approach.`; declining shows `Declined to enter plan mode`. ExitPlanMode shows
`Approved Claude's plan` (planMode colour) and below it `Plan saved to: <path> · /plan to edit` (dim) and the plan text;
an empty plan shows `Exited plan mode`.

Worktree tools: `Switched to worktree on branch <bold branch>` then dim path; `Kept worktree (branch <bold b>)` /
`Removed worktree`, then dim `Returned to <dir>`.

TodoWrite and the task tools draw no row of their own. The checklist is a separate panel under the spinner
(`[2.1.330]` chunk-pv97d3wp.js, search `squareSmallFilled`):

- Header (only when shown standalone): bold `<done>/<total>` then ` tasks done`, then `, N in progress` in dim.
- One row per task: glyph + space + subject.
  - completed: `✔` U+2714 in success green, subject dim and struck through.
  - in progress: `◼` U+25FC in claude orange (215,119,87), subject bold. Active form (present-tense label) can appear
    after it dim.
  - pending: `◻` U+25FB in the default colour, subject normal.
  - blocked tasks add dim ` › blocked by #id, …`; an owner adds `@name`.
- Order: completed first, then in progress, then pending (unblocked before blocked). Overflow collapses to a dim line
  `… +N tasks (<k in progress, k open, k done>)`.

### 3.9 Errors

`[2.1.330]` chunk-r8cgv6h8.js (search `Tool execution failed`).

- The tool error text has its `<tool_use_error>` wrapper stripped. If it already starts with `Error: ` or `Cancelled: ` it is
  kept; if it starts with `InputValidationError: ` (not expanded) it becomes `Invalid tool parameters`; no text at all
  gives `Tool execution failed`; otherwise `Error: ` is put in front.
- Drawn in error colour (255,107,128) inside the `⎿` block, first 10 rows only (not expanded), then the hint `… +N lines
(ctrl+o to expand)` in dim gray. Expanded shows everything.
- Several tools replace the raw error with a short fixed row in error tone (`File not found`, `Couldn't read file`,
  `Couldn't edit file`, `Couldn't write file`, `Couldn't search files`, `Couldn't edit notebook`) unless the denial came from a
  permission rule.
- Marker: error colour (section 1).

### 3.10 Interrupted, rejected, waiting

- Interrupted result row: `Interrupted · What should Claude do instead?` in dim, one row, truncated at the row end;
  just `Interrupted` when it follows another stop message `[2.1.330]` chunk-zprqxvft.js (search `What should Claude do instead?`).
- Rejected (user said no): per tool; edits show `Rejected update to <path>` (see 3.5). The generic row is `Rejected` in
  warning tone.
- Queued call (not started): no result row for most tools; Bash shows `Waiting…` (dim, one row).
- Running call with no progress data yet: Bash shows `Running…` (dim, one row). MCP also `Running…`.
- Waiting for the user to grant permission: dim one row `Waiting for permission…`.
- Classifier checking (when enabled): `Bash classifier checking…` / `Auto classifier checking…`, dim `[old]`.
- Hook activity under a call: while PreToolUse/PostToolUse hooks run, `Running <bold PreToolUse> hook…` (or `hooks…`); expanded
  view shows `N <bold PreToolUse> hook ran` afterwards.

## 4. Folded runs (ToolGroup)

`[2.1.330]` chunk-zprqxvft.js, search `useRenderInput("ToolGroup"` for the props (`calls`, `isActive`, `isExpanded`,
`isCallsOnly`) and `function Ey(` for the line.

Consecutive calls that only read, search or list (plus, depending on build flags, edits, shell commands, MCP calls,
agent runs, memory recall) fold into one line while not expanded. The line is a sequence of clauses joined with `, `; the
first clause has its first letter capitalised; counts are bold; nouns are singular for 1.

Clause order and wording (active = group still running, done otherwise):

| Order                             | Active                                   | Done                                                                                                                                                                                                                                                                                   | Object                                                                   |
| --------------------------------- | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| thinking                          | `Thinking for <duration>`                | `Thought for <duration>`                                                                                                                                                                                                                                                               | duration bold, min 1s                                                    |
| edits                             | `editing`                                | `edited`                                                                                                                                                                                                                                                                               | `N file(s)` then ` +A -R` counts                                         |
| scratchpad                        | `making`                                 | `made`                                                                                                                                                                                                                                                                                 | `N scratchpad edit(s)` ` +A -R`                                          |
| commits / pushes / branches / PRs | (fixed verbs)                            | `committed <shas>`, `amended commit`, `cherry-picked`, `pushed to <branches>`, `merged`, `rebased onto <ref>`, `created`, `edited`, `commented on`, `closed`, `reopened`, `marked ready`, `marked draft`, `enabled auto-merge on`, `disabled auto-merge on` + PR number or sha in bold |
| frame                             | `publishing`                             | `published`                                                                                                                                                                                                                                                                            |                                                                          |
| search                            | `searching for`                          | `searched for`                                                                                                                                                                                                                                                                         | `N pattern(s)`                                                           |
| read                              | `reading`                                | `read`                                                                                                                                                                                                                                                                                 | `N file(s)`                                                              |
| list                              | `listing`                                | `listed`                                                                                                                                                                                                                                                                               | `N director(y/ies)`                                                      |
| MCP                               | `calling`                                | `called`                                                                                                                                                                                                                                                                               | server name(s) joined by `, `, then ` N times` when above 1              |
| agent                             | `running`                                | `ran`                                                                                                                                                                                                                                                                                  | `N agent(s)`; one agent with a description: `agent · <bold description>` |
| other tools                       | `calling`                                | `called`                                                                                                                                                                                                                                                                               | `N tool(s)`                                                              |
| shell                             | `running`                                | `ran`                                                                                                                                                                                                                                                                                  | `N shell command(s)`                                                     |
| not run                           | `no result recorded for` / `did not run` | same                                                                                                                                                                                                                                                                                   | `N call(s)` (`other call(s)` when after other clauses)                   |
| memory                            | `recalling` / `searching` / `writing`    | `recalled` / `searched` / `wrote`                                                                                                                                                                                                                                                      | `N memory/memories`; `searched memories`                                 |
| hooks                             |                                          | `ran N PreToolUse hook(s) (<duration>)`                                                                                                                                                                                                                                                | only when the line would otherwise be empty                              |

Example done lines (constructed from the table): `Searched for 3 patterns, read 2 files`;
`Searching for 1 pattern, reading 2 files…`.

Line layout:

- Row: marker box (2 cols) + the clause text + (while active) an elapsed suffix ` · <duration>` after 2 seconds, in dim, then
  `…` while active and no detail hint, then a space and `(ctrl+o to expand)` (dim) when not expanded.
- Marker: while active the same loader as a call row (dim, blinking); when done a blank 2-col box (no glyph) and the whole line
  is dim gray; an error in the group colours the marker error colour and adds ` N failed` in error colour at the end.
- Active detail row under the line: `⎿` block (5-col gutter) with the latest item as a hint: the last read file (display
  path), or `"<last search pattern>"` in quotes, or a shell command's first lines (up to 2 rows plus `…`), or an MCP
  progress text/percentage. Hints longer than the width wrap in the right column. For a running shell command with
  progress, below the hint the live output tail (5.2) is drawn.
- Blank row above the whole line (margin).
- Expanded (ctrl+o): the group dissolves into the individual call rows and results.

Agent runs fold with the agent group layout in 3.7, not with this line.

## 5. Progress under a running call (ToolProgress)

### 5.1 Bash start

`[2.1.330]` chunk-jannkkyp.js (search `Running… `), chunk-d8n9recq.js (search `run in background`), chunk-bzyb60p0.js (search `Dzo=2000`).

- From the moment the call starts and until the first record: one row `Running…` (dim) under a `⎿` frame.
- The command emits a progress record about every 1 second once it has been running 1 second; each record carries the output tail,
  total lines and bytes, elapsed seconds, and the timeout when one was given.
- After 2 seconds a "background hint" record is emitted (when not already backgrounded): a dim row, indented 2 columns, reading
  `(ctrl+b to run in background)`. Inside tmux the key is shown as `ctrl+b ctrl+b (twice)`. The key comes from the user's key
  bindings, so it may differ. It stays until the call ends or is backgrounded.

### 5.2 Elapsed and output tail

Under the `⎿` frame:

- No output yet: `Running… ` (dim, trailing space) then `(<elapsed>` `·` `timeout <duration>)` in dim: parts are the elapsed time
  (shown once progress exists) and `timeout 2m` (shown when a timeout was set, trailing zero units dropped: `2m`, `1m 30s`).
  Either part may be missing; the parentheses and `·` adjust. Example: `Running… (12s · timeout 2m)`.
- Output present: the last **5** rows of output (wrapped at `W - 5` columns, only the trailing rows kept), dim gray text; then on one
  line (items 1 column apart, dim): `… +N lines` (N = total lines minus rows shown, plus lines dropped by wrapping), or `~<total> lines`
  when byte and line totals are known, then `(<elapsed> · timeout <…>)`, then the byte size (`1.2KB`).
- Duration format (`format of Cn`): under 60 s `Ns` (`0s`, `45s`); 1 min and above `Xm Ys`, hours `Xh Ym Zs`, days `Xd Xh Xm`.
  With the trailing-zero option, `2m`, `1h 5m`, `3d`.

### 5.3 Other tools

- WebFetch `Fetching…`; WebSearch, MCP and Agent as in 3.7 and 3.8; Skill (forked) as in 3.8.
- Tools without a progress renderer show nothing under the call row while running (the dim marker alone).

## 6. Expanded form (ctrl+o transcript)

In the expanded transcript, every call row shows its full title (no 2-line/160-char cut on Bash, full path instead of
the cwd-relative path, extra arguments such as Read's `lines a-b`, NotebookEdit's cell content, WebSearch's domain lists, WebFetch's
prompt), every result shows all of its text (no `… +N lines`, no `(ctrl+o to expand)` hints, no 3/5/10-row caps), write previews
show the whole file, agents show their prompt, nested rows and final response, folded runs dissolve into their individual calls,
hidden-name tools stay hidden, error blocks show the whole text, and the dim `Waiting…`/`Running…` placeholder rows are replaced by the
same content as in the live view. The Mirror's live view does not draw any of this; implement only the collapsed forms above.

## Not established

- Syntax token colours inside Write previews and diffs (a native highlighter with theme-based colours); only row/gutter/background
  colours are given.
- The exact row-wrapping rule of the native diff renderer's split gutter (used when line numbers have more than one digit width);
  the fallback renderer rules are given.
- Whether a `Skill` call's title is just the skill name for namespaced or argument-bearing calls (only the plain form was seen).
- The Edit-tool title when the input uses the batched `edits` array (it shows `Update`; the preview of each edit is not drawn in the title).
- Exact title form for Monitor, LSP, EnterWorktree arguments.
- The marker for the "neutral end" state is dim in the code; which tools set that flag (it looks tied to choice-ending tools such as
  questions and plan mode) was not enumerated.
- MCP argument summary value cap (80 chars) is from the older tree only; the 2.1.330 summary function body was not located.
- Blink was not observed on screen (no running call was visible); the period comes from the code.
- Per-tool result wording for tools not listed (Monitor, LSP, scheduled tasks, connectors, artifacts, workflows) was only skimmed.
- The Agent name background colour for a given agent type depends on the agent definition's colour, which the Mirror does not receive.
