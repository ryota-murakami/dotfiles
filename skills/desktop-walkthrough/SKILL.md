---
name: desktop-walkthrough
description: |
  Perform a task on the user's Mac the way a person would (real apps, visible clicks, typing and commands) while an on-screen HUD says what is happening and why, so the user learns by watching.
  Use when: the user wants a tutorial carried out in front of them, an app's setup steps shown, a tool demonstrated, or asks to "do it like a human while explaining".
  Keywords: walkthrough, live demo, narrated GUI automation, follow this tutorial for me, 実演して, 操作しながら解説, 人間が行うように, チュートリアルを進めて, 画面で見せて, デモして.
argument-hint: "[task, tutorial URL or app to demonstrate | clear]"
---

# Desktop Walkthrough

The user watches the screen, not the chat. Every action is visible, announced before it happens, and checked after. GUI primitives come from the `agent-desktop` skill (load it and its platform guide first); this skill adds the HUD, the safety checks and the rhythm.

`DW=~/.claude/skills/desktop-walkthrough/scripts/dw` (run `$DW` with no arguments for the command list). macOS only. State lives in `~/.local/state/desktop-walkthrough/` and survives a reboot.

Argument `clear`: run `$DW clear` (closes the HUD, the agent-desktop session and the idle terminals it opened), report what it printed, and stop.

## What the user sees

Each surface has one job. Put each thing on the surface that fits it.

| Surface | It says | You drive it with | The user can |
| --- | --- | --- | --- |
| Status bar | what you are doing right now, in one line | `$DW step`, `$DW say`; un-narrated tool calls show their description | drag it, resize it |
| End of the bar and screen border | whose turn the Mac is (see below) | nothing: it is derived from what you do | press stop |
| Explainer panel | the reasoning: numbered pages of Markdown, code and diagrams | `$DW explain` | page back, zoom, bring it forward with the book button |
| Note popup | a few sentences beside the thing they explain | `$DW note` | drag it, close it |
| Prompt card | a question, its two answers and feedback buttons | `$DW ask`, `$DW wait-user` | answer, give feedback, park it at a screen edge |
| Delivery line | that a press is on its way, then that it arrived | nothing: your first action after a press completes it | |
| Mirror | the conversation, with a message box | nothing: the bridge fills it | write to you |

**Which desktop a surface is on.** Only the status bar and the screen border show on every desktop (Space). Every other surface stays on the desktop where it was shown, so the desktops the user moves to meanwhile stay clear of the walkthrough. A new page, note or question appears on the desktop the user is looking at when the command runs, and the book and chat buttons bring their panel to the current desktop. So show things after `$DW front <window>`: they land on the app's desktop, beside what they explain.

**Whose turn the Mac is.** While a `dw` command narrates or acts, the end of the bar is the red stop button and a thin green line surrounds the screen: the Mac is yours and the user keeps their hands off. In every other state the end of the bar is a label and the Mac is the user's, who will read mail or answer messages meanwhile: 待機中 (the turn ended, or a foreground `$DW ask` / `$DW wait-user` blocks), スキル更新中 (a tool call works on this skill's files), その他作業中 (anything else). The state follows your tool calls and holds for six seconds past your last action. So:

- Keep walkthrough actions, skill edits and other checks in separate tool calls: each is shown as what it is.
- Perform in tight stretches: announce, act, check, with the thinking done before the stretch starts.
- After any stretch that was the user's, assume they are in another app. Begin with `$DW say` (the border comes up), then bring the window forward with `$DW front <window>` as an announced step. A `dw press` or `dw click-xy` that refuses because focus is elsewhere means the user took the Mac back: bring the window forward once more, and if that is refused too, ask on the HUD.

Stop (the red button, or Control-Option-Command-Period), the mirror, its message box and closing the HUD belong to the user. A HUD the user closed stays closed: `say` and `ad` reopen one that vanished for another reason (the agent restarted under the same session), and print a note when the user quit it; then say in chat that it is closed.

## Start

1. `$DW doctor`, then fix what it reports before working around it. A broken tool is repaired from its own docs and issue tracker first; a workaround comes only after that fails.
2. `$DW start --name <name>` launches the HUD, names the walkthrough's record and prints the environment: chat window (never send input there), input method, focused window, bridge state. To take up a paused walkthrough, `$DW resume <name>` instead: see `references/records.md`.
3. The session bridge (mirror, message box, stop, the state at the end of the bar) is this plugin's hooks module and loads with the plugin. If `$DW start` prints `bridge: not loaded in this session`, ask the user to run `/reload-plugins` (or restart the session) and carry on: the status bar and its settings work without it, the mirror stays empty and stop only acts at the next `dw` call.
4. Discover, never assume: `$DW windows` for window ids (they change on every relaunch), the app's own keymap or menu bar for shortcuts, the tutorial's real text for what to type. Read the screen before asking the user for a fact it already shows (a verified domain, an account name), and move through an app's own navigation instead of guessed URLs.
5. Put everything the user must watch on one desktop: create new windows there instead of chasing windows on other desktops. When code runs behind a UI step, show both: `$DW layout <editor> <app>`. When the walkthrough teaches why and not only how (a codebase, a design, a framework), `$DW stage <app window>` puts the app on the left, the explainer on the right and the bar under the app. That is a first proposal: once the user has arranged things their own way, work with their arrangement.
6. Put the first page in front of the user within the first minutes (what will happen, in what order, how to steer). Credentials, snapshots and helper scripts are prepared while they read.

## Each step

1. **Announce**: `$DW step "<section>"` once per section, then `$DW say "<what you are about to do and why>"` before every visible action, in the user's language, one line. Write tool call descriptions in the user's language too: the bar shows them between `say` lines (tools that only read, and anything run while a question is open, leave the bar as it is). When you investigate or repair, say that: no silent stretches.
2. **Act** the way a person would: menus, shortcuts, typing, the app's own dialogs. Run agent-desktop as `$DW ad <command>` so stop applies and it waits while the user types a message.
3. **Check** the result against what was expected, then say what happened and what it means (the request sent, the code that ran, the rule being taught): one line on the bar, the rest in a page or a note.

## Explain

Choose by where the thing to read is.

**The reasoning is the thing to read: a page.** Write Markdown to a file (anywhere: every page is kept in the record) and run `$DW explain <file.md>`. It becomes a numbered page with tables, highlighted code, ` ```mermaid ` diagrams, `<details>` for optional depth and links that open in the browser or the IDE; the panel keeps the earlier pages, so the user can go back while you move on.

- One page per idea, written for the user's level: what this piece is for, why it is built this way, what would break without it. Put the page up before the action it explains, and `$DW say` which page to read.
- A diagram for anything with a sequence, a relation or a before/after. `dw explain` reports each diagram that failed to render: fix the source and run it again with `--replace`.
- `$DW step "<section>"` before the first page of a section: a page is filed under the section that is current when it is written.
- A mistake found later is corrected in place: `$DW explain <file.md> --page N`.
- The panel stacks like an ordinary window and takes no keyboard focus. A new page and `$DW explain --show` put it in front; `$DW explain --back` puts it behind the app's window; `$DW explain --hide` closes it.

**Something in the app is the thing to read (code in an editor, a row in a table): a selection and a note.**

1. Add the long page behind the app, for the user who wants the depth: `$DW explain <file.md> --back`.
2. Bring the app's window to the front (`$DW front <window>`) and select what the explanation is about.
3. Put the explanation beside it: `$DW note <file.md> --anchor X,Y,W,H --title "<what is selected>"`. The anchor is the selection's rectangle on screen in points from the top-left corner (an element's bounds, or read from a screenshot); the popup takes the side with room, so the selection stays readable. A note is a few sentences, a short list or a snippet, in Markdown.
4. The bar only says where to look.

One selection and one note per idea: move both as the explanation moves. A new note or a new page replaces the note; `$DW note --clear` removes it.

Nothing secret goes on a page or in a note.

## Wait and ask

Reading takes longer than acting, and the user answers where they are looking: on the HUD.

| You need | Command | Answers |
| --- | --- | --- |
| The user to read, or to do a step themselves (log in, authorize, type a password, change DNS) | `$DW wait-user "<what to read or do, one line>"` (for a step of their own, say in chat what to do first) | 完了しました / できない・中断 |
| A yes or no | `$DW ask "<one-line question with the key facts, e.g. the price>"` | OK / キャンセル |
| An answer that needs explanation or choices | `$DW focus-chat`, then ask in the chat (AskUserQuestion) | |

Both commands take your own words: `--ok "<label>"` and `--no "<label>"` rename the two answers, and each `--button "<label>"` adds a feedback button (`--button "読んでいます" --button "もっと詳しく"`). A feedback button does not answer: its press reaches you as a message (`[HUD] フィードバック「…」`) and the question stays open. Choose the labels for the moment, acknowledge a press on the bar (`$DW say`), and act on what it asks for.

The exit status is the answer, of these commands and of every `dw` command that honours stop:

| Exit | Means | Do |
| --- | --- | --- |
| 0 | the first answer (OK, 次へ, 完了しました) | go on; after a step of the user's own, check the result on screen |
| 1 | the second answer (キャンセル, 質問・中断) | `$DW focus-chat` and ask in the chat what they need |
| 75 | still unanswered, or the user is typing a message in the mirror | wait: `$DW ask --wait` / `$DW wait-user --wait` / `$DW gate`, and do nothing else. If you end the turn instead, a later click reaches you as a message |
| 130 | the user pressed stop | do nothing more; wait for their message |
| 3 | the HUD is closed | ask in the chat |

- A wait that may outlast a foreground call runs as a background task whose last command is the wait itself, with nothing after it: the task's exit status is then the answer. Read it in a call that does nothing else, then act.
- A press is acknowledged for you: the bar shows it on its way, then that it arrived, and its line completes at your first tool call. Make that first action a quick `$DW say` of what you understood, before any long preparation.

## Rules for acting

- **Input goes to a verified target.** Prefer addressed delivery (an element ref, a window id). Keys and coordinates go to whatever is focused, so use `$DW press <combo> --in <window>` and `$DW click-xy X,Y --in <window>`, which refuse when focus is elsewhere. Before typing into a popup or dialog, confirm it is open. With an input method active, enter text by ref or clipboard. A click by ref does not move keyboard focus: follow it with a ref action (`set-value`, `check`), or read the place from a screenshot and click it physically. Chain a physical action to the command that proves its target is there with `&&`.
- **Commands never block the session.** `$DW term open` once, then `$DW term run "<cmd>"` and `$DW term check [seconds]`: it answers RUNNING, OK or FAILED with the exit status. Servers and watchers stay RUNNING in their own terminal (`-n server`). Read the result before the next step. A foreground tool call returns within about 100 seconds; anything longer (watching a deploy, a wait for the user) runs as a background task and reports back when it ends. A wait lasts as long as the thing waited for.
- **Results are compared, not assumed.** A saved file is diffed against its source, a clipboard against the text it should hold, a form submission against the database or the next page, and each browser window against the account it should be signed in as.
- **Demonstrate with the GUI, verify with anything.** The steps being taught go through the apps. Reading files, a database or an HTTP status to confirm a result is fine; say that it is a check.
- **Ask before anything that leaves the machine or cannot be undone**: external services, deploys, accounts, payments, messages to other people, and system-level fixes (restarting system processes, changing global settings). Say what you intend and wait. Describe what a button will do from what the screen says ("creating also starts a deploy"), not from memory.
- **Secrets never reach the chat or the mirror.** API keys, passwords and signed or one-time links go from their source (`op read`, a private file) straight to where they are used; print only names, lengths or hosts, and check that a redaction worked before showing its output. The mirror masks secret-shaped values and a PreToolUse hook refuses Bash commands that spell one out; both are safety nets, not permission.
- **When input lands in the wrong place, stop and say so.** Report what was touched, restore it from the source of truth, then fix the cause before continuing.

## Pause or finish

Every walkthrough is recorded as it runs (`references/records.md`); what you add by hand is the record's `README.md`.

**Finish.** Write in the record's README what a repeat needs: the starting state, the chapters with what each one proves, the cleanup. Remove temporary files and sample data you created, list what you left on purpose (uncommitted changes, test records), `$DW clear` (`$DW end` keeps the terminals), and summarize what was demonstrated.

**Pause** (the user stops before the end: tired, out of time). The walkthrough is paused, not finished. Write the resume point in the record's README (the last step done, the next page, what the environment looked like), put the user's environment back the way an ordinary working day expects it (branch, data, services) or list exactly what stays changed, remove credentials you fetched, then `$DW clear`.

## References

- `references/records.md`: what a record holds and who writes each part, and the procedures to **resume** a paused walkthrough and to **repeat** a recorded one. Read it before either, and before writing a record's README for the first time.
- `references/this-mac.md`: facts about this one machine (the user's PhpStorm keymap and how to drive it, screen, shell, how the user arranges a walkthrough). Read it before the first GUI action; add what you learn.
- `references/pitfalls.md`: failures seen in real runs, their causes and the rule each one produced, plus per-app notes (agent-desktop, JetBrains IDEs, Chrome, Terminal, macOS). Read it before the first GUI action in an app you have not driven in this session.
- `~/.config/desktop-walkthrough/notes.md`: private notes about the user's own projects (how their local services are wired, what a walkthrough there needs). It is outside the repository on purpose: facts about someone's work go there, not into the files above. Read it when a walkthrough touches one of those projects; add what you learn.
- `references/developing.md`: how to change the HUD, the bridge or `dw` itself and try the change without disturbing the walkthrough on screen. Read it before editing anything under `hud/`, `hooks/`, `explainer/` or `scripts/`.
