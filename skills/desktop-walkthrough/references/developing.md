# Developing the skill

How to change the HUD, the session bridge or `dw`, and try the change without disturbing the walkthrough on screen. `README.md` says where the source lives and how the install is linked.

## Where things are

| Path | Holds |
| --- | --- |
| `scripts/dw` | the helper: every command the agent runs. One function per command, dispatched at the bottom |
| `hud/HUD.swift` | the HUD class: stored views, launch, timers, settings, stop, lifecycle, and the paths of the state files |
| `hud/Bar.swift` | the status bar, its click-through, and the session state (`currentActivity`) |
| `hud/Border.swift` | the green line around the screen while the walkthrough acts |
| `hud/Explainer.swift`, `explainer/page.html` | the explainer panel and the template of a page |
| `hud/Note.swift`, `explainer/note.html` | the note popup and the template of a note |
| `hud/AskPrompt.swift` | the prompt card: answers, feedback buttons, parking |
| `hud/Pending.swift` | the delivery progress of a press |
| `hud/Mirror.swift` | the conversation mirror and its message box; the shared edge resize handle |
| `hud/Settings.swift`, `hud/SettingsCard.swift` | the options (add one line to the registry to add a setting) and the card that shows them |
| `hud/Controls.swift` | shared controls: buttons, the state badge, tooltip-style placement (`popupFrame`), cursors, the stop shortcut |
| `hooks/register.ts`, `hooks/register.test.ts` | the session bridge (the plugin's hooks module) and its tests |

Everything the three parts say to each other goes through small files in the state folder. A new signal is a new file: name its path in `hud/HUD.swift` (or the surface's own file) with who writes it and what it means, and list it in the header of `hooks/register.ts` when the bridge reads or writes it.

## The loop

1. Edit the source.
2. `scripts/check` (bash syntax and pitfalls, shellcheck, Swift typecheck, plugin validation, hooks tests).
3. Try a changed HUD on a **scratch instance**, never on the one the user is watching:
   - build: `swiftc -O -swift-version 5 hud/*.swift -o <tmp>/StatusHUD`
   - give it a state folder of its own and start it: `<tmp>/StatusHUD <tmp state folder>`
   - drive it: `DW_HOME=<tmp state folder> scripts/dw …` (create `<tmp state folder>/bridge/owner` so that `dw` treats a walkthrough as active)
   - stand in for the session by writing the files it would write (`bridge/state.json`, `bridge/tool-class`, `status.txt`, …)
   - quit it: `touch <tmp state folder>/quit`
4. Compare what is on screen with what was meant: `screencapture -x -R x,y,w,h file.png` for a still, and for anything that moves or changes over time `screencapture -V <seconds> out.mov`, then frames with `ffmpeg -i out.mov -vf fps=5 frame_%03d.png`.
5. Put the new build in front of the user: `touch <state>/quit`, wait for the HUD to exit, then any `dw say`: it rebuilds and relaunches. A HUD the user quit from its settings is not relaunched (`hud-closed-by-user`): leave it closed and say so.
6. A change under `hooks/` or `.claude-plugin/` reaches the running session only after the user runs `/reload-plugins`. Make the HUD work with the bridge that is loaded until then (a missing file means "not known", never "no").

## Things that bit

- The live HUD and a scratch HUD are both called `StatusHUD`: accessibility queries by app name reach the live one. Click the scratch one by coordinates read from a screenshot.
- The bar ignores the pointer until it rests on a control: `mouse-move`, wait half a second, then click.
- A web view in a panel that is not on screen can report a size it will not keep: measure again once the panel shows.
- Cursor rects do nothing in a panel that is never key: set cursors from an always-active tracking area (`HoverCursorView`).
- The stop button and Control-Option-Command-Period abort the agent's own turn: press them only on a scratch HUD.
