# desktop-walkthrough

A personal Claude Code skill and plugin (macOS): the agent operates real apps the way a person would while an on-screen HUD says what it is doing, so you can learn by watching.

## Layout

| Path | What it is |
| --- | --- |
| `SKILL.md` | The operating manual the agent follows: what each HUD surface is for, the steps, how to explain, wait and ask, the rules for acting |
| `.claude-plugin/plugin.json`, `hooks/` | Makes this folder a plugin; `hooks/register.ts` is the session bridge (messages typed in the HUD, stop switch, the state at the end of the bar), `hooks/mirror.ts` what it reports for the mirror (the conversation as rows, the spinner's figures), `hooks/secrets.ts` the masking of secrets before display; `*.test.ts` their tests |
| `packages/protocol` | The shape of what the bridge, the HUD and the mirror's page say to each other (zod schemas, types, sample data) |
| `packages/mirror` | The mirror's page: the conversation redrawn the way Claude Code's terminal draws it (React, built into the one file `dist/index.html`, which is committed and which the HUD loads). `gallery.html` shows every row and state from sample data |
| `packages/handout` | `dw handout`'s contract (input, messages, codes), its builder (secret scan, render checks, images, sanitizing, assembly, verification) and the Handout's controller, built into the committed `dist/` (`builder.html`, `controller.js`, `purify.js`) |
| `handout/main.swift` | The Handout renderer: web views in a window nobody sees, the builder's requests, time limits, publishing without replacing a file that is not a Handout. `dw handout` builds it on first use |
| `fixtures/hud-golden/`, `scripts/hud-golden`, `scripts/handout-check` | A synthetic Record and the HUD's pages as built before the Handout work; the renderer-level checks of `dw handout` and the HUD regression check that `scripts/check` runs in a logged-in macOS session |
| `scripts/dw-check` | dw's plumbing case by case (narration, records, resume, audience markers, what `dw handout` checks before rendering), with the HUD and the renderer replaced by stand-ins; `scripts/check` runs it on macOS |
| `docs/claude-code-tui/` | How Claude Code 2.1.330 draws its terminal UI, in this project's own words: the reference the mirror's page follows |
| `GLOSSARY.md`, `docs/adr/`, `TODOS.md` | The project's words, the decisions that would surprise a reader without their reasons, and work decided but deferred |
| `package.json`, `pnpm-workspace.yaml`, `turbo.json` | The pnpm workspace and its tasks (`pnpm check`): `packages/*`, `hooks` and `hud` are its packages |
| `scripts/dw` | Helper CLI: HUD lifecycle, narration, focus checks, non-blocking Terminal commands |
| `scripts/check` | Static checks: bash 3.2 syntax and pitfalls, shellcheck, Swift typecheck, plugin validate, hooks tests and types, and the workspace's lint, types, tests and build when its dependencies are installed |
| `hud/HUD.swift` | The HUD class (stored views, launch, settings, stop, lifecycle) and the state-file paths shared with `dw` and the hooks |
| `hud/Bar.swift`, `hud/Mirror.swift`, `hud/AskPrompt.swift`, `hud/Explainer.swift`, `hud/Note.swift` | One surface each: status bar (with the session state at its end), conversation mirror, prompt card with answers and feedback buttons, explainer panel (long-form pages in a web view), note popup beside what it explains |
| `hud/MirrorPage.swift` | The web view that hosts the mirror's page: it hands the page what the bridge wrote and takes what the user did in it (a prompt, Esc, focus) |
| `hud/Border.swift`, `hud/Pending.swift` | The green line around the screen while the walkthrough acts; the delivery progress of a press (on its way, taken, reacted) |
| `hud/KeyCast.swift` | The key display: the keys the walkthrough sends (`dw press`, `dw keycast`), drawn large at the bottom-left corner of the screen the way a screencast shows keystrokes |
| `explainer/page.html`, `explainer/note.html` | Templates of an explainer page and of a note: `dw explain` / `dw note` fill in the Markdown, the page renders it with marked, highlight.js and mermaid (fetched once into the state folder, pinned by digest). The page draws the reading marks (a check per block, the frame on the block being read), the note its 理解した button |
| `hud/Reading.swift`, `hud/Sound.swift`, `hud/Effects.swift`, `explainer/effects.html` | Reading feedback: what was read (kept in `progress.json`, with a copy in the record), the achievements, the sounds that answer a mark, and the see-through layer that draws the banner of a cleared page and an achievement under the bar |
| `sounds/synth.py` | The sound effects as source: `dw` renders them to WAV files in the state folder before it starts the HUD (no audio files in the repository) |
| `hud/Settings.swift`, `hud/SettingsCard.swift`, `hud/Controls.swift`, `hud/Appearance.swift` | The options registry, the settings card, shared controls and the hot keys (stop, Command-C over a page, hiding the HUD with keys the user records), and the look every surface shares (appearance, colours, materials, accessibility display settings). Compiled on first `dw start` |
| `references/records.md` | What a recorded walkthrough holds, and how to resume or repeat one |
| `references/developing.md` | How to change the HUD, the bridge or `dw` and try the change on a scratch HUD |
| `references/pitfalls.md` | Failures seen in real runs and the rules they produced |
| `references/this-mac.md` | Facts about the one machine this skill runs on: PhpStorm keymap, screen, shell, projects |

Runtime state (built HUD, preferences, logs) lives in `~/.local/state/desktop-walkthrough/`, not in this folder, so the folder is plain source and safe to commit. Recorded walkthroughs (pages, journal, handbook) live in `~/.config/desktop-walkthrough/walkthroughs/`, which the dotfiles repository ignores.

## Install or refresh

While the skill is being developed, the install is a link to `~/dotfiles/skills/desktop-walkthrough/`: the folder Claude Code runs and its backup are one folder, so edits are live. Run `scripts/check` after every change.

```sh
rm -rf ~/.agents/skills/desktop-walkthrough   # the copied install, once nothing in it is newer than dotfiles
ln -s ~/dotfiles/skills/desktop-walkthrough ~/.agents/skills/desktop-walkthrough
```

`npx skills add ~/dotfiles/skills --skill desktop-walkthrough -g -y` (or `npx skills update`) replaces the link with a copy again. After a change to `hooks/` or `.claude-plugin/`, run `/reload-plugins` in Claude Code (or start a new session). `claude plugin list` shows it as `desktop-walkthrough@skills-dir`.

## The mirror

The mirror shows the session's conversation the way Claude Code's own terminal shows it: the same rows, glyphs, colours and wording, the spinner line with its time and token count, the input box and the hint line under it. It is a redrawing, not a copy of the screen: the bridge watches what the terminal draws and writes it down as rows, and the page draws those rows (`docs/adr/0001-the-mirror-redraws-the-conversation.md`). So it works in any terminal, and it has a real input box (input methods and dictation work in it).

What it cannot show, because Claude Code does not tell a plugin: your own status line, the list of agents under the footer, the row a compaction leaves, and thinking-token estimates while the model thinks (the token count catches up when the response ends). Rows drawn before the bridge loaded appear only if the terminal draws them again.

Until the bridge of a session has written its first transcript (a session that loaded the plugin before this version, until `/reload-plugins`), the mirror shows its earlier plain feed.

## Requirements

- [agent-desktop](https://github.com/vercel-labs/agent-desktop) with Accessibility permission, `jq`, and Xcode Command Line Tools (`swiftc`, and `python3` for the sound effects: without it the HUD is silent). `scripts/dw doctor` checks them.
- Terminal.app for the `dw term` commands.
- To change the mirror's page or the protocol: Node 24 and pnpm (`pnpm install`, then `pnpm check`). Using the skill needs neither: the built page is in the repository.

## Use

Ask Claude Code to demonstrate something ("このチュートリアルを実演して"), or invoke `/desktop-walkthrough`. Stop the agent with the red button on the bar or Control-Option-Command-Period. Hide the whole HUD and bring it back by pressing right Command and right Option together and letting go (click the shortcut in the settings to record other keys: a key with modifiers, or modifier keys by themselves, one or several). Close the HUD from its settings (the slider icon on the bar), with `scripts/dw end`, or by ending the session.
