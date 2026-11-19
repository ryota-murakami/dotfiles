# Pitfalls from real runs

Each row is something that actually went wrong, why, and the rule or helper that now prevents it.

## Wrong target, wrong content

| What happened | Cause | Rule |
| --- | --- | --- |
| Text meant for a popup was typed into a source file | The popup had not opened (or closed on focus change) and keys went to the editor | Confirm the popup is the focused surface before typing; type by ref into its field |
| A comment was posted as the wrong account | Two browser windows of one app: keys went to the app's key window, not the intended one | Focus the exact window id, verify it, and check which account that window is signed in as |
| The user's own typing merged with a command and launched another program | The command was pasted into a focused terminal while the user typed | `dw term run` sends by window id, clears the prompt line first, and refuses while a command runs |
| A file path was typed as garbled Japanese | Key-by-key input went through the input method | Enter text by ref (`type`, `set-value`) or clipboard |
| A paste left the file different from the source | The IDE reformatted pasted code | Use the IDE's plain-text paste, then diff the saved file against the source |
| A new file got the user's sentence as its name | The user typed while a filename dialog was open | Pause automation while the user types in the HUD (`typing` flag); verify the created path |
| A key meant to tick a checkbox put a full-width space into another field | The row had been clicked by ref, which does not move keyboard focus; the key went to the field that had it, through the Japanese input method | After a ref click, act by ref (`set-value`, `check`) or click physically at a place read from a screenshot; never send a key on the assumption that focus followed |
| A drag meant for the HUD moved the chat window instead | The user had closed the HUD; the command that said so and the drag were chained with `;` | Chain a physical action to its precondition with `&&`; try HUD changes on a scratch HUD (`StatusHUD <tmp state folder>`) |
| A file was reported different from its source although it was identical | `git diff <commit> -- <path>` does not see a file that is not tracked yet | Compare contents: `git show <commit>:<path> \| cmp - <path>` |
| A test failed on a step taken straight from the tutorial | An earlier chapter's file was missing a method | When a check fails, compare earlier files with their source before blaming the new step |

## Waiting and visibility

| What happened | Cause | Rule |
| --- | --- | --- |
| A failed build went unnoticed until a timeout | The helper waited for a success pattern in the prompt | Exit status comes from a shell hook; `dw term check` reports FAILED at once |
| The session froze while a command ran | The tool call waited for completion | Start, return, check for a bounded time, come back later |
| The user could not tell what was happening | Status lived in the chat, on another desktop | `dw say` before every action; one line goes on the bar, long explanations go to the explainer (`dw explain`) |
| A walkthrough of a codebase needed pages of reasoning and diagrams; the bar showed one line and the chat was on another desktop | The HUD had no surface for long-form text | `dw explain <file.md>` shows Markdown, code and mermaid diagrams as pages beside the app; `dw stage` lays out app, explainer and bar without overlap |
| The approval prompt covered the title of the page being read | It followed the bar and could not be moved | Drag it by its left part; the place is remembered (reset in the settings) |
| The prompt came back each time the user pushed it off-screen to read | Its saved place was clamped to the visible screen | Past a screen edge it parks as a 44-point strip (buttons off, so a strip cannot answer by accident) and shows in full while the pointer is on it |
| The agent could not tell whether the user was reading, stuck or away during a long wait | A wait had only two answers, and the user does not watch the agent's terminal | `--button "<label>"` on `dw ask` / `dw wait-user`: feedback buttons with the agent's own wording; a press arrives as a message and the question stays open |
| Part of the status line could not be read with the bar at the top of the screen | The text ran under the display notch of the MacBook | The status line leaves the notch's span empty and continues after it (`StatusLabel`, from `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`) |
| A status bar left in the middle of the screen covered the page being read | Surfaces remember where they were last dragged, whatever the next walkthrough needs | `dw stage <window>` at the start of a walkthrough that uses the explainer |
| Windows could not be focused or tiled | They sat on another desktop (`visible: false`, not accessible) | Create the working windows on one desktop; `dw front` switches through the Dock |
| A click hit the HUD mirror instead of the page | The mirror floats above apps | `dw click-xy` hides the mirror for the click |
| The HUD disappeared mid-run while narration kept going | It quit with the agent process it was started from; the agent CLI restarted under the same session (model/effort change) with a new pid | `dw` records the current pid in `owner.pid` on every call, the HUD waits 10 minutes before giving up on a missing owner, and `say`/`ad` relaunch it |
| The bar showed `Read: /tmp/…png` for minutes while the user was meant to answer a question | Every un-narrated tool call replaced the status line | The bridge leaves the bar alone for tools that only read and while a question is open (`showsToolOnBar`) |
| The first page appeared half an hour after the walkthrough started | Tools were built and the environment explored before anything was shown | Show a roadmap page first, prepare while the user reads |
| The HUD stayed after the work ended | Nothing closed it | `dw end`, the quit button in the HUD's settings, and the HUD exits with the owning session |

## Tools

| What happened | Cause | Rule |
| --- | --- | --- |
| The agent-desktop cursor overlay drew nothing while reporting success; clipboard commands failed | npm install without its postinstall leaves a launcher that spawns a platform-named binary (upstream issue 385) | `dw doctor` detects it and prints the fix; repair before building a replacement |
| The built-in cursor label truncated explanations | It is one line, 360 pt, at most 12 words (upstream issue 407) | Narration lives in the HUD, not in the cursor label |
| A window at screen-saver level, a non-activating text panel | Suspected of blocking desktop switching; dictation tools could not reach the field | HUD windows stay at status-bar/floating level; the mirror activates on click and returns focus on Enter or Esc |

## Per-app notes

**agent-desktop**
- Refs die on any UI change: snapshot again right before acting. Menus rebuilt on each open (Dock menus) need a fresh snapshot or a screenshot and coordinates.
- `find` over a very large page times out: use `snapshot --skeleton` and drill with `--root`, or scope with `--window-id`.
- HTML `<select>`: `select` and `set-value` fail. Click it, snapshot `--surface menu`, click the menu item, then read the value back.
- `set-value` on text inputs and `check`/`uncheck` on checkboxes work for web forms; verify with a fresh read.
- A file dialog is a sheet: click the sidebar folder, then the row whose child text is the file name.
- `pgrep` on macOS skips its own ancestors unless `-a` is given.
- The HUD bar lets clicks through except where the pointer rests: to click one of its buttons physically, `mouse-move` onto it, wait a moment, then `mouse-click` (the same before a `drag` that starts on its edge: without the wait the drag lands on the window behind); or press it through accessibility (`find --app StatusHUD --role button`), which moves no pointer.
- The stop button and Control-Option-Command-Period abort the agent's own turn: never press them on the live HUD to test it; use a scratch state folder (`StatusHUD /tmp/x`).

**JetBrains IDEs**
- A full-window `snapshot` can fail with `RefMap exceeds 1MB` (and `find` can time out) while the Project tree is open: use `--skeleton`, or take one `-i --compact` snapshot and read `get <ref> --property bounds` for what you need. Menu bar refs go stale at once (the IDE rebuilds its menus); toolbar buttons keep theirs.
- Tree rows (the changes list of the commit view) report no bounds and unstable names: tick their checkboxes by a physical click at a place read from a screenshot.
- Shortcuts may be remapped: read `~/Library/Application Support/JetBrains/<IDE>/keymaps/*.xml` (active one named in `options/mac/keymap.xml`), or run actions through Find Action by name.
- Popups (Go to File, New File, Find Action) are separate surfaces: wait until the main window is no longer the focused window, then type into the focused surface's text field by ref.
- New File accepts `folder/file.ext` relative to the current file's folder, but cannot create a folder beside the project root from there: use the framework's generator or the project view.
- After pasting, save and diff. New files may be auto-added to version control.

**Chrome**
- Reach the address bar through a skeleton snapshot of that window; the page tree can be huge.
- Use an incognito window for a second account, and expect password-manager prompts over the page: dismiss them without saving demo accounts.
- A click that silently did nothing often opened a context menu or a find bar: look before retrying.
- On this Mac, DevTools opens with **Ctrl+Space** (the user's shortcut). ⌥⌘J and View → Developer → JavaScript Console may show nothing visible here.
- Very long pages (a full tutorial article) make accessibility queries (`find`, `list-windows`) time out and stall: drive such pages with keys and screenshots, and check the front app with `osascript` instead.
- The console refuses pastes until `allow pasting` is typed; switch the input method to ASCII first.

**Terminal.app**
- `dw term` works by window id through Terminal's scripting interface, so it does not depend on focus or the visible desktop. Other terminal apps need focus-verified paste instead.
- Never send anything to the window that hosts the agent's chat (`dw start` prints its id).
