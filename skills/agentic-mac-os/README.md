# agentic-mac-os

A personal Claude Code skill and plugin (macOS): the agent operates real apps the way a person would while an on-screen HUD says what it is doing, so you can learn by watching.

## Layout

| Path | What it is |
| --- | --- |
| `SKILL.md` | The operating manual the agent follows: what each HUD surface is for, the steps, how to explain, wait and ask, the rules for acting |
| `.claude-plugin/plugin.json`, `hooks/` | Makes this folder a plugin; `hooks/register.ts` is the session bridge (conversation mirror, messages typed in the HUD, stop switch, secrets masked before display), `hooks/register.test.ts` its tests |
| `scripts/dw` | Helper CLI: HUD lifecycle, narration, focus checks, non-blocking Terminal commands |
| `scripts/check` | Static checks: bash 3.2 syntax and pitfalls, shellcheck, Swift typecheck, plugin validate, hooks tests and types |
| `hud/HUD.swift` | The HUD class (stored views, launch, settings, stop, lifecycle) and the state-file paths shared with `dw` and the hooks |
| `hud/Bar.swift`, `hud/Mirror.swift`, `hud/AskPrompt.swift`, `hud/Explainer.swift`, `hud/Note.swift` | One surface each: status bar (with the session state at its end), conversation mirror with its message box, prompt card with answers and feedback buttons, explainer panel (long-form pages in a web view), note popup beside what it explains |
| `hud/Border.swift`, `hud/Pending.swift` | The green line around the screen while the walkthrough acts; the delivery progress of a press (on its way, taken, reacted) |
| `explainer/page.html`, `explainer/note.html` | Templates of an explainer page and of a note: `dw explain` / `dw note` fill in the Markdown, the page renders it with marked, highlight.js and mermaid (fetched once into the state folder, pinned by digest) |
| `hud/Settings.swift`, `hud/SettingsCard.swift`, `hud/Controls.swift`, `hud/Appearance.swift` | The options registry, the settings card, shared controls and the hot keys (stop, Command-C over a page), and the look every surface shares (appearance, colours, materials, accessibility display settings). Compiled on first `dw start` |
| `references/records.md` | What a recorded walkthrough holds, and how to resume or repeat one |
| `references/developing.md` | How to change the HUD, the bridge or `dw` and try the change on a scratch HUD |
| `references/pitfalls.md` | Failures seen in real runs and the rules they produced |
| `references/this-mac.md` | Facts about the one machine this skill runs on: PhpStorm keymap, screen, shell, projects |

Runtime state (built HUD, preferences, logs) lives in `~/.local/state/agentic-mac-os/`, not in this folder, so the folder is plain source and safe to commit. Recorded walkthroughs (pages, journal, handbook) live in `~/.config/agentic-mac-os/walkthroughs/`, which the dotfiles repository ignores.

## Install or refresh

While the skill is being developed, the install is a link to `~/dotfiles/skills/agentic-mac-os/`: the folder Claude Code runs and its backup are one folder, so edits are live. Run `scripts/check` after every change.

```sh
rm -rf ~/.agents/skills/agentic-mac-os   # the copied install, once nothing in it is newer than dotfiles
ln -s ~/dotfiles/skills/agentic-mac-os ~/.agents/skills/agentic-mac-os
```

`npx skills add ~/dotfiles/skills --skill agentic-mac-os -g -y` (or `npx skills update`) replaces the link with a copy again. After a change to `hooks/` or `.claude-plugin/`, run `/reload-plugins` in Claude Code (or start a new session). `claude plugin list` shows it as `agentic-mac-os@skills-dir`.

## Requirements

- [agent-desktop](https://github.com/vercel-labs/agent-desktop) with Accessibility permission, `jq`, and Xcode Command Line Tools (`swiftc`). `scripts/dw doctor` checks them.
- Terminal.app for the `dw term` commands.

## Use

Ask Claude Code to demonstrate something ("このチュートリアルを実演して"), or invoke `/agentic-mac-os`. Stop the agent with the red button on the bar or Control-Option-Command-Period. Close the HUD from its settings (the slider icon on the bar), with `scripts/dw end`, or by ending the session.
