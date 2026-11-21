# Claude Code 2.1.330 TUI: spinner row, prompt input, footer, session start

Reference for the Mirror (HTML, monospace). Dark theme only. Measurements are in terminal
columns ("cols") and rows. Tags: `[2.1.330]` read in the extracted modules (chunk file plus a
search string), `[screen]` seen on the real terminal, `[old]` only in the older readable tree and
not confirmed. Wording of rules is our own; no code is reproduced.

Chunk files below are in `/tmp/rea-cc/extracted/$bunfs/root/`. Identifiers are minified and
differ per chunk, so search by the quoted strings.

## 0. Dark theme colours used here (RGB)

`[2.1.330]` chunk-1tyxkk56.js, search `claudeShimmer:` (the 5th of 6 palettes, selected by default,
is the dark one; the screen matches it).

| Theme name                           | RGB                | Used for                                                            |
| ------------------------------------ | ------------------ | ------------------------------------------------------------------- |
| claude                               | 215,119,87         | spinner glyph and verb at rest, mascot body                         |
| claudeShimmer                        | 235,159,127        | light passing over the verb, flash colour                           |
| claudeBlue_FOR_SYSTEM_SPINNER        | 147,165,255        | verb/glyph while hooks run or compaction (system)                   |
| claudeBlueShimmer_FOR_SYSTEM_SPINNER | 177,195,255        | light colour for the above                                          |
| inactive                             | 153,153,153        | everything drawn "dim": bracket text, tip, prompt marker, hint text |
| inactiveShimmer                      | 193,193,193        | slow pulse of the "thinking" text                                   |
| promptBorder                         | 136,136,136        | the two rules around the input                                      |
| bashBorder                           | 253,93,177         | bash mode rule, `!` marker, "! for shell mode"                      |
| planMode                             | 72,150,140         | plan mode pill                                                      |
| autoAccept                           | 175,135,255        | accept-edits pill                                                   |
| warning                              | 255,193,7          | thinking >10 s tint, auto-mode pill                                 |
| error                                | 255,107,128        | stall tint, bypass and dont-ask pills                               |
| background                           | 0,204,204          | "N background tasks" pill                                           |
| text                                 | 255,255,255        |                                                                     |
| clawd_body / clawd_background        | 215,119,87 / 0,0,0 | mascot                                                              |

"Dim" in this program is drawn with the `inactive` colour, not the terminal faint attribute
`[screen]`: every dim run on the real screen was the plain colour 153,153,153 with no SGR 2.

## 1. Spinner row

Code: `[2.1.330]` chunk-a824gc5p.js (search `thought for `): states, colours, bracket. chunk-pv97d3wp.js
(search `tengu_shining_fractals`): verb choice, tip line. chunk-9rvw567f.js (search `Beboppin`): the
per-agent spinner state store and the verb list. chunk-gdmb039p.js: glyph frames and colour helpers.
Older tree: `src/components/Spinner/SpinnerAnimationRow.tsx`; 2.1.330 differs (thinking wording by
duration, stall threshold 10 s not 3 s, `tool-done`, `recovering`).

### 1.1 Layout

One row (it wraps to a second row only if the terminal is too narrow; the width gating below
normally prevents it), full width, with one blank row above it (top margin 1). Left to right:

1. Glyph box, width 2 cols (glyph, then one cell), starting at column 0. `[screen]`, `[2.1.330]`.
2. Verb text including its trailing ellipsis, then one space in the same colour.
3. Bracketed status `( … )` when it has content (section 1.6). A plain space precedes `(`
   because of step 2. Example seen on screen: `✶ Wrangling… (20m 10s · ↓ 84.6k tokens)`.

Below the row: either the tip line (1.10) or a single blank row `[screen]` (one space) before the top
rule of the input box. Hooks/compaction hints and task lists use the same sub-row (1.10).

### 1.2 Glyph

- Frame set `[2.1.330]` chunk-gdmb039p.js: `·` `✢` `✳` `✶` `✻` `✽` (U+00B7, 2722, 2733, 2736, 273B,
  273D). In Ghostty (TERM `xterm-ghostty`) the last one is `✻` instead of `✽`; in a `linux` TERM the
  glyph set is the same except `*` replaces `✳`.
- Frame choice: not a fixed-rate loop. The index is the cosine-eased value
  `round(5 * (1 - cos(2π t / 2000 ms)) / 2)` into the six glyphs, so the glyph rises
  `· → ✽` and falls `✽ → ·` once per 2 s period. Timer tick for the redraw is 100 ms, or 50 ms in
  `requesting` mode. Phase is absolute wall-clock based, not tied to the start of the turn.
- Reduced motion (user setting `prefersReducedMotion`, or the terminal's accessibility mode): a
  single `●` (U+25CF) whose colour pulses between the base colour darkened 50 % toward black and the
  base colour, on the same 2 s cosine period. No frames, no verb light, no counting animation.
- Colour: `claude` at rest. When stalled (1.8) it fades toward `error`; when thinking longer than 10 s
  (1.5) it fades toward `warning`, and is bold once the thinking tint is ≥ 0.5 (not while stalled).
  When a system override colour is set (hooks, compaction) the glyph and verb use
  `claudeBlue_FOR_SYSTEM_SPINNER` and no tinting applies.
- Reduced-motion variant for the glyph box is also 2 cols wide, height 1.

### 1.3 Verb (the word)

`[2.1.330]` chunk-pv97d3wp.js, search `tengu_shining_fractals`. Priority:

1. An override message (hooks: `Running PreCompact hooks…`, `Running PostCompact hooks…`, a generic
   "Running hooks…" text for others; compaction: `Compacting conversation`; plugin API `message`).
2. The active form of the current task: the first task whose status is neither pending nor
   completed (i.e. in progress), whitespace collapsed, truncated to the row width. Only for the
   main agent or the agent that owns the task.
3. The per-turn default verb: one word chosen at random from a built-in list of about 187
   present-participle words (the list lives in chunk-9rvw567f.js); the user's `spinnerVerbs`
   setting either appends to it or replaces it (`mode: append | replace`). It is picked when the
   spinner state for an agent is created and re-picked each time overrides are reset (each new turn),
   so the word stays constant during a turn. Fallback word if the list is empty: `Working`.

Ellipsis: the message is followed by `…` (U+2026) unless it already ends in `…` or `...`. So a verb
is displayed as `Wrangling…` and an override as `Running PostCompact hooks…`.

### 1.4 Light running over the verb

`[2.1.330]` chunk-a824gc5p.js, search `claudeShimmer`.

- Width: 3 cells (the character cells whose start column lies in [g-1, g+1] around a moving centre
  g). Colour `claudeShimmer` (or the override's shimmer colour) on the rest in the base colour.
- Speed and direction by mode:
  - `requesting`: centre moves left to right, one cell every 50 ms.
  - `responding`, `thinking`, `tool-input`: centre moves right to left, one cell every 200 ms.
  - Both sweep from 10 cells outside one edge to 10 cells outside the other, so one pass takes
    `(verbWidth + 20)` steps and then repeats.
  - `tool-use`: no travelling light. The whole verb breathes between `claude` and `claudeShimmer`
    with a sine of period 2 s (`(sin(π t/1000)+1)/2`, quantised to 1/8 steps). `[screen]` saw the
    whole word in 235,159,127 at one instant.
- No light while stalled (1.8) or in reduced motion.
- When stalled or thinking-tinted, the verb takes the same blend colour as the glyph.

### 1.5 Mode and its effect

`mode` values (plugin API): `requesting`, `responding`, `thinking`, `tool-input`, `tool-use`.
Effects: arrow glyph (1.7), light direction/speed (1.4), `thinking` triggers the thinking wording and
tint, `tool-use` the breathing flash. Mode changes reset nothing else.

### 1.6 The bracketed status

Items in this order, separated by `·` (space, middle dot U+00B7, space), all dim except where
noted, inside `(` and `)` which are dim as well. `[2.1.330]` chunk-a824gc5p.js (search
`still thinking`, `tokens`).

1. Hook or script suffix text (`spinnerSuffix`). While hooks run the text is
   `running <HookEvent> hook` (plural `hooks` when several), and with several hooks a trailing
   `… i/n` (settled count over total) is appended; if the running hook has its own status message
   the text is `<statusMessage>…` instead. Example from screen: `running <Hook> hook`.
   Source: chunk-3pqaw3hv.js (search `running ${`). Always kept, never dropped for width.
2. Elapsed time, e.g. `4m 25s`. Counted from the start of the turn minus time spent paused
   (permission prompts etc.); frozen while paused; during compaction it counts from the compaction
   start. Format: under 60 s `Ns` (floored; `0s`), then `Nm Ns`, `Nh Nm Ns`, `Nd Nh Nm`
   (seconds rounded; chunk-f64qna2j.js, search `hideTrailingZeros`).
3. Tokens: `<arrow> <N> tokens`, arrow 2 cols wide (arrow + space), dim. Arrow `↑` (U+2191) in
   `requesting`, `↓` (U+2193) in every other mode. `N` format below. Shown only when the count
   is above 0.
4. Thinking text (1.9), after the tokens.

When it appears: the bracket is drawn when any of these holds: there is a suffix; verbose
mode; a thinking text exists; compaction is on; the token count is above 0; or elapsed time exceeds
16 000 ms. So `(12s · ↓ 300 tokens)` appears as soon as tokens start, and a long silent wait shows
`(16s)` after 16 s. The elapsed time is then drawn whenever the bracket is.

When the thinking text is the only item (no suffix, no time, no tokens fit), it is drawn alone as
`(thinking)` with the parentheses in the thinking colour instead of dim.

If the terminal is in screen-reader/accessibility mode only the suffix is kept; time, tokens and
thinking text are dropped.

Width gating (what narrow widths drop first): available width for the bracket is
`columns − (verbWidth + 2) − 5`. Priority from most to least kept: suffix (never dropped) → thinking
text → elapsed time (needs thinking width + 3 + its own width) → tokens (needs everything before it
plus its own width). Thinking text that is too wide (progressive wording or effort suffix) falls back
to plain `thinking` (8 cols) if that fits; otherwise it is dropped. If nothing fits there is no
bracket.

### 1.7 Token figure: exactly which number

`[2.1.330]` chunk-3pqaw3hv.js (search `get responseLength`, `countReply`, `addResponseLength`) and
chunk-pv97d3wp.js (search `thinkingTokenEstimate`). The displayed number is
`round(responseLength / 4)` where `responseLength` is kept in "characters, 4 per token" units and is
cumulative over the whole turn (all assistant messages and tool calls of the turn), not for the
current message:

- It is `keptLength + replyLength`. `keptLength` accumulates the finished messages of the turn;
  `replyLength` belongs to the message being streamed.
- While streaming: each streamed text or tool-input delta adds its character length to `replyLength`
  (flushed to the display at most every few tens of ms); thinking blocks add an estimated
  token count times 4 as thinking progress events arrive.
- When the API reports usage (the message delta or final assistant message carries `output_tokens`),
  `replyLength` is replaced by `output_tokens × 4`, i.e. the real count. At a new message start the
  previous reply is moved into `keptLength`.
- Context compaction resets the figure to 0.
- This is why a count of current-message characters divided by four (about 4.8k) can be far below
  the display (20.5k): the display accumulates real output tokens of every API call in the turn
  (and agent-side additions), not the visible text of one answer. `[screen]` the figure climbs over
  tens of minutes (e.g. 71.7k at 16m 21s, 84.6k at 20m 10s) which only the cumulative reading fits.

Number format: `Intl` compact notation, locale `en-US`, lower-cased. Under 1000: integer without
decimals (`999`). From 1000: exactly one decimal (`1.2k`, `12.0k`, `84.6k`, `1.2m`).

Counting animation (not in reduced motion): the shown value chases the real value in steps every
50 ms; in characters, step = 3 when the gap is under 70, `max(8, ceil(15 % of gap))` when under 200,
50 otherwise; a jump of more than 2000 characters snaps at once. The tokens are then `round(shown/4)`.

### 1.8 Stall: turning red

`[2.1.330]` chunk-a824gc5p.js, search `tengu_spinner_stalled_ui`.

- Stalled = the character counter has not increased for more than 10 000 ms. Not evaluated (never
  stalled) while tools are running, while thinking, while paused, while a response is held, or
  during compaction (unless responding). Resets to unstalled the moment the counter grows.
  (Older tree: 3 s.)
- Intensity = `min((silence − 10 s) / 10 s, 1)`, so full red 20 s after the last growth; smoothed
  (10 % of the gap closed every 50 ms) and quantised to 1/8 steps for colour. Blend target colour is
  `error` (255,107,128), applied to the glyph and the verb. The light stops while stalled.
- Telemetry thresholds exist at 10 s, 45 s and 300 s but change nothing visible.

### 1.9 Thinking wording

`[2.1.330]` chunk-a824gc5p.js (search `deep in thought`).

State kinds, in priority order: tool-running, recovering, tool-done, thinking, thought-for, none.

- `thinking` (mode is `thinking` and no tool is active). Wording by how long the current thinking
  block has run: under 10 s `thinking`; 10 s `still thinking`; 20 s `thinking more`; 30 s
  `thinking some more`; 45 s `deep in thought`. Then the effort suffix is appended:
  ` with <level> effort` (level word is lower-case, e.g. `thinking with max effort` `[screen]`),
  present when the model supports an effort level and one is set for the turn (otherwise empty).
  Colour: not dim. After 3 s of thinking the text pulses between `inactive` and `inactiveShimmer`
  with a 2 s sine; after 10 s it additionally tints toward `warning`, reaching full tint at 20 s
  (linear ramp, smoothed). The glyph and verb take the same tint. Not in reduced motion (then it is
  plain dim).
- `thought-for`: shown after thinking ends. Text `thought for Ns` with `N = max(1, round(seconds))`.
  Timing: thinking has to last at least 2 s from its start before the label switches (shorter
  thinking still shows the `thinking` state until 2 s have elapsed), then `thought for Ns` stays for
  2000 ms and disappears. Plain dim.
- `recovering`: `picking the thought back up`, with ` (N of M)` appended when the attempt number
  is above 1. Shown while a limited-output recovery is retrying and no tool is active.
- `tool-running` / `tool-done`: `running tool for <duration>` after 2 s of tool activity, and
  `ran tool for <duration>` after tools finish if they ran at least 2 s (`<duration>` in the
  format of 1.6). Gated by the feature flag `tengu_shining_fractals`, which defaults to off; not
  seen on screen; treat as normally absent.

### 1.10 Lines under the spinner (tip, next task, hints)

`[2.1.330]` chunk-pv97d3wp.js (search `Use /btw to ask a side question`); wrapper in
chunk-b7hj8816.js (search `⎿`).

- Prefix: two spaces, `⎿` (U+23BF), one space, one non-breaking space → 5 cols, dim. Content in
  the remaining width, dim.
- Content priority: `Next: <subject>` (the first pending task that is not blocked, whitespace
  collapsed, single line, truncated with ellipsis); else the selected tip as `Tip: <text>`
  (the tip may carry its own label word instead of `Tip`, followed by `: `); one special tip is a
  line with a trailing `· ` and an underlined slash command link in `suggestion`.
- A fallback tip, `Tip: Use /btw to ask a side question without interrupting Claude`, replaces the
  selected tip once the turn has run longer than 30 s, when tips are enabled and `/btw` has never
  been used.
- Tip choice: one tip per turn from a registry with per-tip cooldowns in sessions; skipped entirely
  when the user setting `spinnerTipsEnabled` is `false`. `[screen]` a session with tips turned off
  shows no tip line, only a blank row.
- Replaced by: the task list when the expanded view is `tasks`; the compaction hint text (dim) while
  compacting; an overload notice during API retries; nothing in a retry state.

### 1.11 API retry and wait states (replace the whole row content)

`[2.1.330]` chunk-a824gc5p.js (search `will retry in`). Glyph is `✻` in `error` colour (or `warning`
for low priority). Wording variants:

- `Waiting for API response · will retry in <t> · check your network`
- `Auto mode check unavailable · next try in <t> · attempt i/n · esc to interrupt`
- `No response from the API after <t>` (error colour) followed dim by
  ` · retrying, waiting up to <t> · attempt i/n` (or ` · retrying once, waiting up to <t>`), with a
  second dim line about proxies buffering streamed responses.
- low-priority queue: `<banner> · next try in <t> · attempt i · esc to interrupt` in `warning`.
  Countdown re-reads every second.

### 1.12 Compaction row

While compacting and not retrying, the row is the quieter "system line": one row (top margin 1) with
glyph frames `∴ ∷ ∵ ∷` (cycle, 150 ms each), italic, dim, text `Compacting conversation…`; hint text
below in the tip sub-row. In reduced motion the glyph is `∷`. `[2.1.330]` chunk-a824gc5p.js
(search `UMo`), chunk-xcgcdx61.js (glyph constants).

## 2. Queued prompts

- Prompts submitted while the agent works are listed as ordinary user-message rows, non-animated,
  without the leading dot, using the same drawing as a sent prompt (see the transcript doc). They
  sit in a column that sizes itself so that the whole queue stays within one third of the terminal
  height (each message is cut to fit; overflow is summarised as a count line, indented 2). Each row
  is followed, when there is room, by a dim marker `  ⎿  Queued · <key> to send now` (two spaces,
  `⎿`, two spaces, the word, `·`, then the configured chord and `send now`, or `click to send
now`). With little room only the key part is shown. `[2.1.330]` chunk-3pqaw3hv.js (search
  `Queued \xB7`, `send now`).
- Exact vertical position of the queue relative to the spinner is not established (it is a
  separate component mounted next to the prompt).
- Placeholder in the empty input mentioning the queue, `[2.1.330]` chunk-3pqaw3hv.js (search
  `Press up to edit queued`): with queued messages present and the empty input focused:
  - `Press up to edit queued messages` (shown for the first 3 times, a per-user counter), or
    `Press up to edit queued messages, Enter to send them now` / `Press up to select a queued
message to edit, or Enter to send them now` (variants when send-now is enabled);
  - while one is selected: `Press Enter to edit the selected message, or up again for history` (the
    oldest) / `… or up again for an older one` (a newer one).
    Other placeholders are in 3.4.

## 3. Prompt input box

### 3.1 Frame

`[2.1.330]` chunk-e9gframp.js (search `bashBorder`): only a top and a bottom rule, no side
borders. Each rule is a full-width row of `─` (U+2500), `[screen]` 115 cols on a 115-col terminal.
Rule colour: `promptBorder` 136,136,136 normally; `bashBorder` in bash mode; a session/agent colour
if the user set one with `/color`. There is no plan-mode-specific rule colour; plan mode shows only in
the footer pill (4.2). There is no memory (`#`) input mode in 2.1.330 (not found).
Optional label in the top rule `[2.1.330]` chunk-5m5vdxpd.js (search `─── `): when a session
name or agent colour label exists the top rule starts `─── <label> ` with the label dim, then
rules to the edge.

Vertical order `[screen]`: blank row, spinner row (when working), blank/tip row, top rule, input
row(s), bottom rule, status line row(s) if configured, footer row, then optional agent panel.

### 3.2 Marker and text rows

- Marker: `❯` (U+276F) followed by a non-breaking space = 2 cols; `!` plus NBSP in bash mode (bashBorder
  colour); `@<agent>` (truncated to 24 cols) plus NBSP when viewing a named agent, in that agent's
  colour. Normal marker colour is `inactive` (dim) `[screen]` (153,153,153, shown as `❯ `).
  `[2.1.330]` chunk-5m5vdxpd.js (search `function l5t`) and constants.
- Text is the plain foreground colour. Continuation lines start under the text column (indent equals
  marker width), not under the marker.
- Growth: the input is as many rows as the wrapped text needs; in non-fullscreen mode it is unbounded,
  in fullscreen it is capped at the larger of a small minimum and half the terminal height minus
  fixed rows. A rule is always directly above and below.
- Newline: Enter submits; the chord for a newline is shift+enter (or `\` then Enter); terminals that
  cannot distinguish show the hint `Shift+Enter for newlines` in setup tips.

### 3.3 Cursor

`[2.1.330]` chunk-s73318k8.js (search `cursorChar`): the cursor is an inverse-video cell on the
character under it (a space when at the end of the text) when the terminal window has focus; the
cell is not inverted when the window is unfocused. In "native cursor" mode (screen readers) the
inverse cell is replaced by the real terminal cursor. `[screen]` the real terminal showed no inverse
cell in a captured frame while the agent was running (focus lost or capture before the cell).

### 3.4 Placeholders (input empty only)

`[2.1.330]` chunk-3pqaw3hv.js (search `Taking your message back`), chunk-0rtj0bmp.js (search
`Try "`). Priority:

1. Viewing another agent: `Message @<name>…` (name cut to 20 cols).
2. `Taking your message back…`
3. Queue hints (section 2).
4. A next-step suggestion supplied by the program (rare).
5. On a fresh empty screen: the product's own onboarding placeholder.
6. First prompt of a session with prompt suggestions enabled: `Try "<one of eight canned ideas>"`,
   where the idea is chosen by a hash of the project path; the ideas are generic coding requests and
   may embed a file name from the project (`how does <file> work?`).
   Placeholder text is dim; the cursor cell sits on its first character.

### 3.5 Paste and attachment tokens

`[2.1.330]` chunk-bq31aqv6.js (search `Pasted text`): long pasted text is replaced in the input by
`[Pasted text #N +M lines]` (M = number of line breaks; `[Pasted text #N]` when M is 0); images by
`[Image #N]`; truncated pastes by `[...Truncated text #N +M lines...]`. Tokens are shown inline as
plain (or highlighted) text; ids count up per session. While pasting the footer says `Pasting…`;
after a paste that can expand, the footer says `paste again to expand`. The size threshold that
triggers collapsing is not established.

## 4. Footer under the box

Order below the bottom rule `[screen]`: user status line (if any), then the footer row. Both indented
2 cols (left padding 2 on a normal terminal). Then (outside the prompt component) the agent panel.

### 4.1 Hint row contents

`[2.1.330]` chunk-3pqaw3hv.js (search `bypass`, `for shell mode`, `? for shortcuts`, `again to`). One
row, height 1, items joined with dim `·`. Exclusive states, in priority order:

1. Exit pending: `Press Ctrl-C again to exit` (or `Ctrl-D`; `to detach (session keeps running)` in
   attached sessions), dim.
2. `Pasting…` dim; then `paste again to expand` dim.
3. Vim mode other than NORMAL: dim `-- INSERT --` style label before the rest.
4. Bash mode: `! for shell mode` in `bashBorder`.
5. Normal:
   `[mode pill] · [background tasks pill] · [esc to interrupt] · [← N agents] · [↓ to manage]`
   with only the parts that apply, `[screen]` verified order for a working session:
   `⏵⏵ bypass permissions on · 6 background tasks · esc to interrupt · ← 2 agents · ↓ to manage`
   (pill in its mode colour; tasks pill in `background` 0,204,204, inverse when selected, followed by
   dim ` · ↓ to view` in some states and `warning` ` · needs your input`; the rest dim).
6. Idle with nothing else to show: dim `? for shortcuts`.

States:

- Idle, empty input: mode pill (non-default modes only), `? for shortcuts` if nothing else shows.
- Draft (input not empty): the `? for shortcuts` and `esc to interrupt` items are hidden (the parent
  sets suppressHint when the input has content); the mode pill and other pills stay. The plugin
  API `isDraft` reflects this.
- Working: `esc to interrupt` (the chord is looked up from keybindings, lower-cased; default `esc`)
  and `ctrl+t to hide tasks / show tasks` when a task list exists; `← N agents` / `↓ to manage`
  when sub-agents exist (`← agents` narrow variant under 100 cols).
- Quiet states suppressing hints: help open, history search, suggestions popup.

### 4.2 Permission-mode pill

`[2.1.330]` chunk-xcgcdx61.js (search `indicator:"bypass permissions"`). Text is
`<symbol> <indicator> on`, whole pill in the mode colour; symbol `⏵⏵` (U+23F5 U+23F5) except plan `⏸`
(U+23F8):

| Mode              | Symbol      | Text                    | Colour                                  |
| ----------------- | ----------- | ----------------------- | --------------------------------------- |
| default           | (not shown) |                         | inactive                                |
| plan              | ⏸           | `plan mode on`          | planMode 72,150,140                     |
| acceptEdits       | ⏵⏵          | `accept edits on`       | autoAccept 175,135,255                  |
| bypassPermissions | ⏵⏵          | `bypass permissions on` | error 255,107,128 (`[screen]` verified) |
| dontAsk           | ⏵⏵          | `don't ask on`          | error                                   |
| auto              | ⏵⏵          | `auto mode on`          | warning 255,193,7                       |

Directly after the pill, dim ` (shift+tab to cycle)` is added only when the whole row still fits
the row width; `[screen]` it was absent on a crowded working row. The shift+tab chord is the
configured `chat:cycleMode` binding.

### 4.3 Right-aligned parts

The footer container is a flex row that wraps; the left column holds the status line and hint row; a
right column holds the plugin `modes` labels (SessionMode), notification items (update status,
context warnings, IDE/MCP status) and similar. `[2.1.330]` chunk-3pqaw3hv.js (search
`FooterHintLine`). Exact right-column strings (context-left warning wording, agent count) are not
established here; the `← N agents` item is in the left row (4.1), not right-aligned.

### 4.4 User status line

`[screen]` Rows of the user's status line command are drawn right under the bottom rule, indented
2 cols, above the footer row, in their own colours. The footer hint row follows immediately (no
blank row between them). A blank row separates the footer from the agent panel.

### 4.5 Agent panel (below the footer)

`[screen]` After one blank row: a bold `⏺ main` row, then one row per sub-agent: 2-space indent, `◯`
glyph, agent type, description, then right-aligned `<elapsed> · ↓ <N>k tokens` in dim. Same token
format as 1.7. Colour for the row text is dim.

## 5. Start of a session (top of the transcript)

`[old]` chunk-level logic in `src/components/LogoV2/CondensedLogo.tsx`; 2.1.330 has the same
elements with a newer mascot sprite table (chunk-ra3kqnyn.js, search `clawd_body`), exact default
sprite not established.

- Row layout: mascot at left, 2-col gap, text column to its right, vertically centred.
- Mascot (3 rows, about 9 cols, colour `clawd_body` 215,119,87 on `clawd_background` black); old
  tree default pose:
  ```
   ▐▛███▜▌
  ▝▜█████▛▘
    ▘▘ ▝▝
  ```
- Text column, three rows:
  1. `Claude Code` bold + ` v2.1.330` dim.
  2. `<model name> · <billing/plan>` dim (model name with ` with <level> effort` appended when set;
     split across two rows if too narrow).
  3. working directory, dim, shortened from the left with `…` (prefixed by `@<agent> · ` when an
     agent is named).
- Very narrow (< 59 cols) or short (< 30 rows) terminals or screen-reader mode: single line
  `Welcome to Claude Code` (claude colour) + space + dim `v<version>`. `[2.1.330]` chunk-89jb0md2.js
  (search `Welcome to Claude Code`).
- Following rows: optional upsell/notices (dim), then a blank row before the first message.

## Not established

- Exact vertical position of queued prompts relative to the spinner and the blank row under it.
- Paste collapse threshold; image paste behaviour beyond the token text.
- The 2.1.330 default mascot sprite (only the old-tree one is recorded) and the exact welcome
  header text/line count in 2.1.330 (the screen scrolled past it).
- Which condition makes the mode pill appear for `default` mode (assumed hidden because default
  shows only `? for shortcuts`).
- Right-column footer strings (context-left warning, notification wording and colours).
- Whether the status-line row precedes the hint row only when a status line command is configured
  (screen showed it so; code places the status line above the hint row).
- Effort level words list and their capitalisation in all surfaces (only `max` seen, lower case).
- Light and flash phases are absolute-clock based; start phase after a state change is not recorded.
