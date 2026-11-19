---
name: desktop-walkthrough
description: |
  Perform a task on the user's Mac the way a person would (real apps, visible clicks, typing and commands) while an on-screen HUD says what is happening and why, so the user learns by watching.
  Use when: the user wants a tutorial carried out in front of them, an app's setup steps shown, a tool demonstrated, or asks to "do it like a human while explaining".
  Keywords: walkthrough, live demo, narrated GUI automation, follow this tutorial for me, 実演して, 操作しながら解説, 人間が行うように, チュートリアルを進めて, 画面で見せて, デモして.
argument-hint: "[task, tutorial URL or app to demonstrate | clear]"
---

# Desktop Walkthrough

The user watches the screen, not the chat. Every action must be visible, announced before it happens, and checked after. GUI primitives come from the `agent-desktop` skill (load it and its platform guide first); this skill adds the HUD, the safety checks and the rhythm.

`DW=~/.claude/skills/desktop-walkthrough/scripts/dw` (run `$DW` with no arguments for the command list). macOS only. State lives in `~/.local/state/desktop-walkthrough/` and survives a reboot.

If the argument is `clear`, only end the walkthrough: run `$DW clear` (closes the HUD, the agent-desktop session and the idle terminals it opened), report what it printed, and stop.

## Start

1. `$DW doctor`, then fix what it reports before working around it. A broken tool is repaired from its own docs and issue tracker first; a workaround comes only after that fails.
2. `$DW start` launches the HUD and prints the environment: chat window (never send input there), input method, focused window, bridge state.
3. The session bridge (mirror, message box, stop) is this plugin's hooks module and loads with the plugin. If `$DW start` prints `bridge: not loaded in this session`, ask the user to run `/reload-plugins` (or restart the session) and carry on: the status bar and its settings work without it, the mirror stays empty and stop only acts at the next `dw` call.
4. Discover, never assume: `$DW windows` for window ids (they change on every relaunch), the app's own keymap or menu bar for shortcuts, the tutorial's real text for what to type. Read the screen before asking the user for a fact it already shows (a verified domain, an account name), and move through an app's own navigation instead of guessed URLs.
5. Put everything the user must watch on one desktop: create new windows there instead of chasing windows on other desktops. When code runs behind a UI step, show both: `$DW layout <editor> <app>`. When the walkthrough teaches why and not only how (a codebase, a design, a framework), set the stage for reading: `$DW stage <app window>` puts the app on the left, the explainer panel on the right and the status bar under the app. That is a first proposal: once the user has arranged things their own way (a maximized app, a wider panel, the bar somewhere else), leave it and work with their arrangement.
6. Put the first page in front of the user within the first minutes (what will happen, in what order, how to steer). Credentials, snapshots and helper scripts can be prepared while they read; a long silent preparation is the part of a walkthrough nobody watches.

## Each step

1. **Announce**: `$DW step "<section>"` once per section, then `$DW say "<what you are about to do and why>"` before every visible action, in the user's language, one line.
2. **Act** the way a person would: menus, shortcuts, typing, the app's own dialogs. Run agent-desktop as `$DW ad <command>` so stop applies and it waits while the user types a message.
3. **Check** the result against what was expected, then say what happened and what it means (the request sent, the code that ran, the rule being taught): one line on the bar, the rest in the explainer.

## Explaining at length

The bar holds one line. Anything longer goes to the explainer panel: write Markdown to a file and run `$DW explain <file.md>`. It becomes a numbered page (tables, code with highlighting, ` ```mermaid ` diagrams, `<details>` for optional depth, links that open in the browser or the IDE); the panel shows the newest page and keeps the earlier ones (◀ ▶ and a list), so the user can go back while you move on.

- One page per idea, written for the user's level: what this piece is for, why it is built this way, what would break without it. Put the page up before the action it explains, and `$DW say` which page to read.
- Prefer a diagram for anything with a sequence, a relation or a before/after. `dw explain` reports each diagram that failed to render: fix the source and run it again with `--replace`.
- `$DW step "<section>"` before the first page of a section: a page is filed under the section that is current when it is written.
- Every page is kept in the walkthrough's record (see Recording and repeating), so write the source anywhere (a temp file is fine). A mistake found later is corrected in place with `$DW explain <file.md> --page N`.
- The panel covers part of the app. When the next thing to watch is the app itself (code being written, a request being sent), step it aside with `$DW explain --hide`; the next page brings it back, or `$DW explain --show`.
- Reading takes longer than acting. After a page that matters, wait: `$DW wait-user "<what to read>"` in the background, and continue when the user says so.
- Nothing secret goes on a page.

## Principles

- **The HUD always shows the current action.** `say` and `ad` reopen the HUD if it vanished (the agent restarting under the same session gets a new pid), unless the user quit it from its settings; then say in chat that it is closed. No silent stretches: if you are investigating or repairing, say that. Between `say` lines the bar shows each un-narrated tool call by its description, so write those descriptions in the user's language during a walkthrough; tools that only read and anything run while a question is open leave the bar as it is. Stop (the red button on the bar, or Control-Option-Command-Period), the mirror and its message box belong to the user; when `dw` exits 130 the user pressed stop, so do nothing more and wait for their message. Exit 75 means the user is still typing a message in the mirror: wait, do nothing else.
- **Commands never block the session.** `$DW term open` once, then `$DW term run "<cmd>"` and `$DW term check [seconds]`: it answers RUNNING, OK or FAILED with the exit status. Servers and watchers stay RUNNING in their own terminal (`-n server`). Read the result before the next step; never assume success. A foreground tool call must return within about 100 seconds: anything that may take longer (watching a deploy, `$DW wait-user` for a login) runs as a background task and reports back when it ends. Never shorten a wait just to end the turn.
- **Input goes to a verified target.** Prefer addressed delivery (an element ref, a window id). Keys and coordinates go to whatever is focused, so use `$DW press <combo> --in <window>` and `$DW click-xy X,Y --in <window>`, which refuse when focus is elsewhere. Before typing into a popup or dialog, confirm it is actually open. With an input method active, enter text by ref or clipboard, never key by key. A click by ref does not move keyboard focus, so never follow it with a key meant for the clicked element: use a ref action (`set-value`, `check`), or read the place from a screenshot and click it physically. Chain a physical action to the command that proves its target is there with `&&`, never `;`.
- **Results are compared, not assumed.** A saved file is diffed against its source, a clipboard against the text it should hold, a form submission against the database or the next page, and each browser window against the account it should be signed in as.
- **Ask before anything that leaves the machine or cannot be undone**: external services, deploys, accounts, payments, messages to other people, and system-level fixes (restarting system processes, changing global settings). Say what you intend and wait. Describe what a button will do from what the screen says ("creating also starts a deploy"), not from memory.
- **Ask where the user is looking.** A yes/no approval goes on the HUD: `$DW ask "<one-line question with the key facts, e.g. the price>"` → OK (exit 0), キャンセル (1), still unanswered (75: run `$DW ask --wait`, do nothing else; a click after the turn ended arrives as a message). When the user must do a step themselves (log in, authorize, type a password, change DNS): say in chat what to do, then `$DW wait-user "<the step, one line>"` → 完了しました (exit 0: check the result on screen), できない・中断 (1: ask in the chat), still waiting (75: `$DW wait-user --wait`; if you end the turn instead, a later click reaches you as a message). A question that needs explanation or choices: `$DW focus-chat` to bring the chat to the front, then ask there (AskUserQuestion). Both commands take your own words: `--ok "<label>"` and `--no "<label>"` rename the two answers, and each `--button "<label>"` adds a feedback button. A feedback button does not answer: its press reaches you as a message (`[HUD] フィードバック「…」`) and the question stays open, so the user can tell you what they are doing without leaving the app (`--button "読んでいます" --button "もっと詳しく"`). Choose the labels for the moment, acknowledge a press on the bar (`$DW say`), and act on what it asks for. The prompt can be dragged off whatever it covers and stays where the user put it; pushed past a screen edge it parks there as a strip and slides back in while the pointer is on it.
- **Secrets never reach the chat or the mirror.** API keys, passwords and signed or one-time links go from their source (`op read`, a private file) straight to where they are used; print only names, lengths or hosts, and check that a redaction worked before showing its output. The mirror masks secret-shaped values and a PreToolUse hook refuses Bash commands that spell one out; both are safety nets, not permission.
- **Demonstrate with the GUI, verify with anything.** The steps being taught go through the apps. Reading files, a database or an HTTP status to confirm a result is fine; say that it is a check.
- **When input lands in the wrong place, stop and say so.** Report what was touched, restore it from the source of truth, then fix the cause before continuing.

## Recording and repeating

Every walkthrough is recorded in a folder of its own under `~/.config/desktop-walkthrough/walkthroughs/` (this skill's folder; it is not committed anywhere). `$DW start --name <name>` names it; `$DW record <name>` names or renames it later and takes the pages already shown; `$DW records` lists them.

| In the record | Written by | For |
| --- | --- | --- |
| `journal.md` | `dw`, as you work: sections (`step`), narration (`say`), commands and their results (`term run` / `term check`), questions with their answers, feedback buttons | repeating the walkthrough step by step |
| `pages/NN-title.md`, `handbook.md` | `dw explain`: each page, and all of them in reading order | reading again, sharing with other people |
| `README.md` | you: under "もう一度実演するには", what this walkthrough needs before it starts, what it changes and how to put it back | starting a repeat without the old conversation |

- Keep the helper scripts and input files a repeat would need in the record too (`tools/`, never anything secret such as tokens).
- Write the README section before finishing, while the reasons are fresh: the starting state (branch, data, running services), the order of chapters with what each one proves, and the cleanup.
- **To repeat a recorded walkthrough**: `$DW start --name <new name>`, read the old record's `README.md` and `journal.md`, compare each page with how things are now (code moves on: correct a page before showing it, `$DW explain <page>`), then perform the journal's steps in order. The journal says what happened, including what failed; follow the path that worked.

## Pausing

When the user stops before the end (tired, out of time), the walkthrough is paused, not finished. Write the resume point in the record's `README.md` (the last step done, the next page, what the environment looked like), put the user's environment back the way an ordinary working day expects it (branch, data, services) or list exactly what stays changed, remove credentials you fetched, then `$DW clear`. A HUD the user closed themselves stays closed.

## Finish

`$DW clear` closes the HUD, the agent-desktop session and every idle terminal you opened (`$DW end` keeps the terminals). Remove temporary files and sample data you created, list what you left on purpose (uncommitted changes, test records), and summarize what was demonstrated.

## References

- `references/this-mac.md`: facts about this one machine (the user's PhpStorm keymap and how to drive it, screen, shell, projects). Read it before the first GUI action; add what you learn.
- `~/.config/desktop-walkthrough/notes.md`: private notes about the user's own projects (how their local services are wired, what a walkthrough there needs). It is outside the repository on purpose: facts about someone's work go there, not into the files above. Read it when a walkthrough touches one of those projects; add what you learn.
- `references/pitfalls.md`: failures seen in real runs, their causes and the rule each one produced, plus per-app notes (agent-desktop, JetBrains IDEs, Chrome, Terminal, macOS). Read it before the first GUI action in an app you have not driven in this session.
- `hud/` (Swift: `HUD.swift` the class and lifecycle; `Bar.swift`, `Mirror.swift`, `AskPrompt.swift`, `Explainer.swift` one surface each; `Settings.swift` the list of options, add one line to add a setting; `Controls.swift`; `SettingsCard.swift`), `explainer/page.html` (the template of an explainer page), `hooks/register.ts`, `scripts/dw`: the HUD, the session bridge and the helper. Run `scripts/check` after changing any of them, and try a changed HUD on a scratch instance, not on the one the user is watching: build with `swiftc hud/*.swift -o <tmp>/StatusHUD`, run `<tmp>/StatusHUD <tmp state folder>`, drive it with `DW_HOME=<tmp state folder> scripts/dw …`, quit it with `touch <tmp state folder>/quit`. `README.md` says where the source lives and how the install is linked.
