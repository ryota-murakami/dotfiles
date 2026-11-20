# This Mac

The skill is used on one machine by one person, so what was learned about that machine is written here instead of being rediscovered. An app update can change any of it: when a fact below fails, check it and correct this file.

## Screen and shell

- One display, 1728 × 1117 points (Retina 2x). The Dock hides itself.
- The display has a notch (built-in Liquid Retina XDR, 3456 × 2234): x 771.5–956.5 points, 32 points high (`NSScreen.safeAreaInsets.top`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`). The user keeps the status bar up there, beside the menu bar; a screenshot does not show the notch, so judge by coordinates.
- Terminal.app opens `fish`. `dw term` installs its exit-status hook for it.
- The Bash tool runs `zsh`: `local path=…` empties `PATH` inside a function (`path` is tied to it). Write helper scripts for `/bin/bash` and run them as files.
- `agent-desktop list-windows` does not list the HUD's own panels (bar, mirror, explainer, prompt). Look at them with `screencapture -x -R x,y,w,h file.png`; their frames are in the state folder (`hud-position`, `explain-frame`, `ask-position`, bottom-left origin).

## PhpStorm (2026.3)

**Keymap `MySetting`** (parent: Mac OS X 10.5+), the user's own. Many defaults are removed. Source: `~/Library/Application Support/JetBrains/PhpStorm2026.3/keymaps/MySetting.xml`.

| Action | Shortcut here | The default it replaces |
| --- | --- | --- |
| Find Action | `cmd+p` | `shift+cmd+a` |
| Go to File | `cmd+o` | `shift+cmd+o` |
| Search Everywhere | `shift+cmd+p` | double Shift |
| Terminal tool window | `cmd+2` | `alt+f12` |
| Commit (`CheckinProject`) | `ctrl+g` then `ctrl+c` | `cmd+k` |
| Reformat Code | `ctrl+space` | `alt+cmd+l` |
| Highlight Usages in File | `shift+cmd+u` | `shift+cmd+f7` |
| Hide the active tool window | `ctrl+x` then `ctrl+c` | `shift+esc` |
| Line start / line end | `cmd+left` or `ctrl+a` / `cmd+right` or `ctrl+e` | |
| Extend selection one line down | `shift+down` or `ctrl+cmd+n` | |

- **Editor colours** (the user's dark theme): a selection is painted about `#214283`-like blue (blue channel well above red), the editor background near black. `magick` (ImageMagick) is installed for reading pixels from a `screencapture`.
- **No shortcut at all**: Hide All Tool Windows, Paste as Plain Text, Go to Line, Reload All from Disk, Run context configuration (`RunClass`), the Commit and Services tool windows. Reach them through the menu bar (`--surface menubar`, pressed by accessibility) or Find Action.
- **Unchanged defaults**: `cmd+v` paste, `cmd+s` save all, `cmd+w` close tab, `cmd+a` select all, `cmd+backspace` delete line.

**Driving it**

- `phpstorm --line N --column 0 <absolute path>` opens the file in the running IDE with the caret at the start of line N: addressed, no dialog. The window title ends with the absolute path of the active editor, so wait for the title instead of sleeping.
- A paste with `cmd+v` at column 1 kept PHP and plain text byte for byte in tests (no reformatting, no import dialog). Still save and diff every file against its source.
- Replacing lines: caret at the start of the first line, `shift+down` once per line, then paste.
- A file changed from outside did not refresh in the open editor within 3 seconds while the IDE had focus. After `git` or a script changed files, use File → Reload All from Disk, or switch away and back.
- The editor font is large (about 13 points per character): roughly 69 columns fit beside an explainer of 42%. The user prefers the window maximized with the explainer over its right side.
- The accessibility tree lists the tool window buttons (Project, Git, Services, Terminal, Database…) and the status bar widgets, including the branch name.
- Full-window snapshots and `find` fail while the Project tree is open (`RefMap exceeds 1MB`); `--skeleton` works. Clicking the Project stripe button by ref timed out once: cause unknown, look before relying on it.
- In the keymap file an action written as an empty element (`<action id="HideAllWindows" />`) has **no** shortcut; the `<keyboard-shortcut>` on the following lines belongs to the next action. Read the shortcut inside the action's own element. (`shift+cmd+u` was once taken for Hide All Tool Windows that way: with lines selected it opens the find bar instead. `escape` closes it.)
- To point at code: `phpstorm --line FROM --column 0 <path>`, then `shift+down` once per line through TO, then `dw explain --back`. The selection stays highlighted (greyed) while another app has focus.

**Committing in the IDE** (worked on 2026-11-19)

1. Open the commit view with the toolbar button `Commit…` (click by ref). Here it is the `Local Changes` tab of the Git tool window at the bottom left.
2. New files sit under `Unversioned Files`, unticked. Tick the checkbox with a physical click at a place read from a screenshot (the rows have no bounds). Do not press Space: focus is in the message field.
3. Set the message with `set-value` on the text field `Commit Message` and read it back.
4. Click the button `Commit` by ref, then check `git log -1`.

## How the user arranges a walkthrough

- PhpStorm maximized, the explainer panel over its right side and widened to about two thirds of the screen while reading. The panel must not sit on top of the code: it stacks like a window (asked for on 2026-11-20).
- When code is the thing to read: PhpStorm in front, the lines being explained selected, and the explanation in a note popup beside the selection (the bar is too short for it: asked for on 2026-11-20). The long page stays behind and comes forward with the book button.
- The bar must say what is going on: the stop button only while the walkthrough acts, a state label otherwise. With the green line around the screen the user keeps their hands off; without it they check mail or chat, also in the middle of a walkthrough.
- Other apps are used in between (Slack, the chat). Keys are never sent while PhpStorm is not the focused window: wait for it to be in front again, or bring it forward as part of an announced step.
- The status bar at the very top, beside the menu bar and the notch. The prompt card parked at the left edge.
- Presses 読んでいます while reading and 質問・中断 to give feedback about the HUD itself, then types in the chat.
- While an answer or a fix to the skill is being prepared, moves between desktops (the chat, Slack) and quits the HUD from its settings; asks for the walkthrough to go on in the chat, which takes `dw resume <record>` (seen twice on 2026-11-20).
