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
3. The session bridge (mirror, message box, ⏹) is this plugin's hooks module and loads with the plugin. If `$DW start` prints `bridge: not loaded in this session`, ask the user to run `/reload-plugins` (or restart the session) and carry on: the status bar, ⏸ and ✕ work without it, the mirror stays empty and ⏹ only acts at the next `dw` call.
4. Discover, never assume: `$DW windows` for window ids (they change on every relaunch), the app's own keymap or menu bar for shortcuts, the tutorial's real text for what to type.
5. Put everything the user must watch on one desktop: create new windows there instead of chasing windows on other desktops. When code runs behind a UI step, show both: `$DW layout <editor> <app>`.

## Each step

1. **Announce**: `$DW step "<section>"` once per section, then `$DW say "<what you are about to do and why>"` before every visible action, in the user's language, one line.
2. **Act** the way a person would: menus, shortcuts, typing, the app's own dialogs. Run agent-desktop as `$DW ad <command>` so pause and stop apply.
3. **Check** the result against what was expected, then say in chat what happened and what it means (the request sent, the code that ran, the rule being taught).

## Principles

- **The HUD always shows the current action.** `say` and `ad` reopen the HUD if it vanished (the agent restarting under the same session gets a new pid), unless the user closed it with ✕; then say in chat that it is closed. No silent stretches: if you are investigating or repairing, say that. ⏸ (takeover), ⏹ (stop), the mirror and its message box belong to the user; when `dw` exits 130 the user pressed stop, so do nothing more and wait for their message. Exit 75 means still paused.
- **Commands never block the session.** `$DW term open` once, then `$DW term run "<cmd>"` and `$DW term check [seconds]`: it answers RUNNING, OK or FAILED with the exit status. Servers and watchers stay RUNNING in their own terminal (`-n server`). Read the result before the next step; never assume success.
- **Input goes to a verified target.** Prefer addressed delivery (an element ref, a window id). Keys and coordinates go to whatever is focused, so use `$DW press <combo> --in <window>` and `$DW click-xy X,Y --in <window>`, which refuse when focus is elsewhere. Before typing into a popup or dialog, confirm it is actually open. With an input method active, enter text by ref or clipboard, never key by key.
- **Results are compared, not assumed.** A saved file is diffed against its source, a clipboard against the text it should hold, a form submission against the database or the next page, and each browser window against the account it should be signed in as.
- **Ask before anything that leaves the machine or cannot be undone**: external services, deploys, accounts, payments, messages to other people, and system-level fixes (restarting system processes, changing global settings). Say what you intend and wait.
- **Ask where the user is looking.** A yes/no approval goes on the HUD: `$DW ask "<one-line question with the key facts, e.g. the price>"` → OK (exit 0), キャンセル (1), still unanswered (75: run `$DW ask --wait`, do nothing else). A question that needs explanation or choices: `$DW focus-chat` to bring the chat to the front, then ask there (AskUserQuestion).
- **Demonstrate with the GUI, verify with anything.** The steps being taught go through the apps. Reading files, a database or an HTTP status to confirm a result is fine; say that it is a check.
- **When input lands in the wrong place, stop and say so.** Report what was touched, restore it from the source of truth, then fix the cause before continuing.

## Finish

`$DW clear` closes the HUD, the agent-desktop session and every idle terminal you opened (`$DW end` keeps the terminals). Remove temporary files and sample data you created, list what you left on purpose (uncommitted changes, test records), and summarize what was demonstrated.

## References

- `references/pitfalls.md`: failures seen in real runs, their causes and the rule each one produced, plus per-app notes (agent-desktop, JetBrains IDEs, Chrome, Terminal, macOS). Read it before the first GUI action in an app you have not driven in this session.
- `hud/HUD.swift`, `hooks/register.ts`, `scripts/dw`: the HUD, the session bridge and the helper. `README.md` says where the source lives and how to reinstall after a change.
