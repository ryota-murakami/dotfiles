# desktop-walkthrough

A personal Claude Code skill and plugin (macOS): the agent operates real apps the way a person would while an on-screen HUD says what it is doing, so you can learn by watching.

## Layout

| Path | What it is |
| --- | --- |
| `SKILL.md` | Procedure and principles the agent follows |
| `.claude-plugin/plugin.json`, `hooks/` | Makes this folder a plugin; `hooks/register.ts` is the session bridge (conversation mirror, messages typed in the HUD, stop switch, secrets masked before display), `hooks/register.test.ts` its tests |
| `scripts/dw` | Helper CLI: HUD lifecycle, narration, focus checks, non-blocking Terminal commands |
| `scripts/check` | Static checks: bash 3.2 syntax and pitfalls, shellcheck, Swift typecheck, plugin validate, hooks tests and types |
| `hud/HUD.swift` | The HUD class (stored views, launch, settings, stop, lifecycle) and the state-file paths shared with `dw` and the hooks |
| `hud/Bar.swift`, `hud/Mirror.swift`, `hud/AskPrompt.swift`, `hud/Explainer.swift` | One surface each: status bar, conversation mirror with its message box, one-click approval prompt, explainer panel (long-form pages in a web view) |
| `explainer/page.html` | Template of one explainer page: `dw explain` fills in the Markdown, the page renders it with marked, highlight.js and mermaid (fetched once into the state folder, pinned by digest) |
| `hud/Settings.swift`, `hud/SettingsCard.swift`, `hud/Controls.swift` | The options registry, the settings card, shared controls and the stop shortcut. Compiled on first `dw start` |
| `references/pitfalls.md` | Failures seen in real runs and the rules they produced |
| `references/this-mac.md` | Facts about the one machine this skill runs on: PhpStorm keymap, screen, shell, projects |

Runtime state (built HUD, preferences, logs) lives in `~/.local/state/desktop-walkthrough/`, not in this folder, so the folder is plain source and safe to commit. Recorded walkthroughs (pages, journal, handbook) live in `~/.config/desktop-walkthrough/walkthroughs/`, which the dotfiles repository ignores.

## Install or refresh

The source of truth is `~/dotfiles/skills/desktop-walkthrough/`. Run `scripts/check` after every change.

While the skill is being developed, the install is a link to that folder, so edits are live:

```sh
rm -rf ~/.agents/skills/desktop-walkthrough   # the copied install, once nothing in it is newer than dotfiles
ln -s ~/dotfiles/skills/desktop-walkthrough ~/.agents/skills/desktop-walkthrough
```

`npx skills add ~/dotfiles/skills --skill desktop-walkthrough -g -y` (or `npx skills update`) replaces the link with a copy again. After a change to `hooks/` or `.claude-plugin/`, run `/reload-plugins` in Claude Code (or start a new session). `claude plugin list` shows it as `desktop-walkthrough@skills-dir`.

## Requirements

- [agent-desktop](https://github.com/vercel-labs/agent-desktop) with Accessibility permission, `jq`, and Xcode Command Line Tools (`swiftc`). `scripts/dw doctor` checks them.
- Terminal.app for the `dw term` commands.

## Use

Ask Claude Code to demonstrate something ("このチュートリアルを実演して"), or invoke `/desktop-walkthrough`. Stop the agent with the red button on the bar or Control-Option-Command-Period. Close the HUD from its settings (the slider icon on the bar), with `scripts/dw end`, or by ending the session.
