# desktop-walkthrough

A personal Claude Code skill and plugin (macOS): the agent operates real apps the way a person would while an on-screen HUD says what it is doing, so you can learn by watching.

## Layout

| Path | What it is |
| --- | --- |
| `SKILL.md` | Procedure and principles the agent follows |
| `.claude-plugin/plugin.json`, `hooks/` | Makes this folder a plugin; `hooks/register.ts` is the session bridge (conversation mirror, messages typed in the HUD, stop switch) |
| `scripts/dw` | Helper CLI: HUD lifecycle, narration, focus checks, non-blocking Terminal commands |
| `hud/HUD.swift` | The HUD, compiled on first `dw start` |
| `references/pitfalls.md` | Failures seen in real runs and the rules they produced |

Runtime state (built HUD, preferences, logs) lives in `~/.local/state/desktop-walkthrough/`, not in this folder, so the folder is plain source and safe to commit.

## Install or refresh

The source of truth is `~/dotfiles/skills/desktop-walkthrough/`. After editing or pulling:

```sh
npx skills add ~/dotfiles/skills --skill desktop-walkthrough -g -y
```

Then run `/reload-plugins` in Claude Code (or start a new session). `claude plugin list` shows it as `desktop-walkthrough@skills-dir`.

## Requirements

- [agent-desktop](https://github.com/vercel-labs/agent-desktop) with Accessibility permission, `jq`, and Xcode Command Line Tools (`swiftc`). `scripts/dw doctor` checks them.
- Terminal.app for the `dw term` commands.

## Use

Ask Claude Code to demonstrate something ("このチュートリアルを実演して"), or invoke `/desktop-walkthrough`. Close the HUD from its ☰ menu, with `scripts/dw end`, or by ending the session.
