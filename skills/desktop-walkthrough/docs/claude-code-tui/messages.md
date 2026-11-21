# Claude Code 2.1.330 TUI: theme, transcript layout, message rows, markdown

Scope: the dark theme, how rows are stacked, the user prompt row, the assistant reply row and its
markdown, thinking, notices and system rows, slash command rows. Measurements are in terminal columns
("cols") and rows. Tool rows, the spinner row and the prompt input are in sibling documents.

Provenance tags: `[2.1.330]` read in the extracted modules (chunk file plus a search string that lands on
the place), `[screen]` seen on the live pane (115 cols wide), `[old]` only in the older readable tree.
Chunk files are under `/tmp/rea-cc/extracted/$bunfs/root/`.

The installed setup uses `theme: "dark"` and `showThinkingSummaries: true` in the user settings file
[screen/settings]; `maxProseWidth`, `syntaxHighlightingDisabled` and `showTurnDuration` are unset (defaults).

---

## 1. Theme (dark)

`[2.1.330]` chunk-1tyxkk56.js, the second theme object (search `userMessageBackground:"rgb(55, 55, 55)"`
or `claudeShimmer:"rgb(235,159,127)"`). Theme names: `dark`, `light`, `dark-ansi`, `light-ansi`,
`dark-daltonized`, `light-daltonized`; anything unknown falls back to `dark`. Names below are the program's own.

### 1.1 Named colours used by the transcript

| Name                                     | RGB                      | Where it shows                                                             |
| ---------------------------------------- | ------------------------ | -------------------------------------------------------------------------- |
| `text`                                   | 255,255,255              | assistant bullet, prompt text, selected/plain text                         |
| `inactive`                               | 153,153,153              | "dim" text, user-prompt pointer, queued prompt text                        |
| `inactiveShimmer`                        | 193,193,193              | spinner/dim shimmer (not in rows below)                                    |
| `subtle`                                 | 80,80,80                 | the "(N lines hidden)" rule label of a truncated prompt, very faint things |
| `promptBorder`                           | 136,136,136              | input box rules (see prompt doc)                                           |
| `claude` (brand orange)                  | 215,119,87               | brand orange; `claudeShimmer` = 235,159,127                                |
| `success`                                | 78,186,101               | finished tool bullet, completed task notification bullet                   |
| `error`                                  | 255,107,128              | error rows, failed task bullet                                             |
| `warning`                                | 255,193,7                | API-error bullet and text, killed-task bullet; `warningShimmer` 255,223,57 |
| `permission` / `suggestion` / `remember` | 177,185,249              | inline code and no-language code blocks, selected-row pointer              |
| `permissionShimmer`                      | 207,215,255              |                                                                            |
| `claudeBlue_FOR_SYSTEM_SPINNER`          | 147,165,255              | system spinner                                                             |
| `autoAccept` / `merged` / `skill`        | 175,135,255              | violet                                                                     |
| `planMode`                               | 72,150,140               | "Plan to implement" box colour                                             |
| `ide`                                    | 71,130,200               |                                                                            |
| `bashBorder`                             | 253,93,177               | the `! ` marker of a bash-mode prompt                                      |
| `background`                             | 0,204,204                |                                                                            |
| `professionalBlue`                       | 106,155,204              |                                                                            |
| `chromeYellow`                           | 251,188,4                |                                                                            |
| `fastMode` / shimmer                     | 255,120,20 / 255,165,70  |                                                                            |
| `briefLabelYou` / `briefLabelClaude`     | 122,180,232 / 215,119,87 | labels of the "brief" layout (see 3.6)                                     |

Backgrounds:

| Name                         | RGB       | Use                                     |
| ---------------------------- | --------- | --------------------------------------- |
| `userMessageBackground`      | 55,55,55  | user prompt row                         |
| `userMessageBackgroundHover` | 70,70,70  | same row under the pointer (mouse only) |
| `bashMessageBackgroundColor` | 65,60,65  | `! command` prompt row                  |
| `memoryBackgroundColor`      | 55,65,70  | `# note` prompt row                     |
| `composerSidebarBackground`  | 38,38,38  | side panels                             |
| `selectionBg`                | 38,79,120 | text selection                          |

Diff colours (used by tool rows): `diffAdded` 34,92,43; `diffRemoved` 122,41,54; `diffAddedDimmed` 71,88,74;
`diffRemovedDimmed` 105,72,77; word level `diffAddedWord` 56,166,96, `diffRemovedWord` 179,89,107.

Rainbow (the "ultrathink" keyword in a prompt, one colour per letter, cycling): red 235,95,87; orange
245,139,87; yellow 250,195,95; green 145,200,130; blue 130,170,220; indigo 155,130,200; violet 200,130,180
(shimmer variants exist). `[2.1.330]` same chunk, `rainbow_red`.

Sub-agent colours (`*_FOR_SUBAGENTS_ONLY`): red 220,38,38; blue 106,155,204; green 22,163,74; yellow 202,138,4;
purple 130,125,189; orange 217,119,87; pink 196,102,134; cyan 8,145,178.

Not in 2.1.330: `messageActionsBackground` of the old tree (selection of a row now uses the `suggestion` pointer colour).

### 1.2 How "dim" is actually coloured

There are three different things called dim. Using one value for all of them would be wrong.

1. **`dimColor` on a Text node** is not faint ink. It switches the colour to `inactive`, rgb(153,153,153), as an
   explicit foreground. `[2.1.330]` chunk-8bkqeb5d.js, search `Y.inactive`. `[screen]` dim wording such as the
   ` · summary` tag, `(ctrl+o to expand)`, the `⎿` gutter and notices are all `38;2;153;153;153`.
2. **Text that is already an ANSI string** (markdown output, command output, tool output) uses SGR 2 (faint)
   over the terminal's default foreground, with no colour of its own. `[screen]` the `… +N lines (ctrl+o to expand)`
   tail is bare SGR 2 with no colour. The mirror should draw it as default foreground at about 60 percent opacity
   (visually close to 153).
3. **Chalk dim inside markdown** (the language label above an unsupported code fence, the blockquote bar) is
   also SGR 2.

Plain assistant text, markdown paragraphs and list text carry no colour at all: they use the terminal default
foreground (white in the dark theme).

### 1.3 Glyphs shared by rows

`[2.1.330]` chunk-xcgcdx61.js (search `⏺`) and chunk-7r4ehpnw.js (search `pointerSmall`).

| Glyph                        | Code            | Name in program                                     |
| ---------------------------- | --------------- | --------------------------------------------------- |
| `⏺` (macOS) / `●` (other OS) | U+23FA / U+25CF | `BLACK_CIRCLE`, the row bullet                      |
| `❯`                          | U+276F          | `pointer` (prompt marker); `>` on limited terminals |
| `›`                          | U+203A          | `pointerSmall` (message-from-agent marker)          |
| `✔`                          | U+2714          | `tick`                                              |
| `⎿`                          | U+23BF          | result gutter                                       |
| `✻`                          | U+273B          | notice / compaction / turn-duration marker          |
| `∴`                          | U+2234          | thinking marker                                     |
| `∷`                          | U+2237          | notice-list marker and system-line marker           |
| `▎`                          | U+258E          | blockquote bar, quote-style left border             |
| `∙`                          | U+2219          | bullet operator                                     |
| `…`                          | U+2026          | ellipsis                                            |

---

## 2. Transcript layout

### 2.1 Row anatomy (`ki`, the "glyph row")

`[2.1.330]` chunk-bpbq4vg2.js (the whole file, 900 bytes). A flex row, full width, with `marginTop = 1` when the
row has `addMargin`. Left cell: the glyph, in a box of `minWidth 2` (so glyph plus one space = 2 cols), drawn from
the left edge. Right: the content, which wraps inside the remaining width. If the glyph is switched off (`false`)
the left cell is not drawn at all. Default glyph is `⏺`.

Continuation lines of a wrapped row are aligned under the content, so they start at column 2. `[screen]` every
reply continuation line begins with exactly two spaces.

### 2.2 Blank rows between rows

- Every message row is created with `addMargin = true`, which is one blank row above it. `[2.1.330]` chunk-w3q7cmdt.js
  (search `shouldShowDot:wt`): `addMargin` is false only when a metadata header row (timestamp or model name,
  transcript mode only) takes the position instead.
- Result lines (`⎿`) are NOT separate message rows with a margin: they sit directly under the tool row.
- The `Interrupted` row has no margin (it is a result line).
- Turn-duration row: margin above. Compaction row: `marginY 1` (blank above and below).
- `[screen]` assistant text, tool headers and thinking rows are each separated by exactly one blank row. A result
  block (`⎿ ...`) follows its tool header with no blank row.

### 2.3 Width

- Assistant prose wraps at the full terminal width minus the 2-col marker column (113 text cols at 115 cols)
  unless the user setting `maxProseWidth` (integer at least 40, unset by default) caps it. Tables and code blocks
  always keep the full width. `[2.1.330]` chunk-xcgcdx61.js, search `maxProseWidth:()=>`. `[screen]` Japanese
  assistant lines reach 115 columns total.
- Some single-line rows reserve 10 cols on the right: API-error row text box is `columns - 10`, the recap row
  also. `[2.1.330]` chunk-zprqxvft.js, search `N=S-10`.
- Lists wrap in a room of `min(columns - 4, maxProseWidth) - 10` (see 4.5).
- Tables are laid out inside `columns - 4` (see 4.7).
- The user prompt row wraps at `columns - 2 (pointer) - 1 (right padding)`.

### 2.4 The `⎿` result gutter (MessageResponse)

`[2.1.330]` chunk-b7hj8816.js, search `⎿`. Fixed 5-col gutter: two spaces, `⎿`, a space, a no-break space,
all dim. Content sits in a flex box to the right. A nested gutter is suppressed (the inner content is drawn
without a second `⎿`). Optional fixed `height` (used with 1 for one-line rows). `[screen]` rows look like
`  ⎿  text` with continuation lines indented 5 spaces.

The generic note row (`At`, chunk-c7hg08xn.js) is: tone `dim` (default, `inactive` grey), `warning`, or `error`,
text inside the gutter.

---

## 3. The user's prompt row (`UserMessage`)

`[2.1.330]` entry: chunk-zprqxvft.js `function Uh(` (box) and chunk-h4m8apfn.js `function hYn` (content); the plugin
hook is named `UserMessage` (chunk-h4m8apfn.js, search `N2("UserMessage"`).

### 3.1 Anatomy

```
(blank row, no background)
❯ prompt text, first line                      <- background rgb(55,55,55), full row width
  continuation line (aligned under the text)   <- same background
```

- Outer box: column, `marginTop 1`, `backgroundColor userMessageBackground` (55,55,55), `paddingRight 1`. The
  background fills the whole width of the row, including the blank space after the text, on every wrapped line.
- Inner row: pointer cell (`❯` followed by a space, 2 cols, does not shrink) then the text. The pointer is drawn
  in `inactive` (153,153,153); while a prompt is selected for editing it is `suggestion` (177,185,249). When
  selection highlighting is "off" the pointer cell is two plain spaces.
- Text colour is `text` (white). It is `inactive` (153) when the prompt is queued behind the running turn or has
  not been picked up by the model yet (`awaitingModel`). In that state the colour is forced to one flat grey
  (monochrome: bold or inline-code colours are not applied).
- Aria label of the pointer is `you:`.

### 3.2 Text, multi-line and long prompts

- Text of at most 4000 characters goes through the markdown renderer in "prompt mode": bold, italic and inline code
  are styled (inline code in 177,185,249); tables, blockquotes, horizontal rules, links, line-break syntax and
  setext headings are switched off (they stay literal). A paragraph break is a blank row inside the background.
  `[2.1.330]` chunk-h4m8apfn.js (search `K$o`, limit `4e3`), chunk-d167qrvj.js (the `$ya` parser config).
- Longer text, or text containing the ultrathink keyword, is drawn as plain text; the keyword letters are coloured
  with the rainbow colours of 1.1.
- Source newlines are kept. Wrapping is soft at the text width.
- Over 10,000 characters: only the first 2,500 and last 2,500 characters are kept, with a rule row between them whose
  title reads `(N lines, ~X KB hidden)` (`(~X KB hidden)` when whole lines are not the unit, `(N line hidden)` for one),
  drawn dim in the `subtle` colour, padded 3 cols in the plain layout. `[2.1.330]` chunk-h4m8apfn.js, search
  `hidden)`, constants `ue=1e4,fe=2500,he=2500`.

### 3.3 Prompt queued while the agent works

`[2.1.330]` chunk-3pqaw3hv.js (search `function aYt`), chunk-qnwkdfwp.js (the queue context).

- Queued prompts are drawn in a list directly above the input box, below the spinner, using the same row as above
  but with the text in flat `inactive` grey (3.1). The first queued row has a blank row above it.
- Each queued row is height-limited: the budget is a third of the terminal rows, never less than 3 rows per row.
- Queued background-task notifications are collapsed: at most 3 rows; beyond that one summary row
  `+N more tasks completed`.
- A hint line under the queue shows the send-now key when one is bound (see the prompt doc).

### 3.4 Pasted text and attached images

- Placeholders typed in the input are `[Pasted text #N +M lines]` (just `[Pasted text #N]` when M is 0) and
  `[Image #N]`. `[2.1.330]` chunk-bq31aqv6.js, search `Pasted text`.
- A sent image appears as its own row: `[Image #N]` (or `[Image]` when it has no id) in default colour, followed by
  an optional dim description. As a continuation of a prompt it is drawn inside the `⎿` gutter, as the start of a
  turn it is a glyph-less row with the usual blank row above. When the terminal supports hyperlinks the label links
  to the stored file. `[2.1.330]` chunk-zprqxvft.js, search `[Image #`.
- Not established: whether the transcript shows the placeholder or the expanded pasted text for a sent prompt.

### 3.5 Other user-turn row kinds

| Row                                                          | Look                                                                                                                                                                                                                                                                             | Source                              |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| Bash-mode prompt                                             | `! ` in `bashBorder` (253,93,177), then the command in `text`, on background (65,60,65), `paddingRight 1`                                                                                                                                                                        | chunk-zprqxvft.js `function Qbn`    |
| Memory note (`# text`)                                       | a `#` in `remember` colour and the text on background (55,65,70), then a dim row `Got it.`/`Good to know.`/`Noted.` (one picked at random)                                                                                                                                       | `function Em`                       |
| Plan sent to implement                                       | a titled box, title `Plan to implement`, colour `planMode` (72,150,140), body markdown                                                                                                                                                                                           | `function Zbn`                      |
| Interrupt marker                                             | see 6.3                                                                                                                                                                                                                                                                          |                                     |
| Task / agent notification                                    | glyph row: `⏺` coloured by status (completed = `success`, failed = `error`, killed = `warning`, otherwise `text`), then the one-line summary in default colour, then dim ` · <duration>` (duration format of 6.4) and dim ` · delivered to Claude as a ... result` when relevant | `function ph`, `function SC`        |
| Message from another agent, collapsed                        | glyph `›` (dim), dim text `Message from @<name> (ctrl+o to expand)`; plural `N messages from @<name>`                                                                                                                                                                            | chunk-z4vemndw.js (search `from @`) |
| Message from another agent, expanded (transcript or verbose) | dim `› Message from <name>`, then the message body, wrapped, inside the `⎿` gutter                                                                                                                                                                                               | chunk-zprqxvft.js `"Message from "` |
| Prompt that came from a plugin or another session            | an extra dim row above the prompt: `› From <name>` or `› From the <plugin> plugin` (dim, glyph `›`), then the normal prompt row                                                                                                                                                  | `function qo`                       |
| MCP resource update                                          | glyph `↻` in `success`, dim `<server>:`, target in `suggestion`, optional dim ` · reason`                                                                                                                                                                                        | `function Xj`                       |
| Fork directive                                               | dim `⑂` then the directive text, on the user background                                                                                                                                                                                                                          | `function Im`                       |

### 3.6 "Brief" layout (off by default)

When the brief mode is active the row has no background and no pointer: a label row (`You` in `briefLabelYou`
122,180,232, dim timestamp after it) and the text under it with 2 cols of left padding. `[2.1.330]`
chunk-h4m8apfn.js (search `briefLabelYou`). The installed setup does not use it. Not established: how to detect it.

---

## 4. The assistant's reply row (`AssistantMessage`)

`[2.1.330]` chunk-zprqxvft.js `function Yg(` (text), `function bn(` (hook wrapper named `AssistantMessage`).

### 4.1 Anatomy

```
(blank row)
⏺ first line of the reply          <- bullet U+23FA, colour text (255,255,255), box 2 cols wide
  continuation lines               <- 2-space indent
```

- Glyph row (2.1) with glyph `⏺`, colour `text`, aria label `claude:`. `[screen]` the reply bullet is `38;2;255;255;255`
  (white) whereas a finished tool bullet is `38;2;78;186;101` (green): do not mix them up.
- The bullet is drawn when `shouldShowDot` is true, which is the ordinary case for every text row. It is false only
  when the row directly follows a speaker-label row (agent or channel messages), where the content starts with no
  glyph cell at all.
- Each text block of a reply is its own row with its own blank row above and its own bullet. There is no
  "bullet only on the first block" rule in this build.
- Content is the markdown renderer of section 4.2 in a compact stack (no gap between children).
- Messages with a known API error text are drawn as notes instead (6.5).

### 4.2 Markdown engine

The program uses the `marked` lexer (GFM) with its own tokenizer overrides, then formats every token into an ANSI
string; tables, blockquotes and lists are drawn as layout components instead of strings. `[2.1.330]` chunk-d167qrvj.js
(formatter, search `case"blockquote"`), chunk-t7wkkwx8.js (components, search `function Zr(`). Code is highlighted with
highlight.js through ANSI named colours (4.4).

Block layout rules (chunk-t7wkkwx8.js, `function Zr`):

- Consecutive prose blocks are joined and printed as one text node; a source blank line between blocks is kept as
  exactly one blank row. Tight lists and a code block directly after a paragraph get no blank row; tables, block
  quotes and horizontal rules always get one blank row before them (and after, when something follows).
- Single newlines inside a paragraph are kept as line breaks (the text token carries the newline). Inferred, not
  seen on screen.
- Streaming: text is re-lexed incrementally and split into frozen chunks of at most 4096 characters, so partial
  tables, code fences and lists render as they grow.
- A paragraph that is plain text without any markdown trigger characters skips the lexer and is one paragraph.

### 4.3 Inline and block styles

| Markdown                | Drawing                                                                                                                                                                                                                                                                                                                                                                                                            |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `# H1`                  | bold + italic + underline, then one blank row                                                                                                                                                                                                                                                                                                                                                                      |
| `## H2` and deeper      | bold only, then one blank row (levels 2 to 6 look identical)                                                                                                                                                                                                                                                                                                                                                       |
| `**bold**`              | SGR bold. `[screen]` bold runs are bare SGR 1, no colour change                                                                                                                                                                                                                                                                                                                                                    |
| `*italic*` / `_italic_` | SGR italic                                                                                                                                                                                                                                                                                                                                                                                                         |
| `~~strike~~`            | SGR strikethrough on terminals known to render it (iTerm, VS Code, WezTerm, Ghostty, kitty, Alacritty, foot, Windows Terminal, Konsole, Zed, VTE 0.44 or later, Hyper, Tabby, JetBrains, mintty, Warp, rio, contour; env `CLAUDE_CODE_FORCE_STRIKETHROUGH` forces it); otherwise the literal text `~~text~~`. Never on Apple Terminal or `TERM=linux`. chunk-d167qrvj.js, search `CLAUDE_CODE_FORCE_STRIKETHROUGH` |
| `` `code` ``            | colour `permission` rgb(177,185,249), no background, no padding. `[screen]` `38;2;177;185;249`. A code span that is a bare http(s) URL becomes a hyperlink                                                                                                                                                                                                                                                         |
| `---`                   | the three characters `---` then a blank row (not a drawn rule)                                                                                                                                                                                                                                                                                                                                                     |
| escaped characters      | printed unescaped                                                                                                                                                                                                                                                                                                                                                                                                  |
| HTML                    | printed as written; link reference definitions are dropped                                                                                                                                                                                                                                                                                                                                                         |
| images `![alt](url)`    | `alt (url)` in text form, or just `url` when there is no alt text                                                                                                                                                                                                                                                                                                                                                  |
| task list items         | `[ ] ` / `[x] ` before the item text                                                                                                                                                                                                                                                                                                                                                                               |

### 4.4 Fenced and indented code

No frame, no left indent, no background: the code text is printed at the content indent.

- Fence with no language: every non-blank line's visible text in `permission` colour (177,185,249); leading and
  trailing blanks of each line are left uncoloured.
- Fence with a language the highlighter knows: highlight.js tokens coloured with ANSI named colours (dark theme):
  keyword, literal, class, `title.class` and name = bright blue; built_in = cyan; type = dim cyan; number = green;
  string and regexp = red; function and `title.function` = yellow; comment and doctag = green; meta and tag = grey;
  attr = cyan; addition = green; deletion = red; emphasis = italic; strong = bold; link = underline; everything
  else plain. In the light theme bright blue becomes plain blue. These are terminal-palette colours (indices
  9, 4, 6, 2, 1, 3, 8 of the user's terminal), so the mirror should map them through the HUD terminal's palette.
  `[2.1.330]` chunk-apafj80n.js, search `hljs-`.
- Fence with an unknown language label: a dim line holding the label, then the plain code.
- Indented (4-space) code: plain text, unstyled.
- When syntax highlighting is disabled (`syntaxHighlightingDisabled`) the code is unstyled except for the
  no-language rule. A very long message stops highlighting part way and inserts the dim line
  `Syntax highlighting stops here. This message has more code than is highlighted at once.`
  (chunk-t7wkkwx8.js, search `Syntax highlighting stops here`).

### 4.5 Lists

`[2.1.330]` chunk-t7wkkwx8.js (search `var Wr=10,Br=2`), chunk-d167qrvj.js (search `function P2s`, marker rules).

- Unordered marker is always `-` followed by a space, at every depth. `[screen]` `  - item` (2 cols of reply indent
  plus the marker); continuation lines align under the item text (4 cols).
- Ordered markers: depth 0 `1.`, depth 1 `a.` (letters), depth 2 `i.` (Roman, only when the list numbers stay at or
  under 3999), deeper `1.` again. Marker is followed by a space.
- Marker cell width is `max(2, marker width + 1)`. A nested list is indented by the parent's marker cell width
  (2 for `-`, 3 for `1.`), capped at 32 cols in total.
- Wrap room for list text is `min(columns - 4, maxProseWidth) - 10`.
- A blank row appears between items only when the source item ended with a blank line, a heading or a table.
- Lists above 300 items or 64 levels fall back to plain string rendering.
- Block elements inside an item (code, quote, table, nested list) keep the item text indent.

### 4.6 Block quotes

A left border of the "quote" style: character `▎` (U+258E) in dim, then one column of padding, then the text in
italic; nested quotes repeat the bar, one per level. `[2.1.330]` chunk-t7wkkwx8.js (`function xo`, search
`borderStyle:"quote"`) and chunk-d167qrvj.js (search `function Bt(`); the quote border character table is in
chunk-pb0vn6an.js (search `quote:{top:" ",left:`).

### 4.7 Links

`[2.1.330]` chunk-tqcvacgp.js (search `function YE`), chunk-d167qrvj.js (`case"link"`).

- Terminal supports hyperlinks (OSC 8): the link text is drawn in bright blue (`blueBright`, `blue` in the light theme)
  and carries the URL. The URL itself is not printed.
- Terminal without hyperlinks: if the text differs from the URL, `text (url)`; if they are equal, the URL only.
- `mailto:` links print the address only.
- `owner/repo#123` references become links to the issue (GitHub style) when hyperlinks are supported.
- Autolinks and bare URLs: printed as written.
- In prompt mode links are switched off (literal text).

The mirror should draw hyperlink-style text in bright blue (use the HUD terminal's bright-blue) and may show the
URL as a tooltip.

### 4.8 Tables

`[2.1.330]` chunk-t7wkkwx8.js (search `kind:"vertical"`; function `Or`, component `Dt`).

Box-drawing grid, each cell padded with one space on both sides:

```
┌───────┬───────┐
│  head │  head │     <- header cells centred
├───────┼───────┤
│ cell  │ cell  │     <- body cells aligned per the markdown column alignment (left by default)
├───────┼───────┤     <- a separator after EVERY body row
│ cell  │ cell  │
└───────┴───────┘
```

Border characters `┌ ─ ┬ ┐ │ ├ ┼ ┤ └ ┴ ┘`, in default foreground (not dim). In a row where cells have different line
counts the shorter cells are centred vertically.

Width algorithm (available = `columns - 4`):

1. Table frame cost is `1 + 3 * columns`. Budget for content = `max(available - frame, 3 * columns)`.
2. Natural width per column = longest cell (min 3). If the sum fits the budget, use natural widths.
3. Else if the sum of each column's longest word (min 3) fits, start every column at its longest word and share the
   leftover in proportion to (natural - longest word), rounded down.
4. Else columns are narrowed to a common cap (words hard-wrapped) until the sum fits.
5. If any cell would need more than 4 lines, or the drawn grid is wider than `columns - 4`, the grid is replaced by
   the **vertical layout**: for each row, one line per column `**Header:** value` (header in bold, value wrapped,
   continuation lines indented 2 cols), rows separated by a line of `─` of length `min(columns - 4, 40)`.
6. More than 200 body rows: the first 200 are shown and a line `… N more rows not shown` follows.
7. Screen-reader mode prints sentences instead (not relevant for the mirror).

Pipes inside inline code are escaped before parsing, so they do not split cells. East Asian wide characters are
measured by display width.

### 4.9 Line breaks and edge cases

- A hard break (two trailing spaces or a backslash) is a line break; in prompt mode it is off.
- Trailing blank rows of a block are trimmed; `&nbsp;` entities become plain spaces.
- Prompt-style XML wrapper tags are stripped from assistant text.

---

## 5. Thinking

`[2.1.330]` chunk-zprqxvft.js (search `"thinking:"` for `function Ur`, `Thinking…` for `function Ld`, `case"thinking"`).

| Case                                                                                     | Drawing                                                                                                                                                                                                                                                                                                                                            |
| ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ordinary thinking block, normal view                                                     | **not drawn at all** (only transcript mode or verbose mode shows it)                                                                                                                                                                                                                                                                               |
| Thinking block in transcript or verbose mode                                             | glyph row, glyph `∴` (U+2234), dim, aria `thinking:`, content = the thinking text as markdown in dim (whole text)                                                                                                                                                                                                                                  |
| Redacted thinking, transcript or verbose only                                            | glyph row, glyph `✻` dim, text `Thinking…` in dim italic                                                                                                                                                                                                                                                                                           |
| Thinking **summary** (setting `showThinkingSummaries`, which the installed setup has on) | drawn like an ordinary assistant reply: bullet `⏺` in `text` colour (only on the first block of a reply), the summary markdown, and a dim tail tag ` · summary` (a space, `·`, a no-break space, `summary`, dim) appended after the last line. `[screen]` white bullet, 2-space continuation, the tag trailing the last line in `38;2;153;153;153` |

The collapsed `Thought for Ns` wording is not a row: it lives in the spinner line (`thought for N s`, minimum 1 s,
`chunk-a824gc5p.js`, search `thought for`); see the spinner document.

`[screen]` The "thinking-log:" rows in this pane (a dim `⏺` with the label `thinking-log:` and a `✻` before the text)
are drawn by a third-party mod hooking the `AssistantMessage` site, not by core. The hookable sites are:
AskUserQuestion, UserMessage, AssistantMessage, ToolUse, ToolResult, ToolGroup, ToolProgress, CommandOutput,
Spinner, TurnDuration, InfoNotice, SessionMode, PromptHint, AbovePrompt, AgentRow, ContextMenu, Pane, Placed
(chunk-xfj2cwfv.js, search `"CommandOutput","Spinner","TurnDuration","InfoNotice"`). The mirror should not copy that look.

---

## 6. Notices and system rows

Important: the compact "system line" layout (a `∷` glyph row for every system message) exists in the code but its
gate function returns false in 2.1.330 (chunk-q4y63y6c.js, `function oV(){return!1}`), so every row below uses the
legacy layouts described here.

### 6.1 `InfoNotice`, the dim note under the logo

`[2.1.330]` chunk-w3q7cmdt.js (search `"InfoNotice"`, then `function Du`).

- Text is dim (`inactive`), optionally followed by ` · <command>` (for example the model note `Using <model> ... · /model`).
- Under the logo the notices sit in a column with 2 cols of left padding. When the "quote" presentation is on, they
  get a one-column left border `▎` (dim; brand orange for an announcement tier) and 1 col of padding.
- Inside a notice list (transcript context) each item gets the prefix `∷ ` (dim italic) and the text is italic,
  shifted 2 cols left (`marginLeft -2`) so the glyph hangs in the margin.

### 6.2 Compaction and context rows

- `✻ Conversation compacted (ctrl+o for history)`: glyph row, glyph `✻` dim, text dim; `(ctrl+o for the summary)`
  when a summary exists; `marginY 1`. When the summary was saved to a file an extra dim row follows inside a `⎿`
  gutter: `Earlier messages are saved in <path>`. `[2.1.330]` chunk-zprqxvft.js, search `Conversation compacted`.
- Context full: `Context limit reached · /compact or /clear to continue` in the `error` colour inside a `⎿` gutter
  ; `· auto-compact is off · /config to turn it on` is appended when
  auto-compact is off. Same shape for `Credit balance too low · Add funds: <url>`.

### 6.3 Interruption markers

`[2.1.330]` chunk-zprqxvft.js, search `What should Claude do instead`.

- `  ⎿  Interrupted · What should Claude do instead?` in dim, one row, truncated at the end if too narrow. Appears
  when the user cancels the running turn (Esc).
- Variant: `Interrupted` only (when the send-now path interrupted it).

### 6.4 Turn-duration row (`TurnDuration`)

`[2.1.330]` chunk-zprqxvft.js (search `function lM(`), format function chunk-f64qna2j.js (search `function Cn(`).

- Appended to the transcript when a turn finishes normally. It is a glyph row (blank row above): glyph `✻` dim, text dim:
  `<Verb> for <duration>` followed by ` · done <clock time>` (clock time of completion, `h:mm AM/PM` style, locale
  settings applied). `<Verb>` is a past-tense word from a short fixed list of eight, picked by hashing the message id
  (default `Worked`). `[screen]` none visible in the sampled history.
- Duration format: under 60 s: whole seconds `7s` (`0s` at zero); then `1m 6s`; `1h 2m 3s`; `1d 2h 3m`.
- Hidden when the setting `showTurnDuration` is false and nothing else is to show (default true).
- Extra segments, each dim: ` · N message(s) hidden (/focus to show)` (brief mode), the token budget summary, and
  ` · N still running`.
- Waiting variant: when background agents or dynamic workflows still run the row reads
  `Waiting for N background agent(s) to finish`, or `Waiting for N background agent(s) and M dynamic workflow(s) to finish`
  (counts bold dim, singular `agent`/`workflow`). When they end a new row with the real total replaces it.

### 6.5 API error rows

`[2.1.330]` chunk-zprqxvft.js (search `function Xg(`), chunk-865at33z.js (search `Vc="API Error"`, `XTt=1000`).

- Generic error text (starts with `API Error`): glyph row with `⏺` in `warning` (255,193,7) at `minWidth 2` and text in
  `warning`, text box `columns - 10` wide, truncated after 1000 characters with `…` and a dim `(ctrl+o to expand)`.
  A bare `API Error` becomes `API Error: Wait a moment and try again.`
- Known service errors (credit balance, invalid key, token revoked, timeout, org disabled, rate limit) are one-row
  notes: `⎿` gutter, text in `error` (255,107,128). The timeout note appends
  ` (API_TIMEOUT_MS=<n>ms, try increasing it)` when that variable is set.
- Rate-limit and quota texts have their own component with a countdown line; not detailed here.

### 6.6 Other dim rows seen in transcripts

- Stop-hook summary: `Ran N stop hook(s)` plus ` (ctrl+o to expand)`; errors in `error`/`warning`.
- Memory saved: dim `Saved N memory/memories` row.
- Hook notices in transcript mode: `<N> <Event> hook(s) ran` with the event name in bold dim.

---

## 7. Slash command rows (`CommandOutput`)

`[2.1.330]` chunk-zprqxvft.js (search `"CommandOutput"`, `function Rh(`), chunk-6bnjn6js.js (search `function F$o`).

- **Echo**: the typed command (`/name args`) is an ordinary user prompt row (section 3): `❯ /name args` on the grey
  background. There is no separate command-echo component in this build.
- **Output**: arrives as local-command text. It is drawn inside a `⎿` gutter (5 cols). Standard output goes through
  the markdown renderer (ANSI passthrough on, prompt tags kept); standard error is drawn in `error` colour, wrapped.
  Empty output draws nothing; the "(no content)" sentinel is dropped. A stdout block starting with `◇ ` or `◆ ` is
  treated as a cloud-launch status block and drawn in its own layout.
- Output of some commands is a structured "fork" status line: `fork:`-labelled row with state dim, name bold,
  optional ` · id` and chips dim (chunk-6bnjn6js.js `function Kt`).
- The mod hook `CommandOutput` receives `{command, args, text, isErrored}`.

---

## Not established

- The exact terminal-default foreground (plain unstyled text): the program emits no colour, so it is whatever the HUD
  terminal uses; white 255,255,255 matches the `text` colour used for bullets.
- Whether `Idi`'s " · summary" tag appears only when thinking summaries are on (the code shows a hint unless one
  setting-derived flag is true); the screen shows it with summaries on.
- Which condition makes `shouldShowDot` false besides "follows a speaker label" (the second flag in the call was not
  traced).
- Pasted-text expansion versus placeholder in a sent prompt (3.4).
- Precise cell colours of a drawn table border (assumed default foreground; the formatter emits no colour).
- On-screen examples of user prompt rows, tables, code fences, block quotes, `Interrupted`, `TurnDuration` and
  compaction rows: none were in the available pane history, so those rows rest on the module reading alone.
- The spinner-line orange seen on screen (240,165,37 and 225,138,67) differs from `claude` (215,119,87); that
  belongs to the spinner document.
- Exact right-edge reservation of ordinary prose: observed to be the full width on screen, but several row kinds
  subtract 10 explicitly; which others do was not enumerated.
