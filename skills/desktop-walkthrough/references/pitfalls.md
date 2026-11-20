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
| The walkthrough moved on to the next page although the user had pressed 質問・中断 | The background wait ended with `; echo "exit=$?"`, so the task reported exit 0 whatever the answer was, and the call that read its output also ran the next step | A background `dw wait-user` is the last command of its task (no `echo` after it): the task's own exit status is the answer (0 next, 1 question, 130 stop). Read the answer in a call of its own, then act |
| The code under the explainer could not be read: the panel stayed on top of the editor whatever was clicked | It floated above every app, like the bar | The explainer stacks like an ordinary window (a setting keeps it on top). For code: app to the front, `dw explain --back`, the lines selected, the explanation on the bar |
| An edge of a panel could be dragged, but the pointer never showed it | Cursor rects only work in the key window of the active app, which a HUD panel never is | Resize handles set the cursor themselves from an always-active tracking area (`HoverCursorView`); the click-through bar does it from its pointer polling |
| A shortcut from the notes opened a find bar in the IDE instead of hiding the tool windows | The keymap file had been misread: an empty `<action id=… />` means the shortcut was removed, and the next action's shortcut was taken for it | Read a shortcut inside its own action element; after an unverified shortcut, look at the screen before the next step |
| The explanation of selected code was cut off after a line or two | It was written on the status bar | `dw note` shows it in a popup beside the selection; the bar only says where to look |
| The red stop button showed while nothing was happening on screen (the agent waited, or edited the skill) | It was a fixed control | The trailing end of the bar follows the session: stop button while the walkthrough acts, otherwise 待機中 / スキル更新中 / その他作業中 |
| The settings card opened outside the screen | It always opened above the bar, and the bar sat at the top | Popups are placed like tooltips (`popupFrame`): the first side with room, never off the screen |
| A wait for the user's answer ended by itself (exit 3) | The HUD was replaced by a new build while the question was open | The wait tolerates a HUD that is gone for a few seconds; after a HUD change, check that the open question is still being waited for |
| The user could not tell whether a button press had registered: nothing changed for three to five seconds | The press travels through files the session polls, then a turn starts and the model thinks before its first action | The bar shows the press on its way, then delivered, with a progress line that completes at the agent's first reaction (`Pending.swift`); the first action after a press is a quick `dw say` |
| A performed step fell apart: the user had switched to another app (a chat, mail) and the agent's keys were refused | Nothing on screen said whether the agent was driving the Mac or only thinking | While the walkthrough acts, a thin green line surrounds the screen and the stop button shows; in every other state the Mac is the user's. After such a stretch, announce and bring the window forward before acting |
| The explainer and the note covered the user's mail on another desktop while the agent worked on something else | Every HUD window joined all desktops (Spaces) | Only the status bar and the screen border show on every desktop; a page, note, question or the mirror stays where it was shown, and only a new one (or its button on the bar) brings it to the current desktop |
| A new HUD build reopened the explainer the user had closed, on the desktop they were working on | At launch every page already in the index counted as a new page | Pages present at launch are loaded without showing the panel: it stays open or closed as the user left it. Only a page added while the HUD runs opens it |
| `dw resume` opened the explainer the user had closed, on the chat's desktop, before the app was brought forward | The record's pages were put back after the HUD had started, so each one counted as a new page | `dw resume` puts the pages back before it starts the HUD: they are loaded as pages that were already there |
| The pointer stayed an arrow over the edges and grips of the HUD's panels: nothing showed that they can be dragged | The window server takes a cursor change only from the active app, and the HUD stays in the background | The HUD allows itself to set the cursor in the background at launch; a cursor is checked while another app is active |
| The prompt card stayed over the page being read: a click in the explainer did not put the page over it | The card is above every window, and beside an explainer as tall as the screen it has no room to step aside to | A click in the explainer sends the card behind it (`tuckAsk`). It is on top again when the card or the hand button on the bar is clicked, when a new question arrives, and when the explainer is closed, moved off the card or covered by an app |
| A note covered the first lines of the code it explained | The selection was taller than half the editor, no side of it had room for the note, and the note was clamped onto it | For a tall selection pass a larger `--width`: a wide note is short and fits above or below. Look at a screenshot after showing a note |
| A line number in a table of a note was split over two lines (`10` over `5`) | Pages and notes break words anywhere so that long identifiers fit; in a table that lets a column shrink to two characters | Table cells break a word only when it overflows by itself (`overflow-wrap: break-word` on `th, td` in `explainer/page.html` and `explainer/note.html`) |
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
- To show which lines an explanation is about, select them (caret at the first line, extend the selection line by line) with the IDE in front of the explainer. The selection's rectangle for `dw note --anchor` can be read from the screen: whole-line selections are painted in one blue across the editor's width (scan a pixel column near the right edge for the band, a row through it for its left edge, and the non-blue pixels inside it for where the text ends). Clear the note first: it would cover the column.

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
