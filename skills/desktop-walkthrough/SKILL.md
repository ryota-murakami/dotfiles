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
5. Put everything the user must watch on one desktop: create new windows there instead of chasing windows on other desktops. When code runs behind a UI step, show both: `$DW layout <editor> <app>`.

## Each step

1. **Announce**: `$DW step "<section>"` once per section, then `$DW say "<what you are about to do and why>"` before every visible action, in the user's language, one line.
2. **Act** the way a person would: menus, shortcuts, typing, the app's own dialogs. Run agent-desktop as `$DW ad <command>` so stop applies and it waits while the user types a message.
3. **Check** the result against what was expected, then say in chat what happened and what it means (the request sent, the code that ran, the rule being taught).

## Principles

- **The HUD always shows the current action.** `say` and `ad` reopen the HUD if it vanished (the agent restarting under the same session gets a new pid), unless the user quit it from its settings; then say in chat that it is closed. No silent stretches: if you are investigating or repairing, say that. Stop (the red button on the bar, or Control-Option-Command-Period), the mirror and its message box belong to the user; when `dw` exits 130 the user pressed stop, so do nothing more and wait for their message. Exit 75 means the user is still typing a message in the mirror: wait, do nothing else.
- **Commands never block the session.** `$DW term open` once, then `$DW term run "<cmd>"` and `$DW term check [seconds]`: it answers RUNNING, OK or FAILED with the exit status. Servers and watchers stay RUNNING in their own terminal (`-n server`). Read the result before the next step; never assume success. A foreground tool call must return within about 100 seconds: anything that may take longer (watching a deploy, `$DW wait-user` for a login) runs as a background task and reports back when it ends. Never shorten a wait just to end the turn.
- **Input goes to a verified target.** Prefer addressed delivery (an element ref, a window id). Keys and coordinates go to whatever is focused, so use `$DW press <combo> --in <window>` and `$DW click-xy X,Y --in <window>`, which refuse when focus is elsewhere. Before typing into a popup or dialog, confirm it is actually open. With an input method active, enter text by ref or clipboard, never key by key.
- **Results are compared, not assumed.** A saved file is diffed against its source, a clipboard against the text it should hold, a form submission against the database or the next page, and each browser window against the account it should be signed in as.
- **Ask before anything that leaves the machine or cannot be undone**: external services, deploys, accounts, payments, messages to other people, and system-level fixes (restarting system processes, changing global settings). Say what you intend and wait. Describe what a button will do from what the screen says ("creating also starts a deploy"), not from memory.
- **Ask where the user is looking.** A yes/no approval goes on the HUD: `$DW ask "<one-line question with the key facts, e.g. the price>"` → OK (exit 0), キャンセル (1), still unanswered (75: run `$DW ask --wait`, do nothing else; a click after the turn ended arrives as a message). When the user must do a step themselves (log in, authorize, type a password, change DNS): say in chat what to do, then `$DW wait-user "<the step, one line>"` → 完了しました (exit 0: check the result on screen), できない・中断 (1: ask in the chat), still waiting (75: `$DW wait-user --wait`; if you end the turn instead, a later click reaches you as a message). A question that needs explanation or choices: `$DW focus-chat` to bring the chat to the front, then ask there (AskUserQuestion).
- **Secrets never reach the chat or the mirror.** API keys, passwords and signed or one-time links go from their source (`op read`, a private file) straight to where they are used; print only names, lengths or hosts, and check that a redaction worked before showing its output. The mirror masks secret-shaped values and a PreToolUse hook refuses Bash commands that spell one out; both are safety nets, not permission.
- **Demonstrate with the GUI, verify with anything.** The steps being taught go through the apps. Reading files, a database or an HTTP status to confirm a result is fine; say that it is a check.
- **When input lands in the wrong place, stop and say so.** Report what was touched, restore it from the source of truth, then fix the cause before continuing.

## Finish

`$DW clear` closes the HUD, the agent-desktop session and every idle terminal you opened (`$DW end` keeps the terminals). Remove temporary files and sample data you created, list what you left on purpose (uncommitted changes, test records), and summarize what was demonstrated.

## References

- `references/pitfalls.md`: failures seen in real runs, their causes and the rule each one produced, plus per-app notes (agent-desktop, JetBrains IDEs, Chrome, Terminal, macOS). Read it before the first GUI action in an app you have not driven in this session.
- `hud/` (Swift: `HUD.swift` the class and lifecycle; `Bar.swift`, `Mirror.swift`, `AskPrompt.swift` one surface each; `Settings.swift` the list of options, add one line to add a setting; `Controls.swift`; `SettingsCard.swift`), `hooks/register.ts`, `scripts/dw`: the HUD, the session bridge and the helper. Run `scripts/check` after changing any of them. `README.md` says where the source lives and how the install is linked.
