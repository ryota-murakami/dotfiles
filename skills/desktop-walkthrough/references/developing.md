# Developing the skill

How to change the HUD, the session bridge or `dw`, and try the change without disturbing the walkthrough on screen. `README.md` says where the source lives and how the install is linked.

## What the HUD is for

The owner's goal (said on 2026-11-20): an agent that feels native to macOS. A harness today is used inside its own app (the chat, a built-in browser, built-in tools), and work outside it (computer use) means leaving the chat session. If the OS itself wrapped the harness there would be nothing to leave. The HUD is that wrapper: the agent's status, the conversation and its message box, its questions and its explanations are over whatever app is in front.

Judge a change by that. The HUD is with the user all day, over any app, like a part of the system: it follows the platform's conventions, and each thing that still sends the user back to the chat is a gap to close.

## Where things are

| Path | Holds |
| --- | --- |
| `scripts/dw` | the helper: every command the agent runs. One function per command, dispatched at the bottom |
| `hud/HUD.swift` | the HUD class: stored views, launch, timers, settings, stop, lifecycle, and the paths of the state files |
| `hud/Bar.swift` | the status bar, its click-through, and the session state (`currentActivity`) |
| `hud/Border.swift` | the green line around the screen while the walkthrough acts |
| `hud/Explainer.swift`, `explainer/page.html` | the explainer panel and the template of a page; the reading panel shared with the note, and Command-C for a selection in either (`PageSelection`) |
| `hud/Note.swift`, `explainer/note.html` | the note popup and the template of a note |
| `hud/Reading.swift` | reading feedback: the progress kept in `progress.json`, the achievements, what a mark, an understood note and 次へ lead to |
| `hud/Sound.swift`, `sounds/synth.py` | playing the sound effects; their source (rendered to `<state>/sounds` by `dw` before it starts the HUD) |
| `hud/Effects.swift`, `explainer/effects.html` | the effects layer: a see-through window over the screen and the page that draws in it (banner, achievement, sparks, ring) |
| `hud/AskPrompt.swift` | the prompt card: answers, feedback buttons, parking, stepping behind the explainer, staying on the desktop of its page |
| `hud/Pending.swift` | the delivery progress of a press |
| `hud/Mirror.swift` | the conversation mirror and its message box; the shared edge resize handle |
| `hud/Settings.swift`, `hud/SettingsCard.swift` | the options (add one line to the registry to add a setting) and the card that shows them |
| `hud/Controls.swift` | shared controls: buttons, the state badge, tooltip-style placement (`popupFrame`), cursors, hot keys (`HotKey`), a shortcut of modifier keys alone (`ModifierChord`), a shortcut the user records (`Shortcut`, `ShortcutRecorder`), and the switch that hides every surface (`hudHidden`, applied by `NSWindow.setConcealed`) |
| `hud/Appearance.swift` | the look every surface shares: the dark appearance, each surface's colour, the material behind translucent surfaces, the accessibility display settings |
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
5. Put the new build in front of the user: `dw note --clear` (a note still on file is shown again at launch, on whichever desktop is active), `touch <state>/quit`, wait for the HUD to exit, then any `dw say`: it rebuilds and relaunches, with the explainer and the mirror open or closed as the user left them. A HUD the user quit from its settings is not relaunched (`hud-closed-by-user`): leave it closed and say so.
6. A change to `explainer/page.html` reaches pages already shown with `dw explain --rebuild` (every page is built again from its Markdown); `explainer/effects.html` and `sounds/synth.py` are taken up when `dw` next starts the HUD.
7. A change under `hooks/` or `.claude-plugin/` reaches the running session only after the user runs `/reload-plugins`. Make the HUD work with the bridge that is loaded until then (a missing file means "not known", never "no").

## Things that bit

- The live HUD and a scratch HUD are both called `StatusHUD`: accessibility queries by app name reach the live one. Click the scratch one by coordinates read from a screenshot.
- The bar ignores the pointer until it rests on a control: `mouse-move`, wait half a second, then click.
- A web view in a panel that is not on screen can report a size it will not keep: measure again once the panel shows.
- Cursor rects do nothing in a panel that is never key: set cursors from an always-active tracking area (`HoverCursorView`). The window server also ignores `NSCursor.set()` from an app that is not active, which the HUD almost never is: `allowCursorInBackground` lifts that at launch.
- A cursor is checked with another app active, as in a walkthrough. The HUD's own `NSCursor.current` changes even when the screen keeps the arrow: read `NSCursor.currentSystem` from a throwaway tool that moves the pointer with posted mouse-moved events, and capture with `screencapture -C`. The pointer is the user's: move it only when `CGEventSource.secondsSinceLastEventType` says their hands are off, and put it back.
- A page template is tried in a browser before the HUD: build it with test data in place of `<!--DW_DATA-->`, serve it over http beside a copy of `<state>/explain/vendor` (the page's own policy allows `file:` only: widen it to `'self'` in the copy), and define `window.webkit.messageHandlers.dw.postMessage` before the page loads to collect what it reports. Headless, nothing shows on the user's screen, and what the page sends the HUD is the result. `effects.html` is tried the same way by calling `fx.banner(…)`.
- To look at a scratch surface, capture its window, never a region of the screen: `screencapture -x -o -l <window number>` (a test-only file writes the surfaces' `windowNumber` to a state file). A region shows whatever is there now, and that was the user's chat app twice: they had brought their window over the scratch panel, and later moved to another desktop. The effects layer captured by its window is the effect on a clear background.
- A scratch HUD is driven without the pointer: a test-only file evaluates script in the web views (`document.querySelector('#rd-go').click()`), calls `hud.answerAsk("ok")`, and logs every sound and effect. A scratch `settings.json` with a low `feedback.volume` and `mirror.visible` 0 keeps it quiet and small.
- A shadow set on the layer of a view (`layer.shadowOpacity`) is not drawn: AppKit owns that layer and takes the shadow from the view (`view.shadow = NSShadow()`); the layer's `shadowOpacity` can then be animated. Found when the glow of the main answer never showed.
- The stop button and Control-Option-Command-Period abort the agent's own turn: press them only on a scratch HUD.
- A keyboard shortcut reaches the HUD only as a Carbon hot key (`HotKey`), and a registered hot key is taken from every other app, the live HUD included: the stop shortcut pressed for a scratch HUD stops the live one too. Register one only while it means something (Command-C: `HUD.updateCopyHotKey`), and test it on a scratch HUD with a posted key event (`CGEvent`, `.cghidEventTap`) after a test-only file confirmed that it is registered: an unregistered key would land in the user's app.
- A posted key event for a function key triggers a hot key only with the function flag among its flags (`.maskSecondaryFn`), as a real keyboard sends it. F13 to F20 with Control-Option-Command make test shortcuts no app uses: give the scratch HUD one in its `settings.json` (`hud.toggleKey` = modifiers × 1000 + key code).
- A shortcut of modifier keys alone (`ModifierChord`) is tried by posting flags-changed events to the scratch HUD's own process (`CGEvent.postToPid`, the event's type set to `.flagsChanged` and its flags to the raw value with the left/right bits, such as `0x180150` for right Option with right Command): they reach its local monitor and leave the user's keyboard alone. Posted system-wide (the only way to try the global monitor) they hold those modifiers for every app for that moment, and the user's next key becomes a shortcut: post all four changes within a few milliseconds, and only after `CGEventSource.secondsSinceLastEventType` says the keyboard is idle and `flagsState` that no modifier is down.
- Posted key presses and clicks are not counted by `CGEventSource.secondsSinceLastEventType` or `counterForEventType`: only real input is. The chord's rule "nothing else was pressed while it was held" reads them, so it cannot be tried with posted keys.
- A scratch HUD reads `explain-frame` once, at launch: write the frame before starting it. `ask-position` is read on every tick, so a card can be moved over the explainer (to try `tuckAsk`) while it runs.
- The user's own clicks close a scratch settings card (it closes on a click outside it) between two test commands: give the test-only file a whole sequence at once, and have it note the state at each point.
- The settings card takes the keyboard only while a shortcut is recorded. Try the recorder's rules by handing it key events in-process (a test-only file calls its `keyDown` with `NSEvent.keyEvent`). Post a real key only after the test-only file confirmed that the card is key and recording, and only a shortcut no app uses: a key posted while the card is not key lands in the user's app.
- A surface that hides conceals itself before it orders itself in (`setConcealed`, then `orderFrontRegardless`): the other way round, one that opens while the HUD is hidden could show for a frame.
- A page can run script for a test without a click: Markdown passes HTML through, so `<img src="x" onerror="…">` runs when the page renders (selecting a paragraph, for the copy shortcut).
- `dw start` on a scratch folder starts a real agent-desktop session, whose cursor overlay shows on the user's screen and stays after the folder is deleted. To test `dw`'s own flow, put stand-ins first: a script named `agent-desktop` on `PATH` that logs its arguments and `AGENT_DESKTOP_SESSION`, and a script at `<scratch>/bin/StatusHUD` that writes `hud.pid` and waits for `quit`. Nothing shows on screen, and the log is the result.
- A system colour (`systemBlue`, `labelColor`) read outside of drawing can resolve for the light theme, and a layer keeps the value it was given: give layers `color.hudCG`. Text fields and symbols take the colour itself and follow the app's appearance (`hudAppearance`).
- A new translucent surface gets `makeHUDMaterial` under its tint and `surfaceAlpha` for its opacity, and an `applyLook()` that `HUD.applyDisplayOptions` calls. The three accessibility display settings (contrast, transparency, motion) are the user's system settings: their code paths have not been watched on screen yet, and switching them for a test needs the user's word.
- A click posted at a scratch panel lands on whatever window is in front at that point, and the user's app may have come over the panel since it was shown: run `dw explain --show` on the scratch HUD right before the click. Which surface is over which is read from `CGWindowListCopyWindowInfo` (on-screen windows come front to back, each with its layer: 0 ordinary, 25 status bar), before and after the click.
- A window at the ordinary level (the explainer) that is ordered out and in again returns to the desktop (Space) it was on; a `.transient` one comes to the active desktop. Every surface but the bar and the border is `.transient` (`stageCollectionBehavior`), and is moved only by `orderFrontOnActiveSpace`.
- Ordering a surface out and in to hide it for a moment moves it to whichever desktop is active when it returns: hide it with `setConcealed` (invisible and click-through, still on its desktop).
- Which desktop a window is on can be checked without switching desktops, with two private window-server calls in a throwaway Swift tool: `CGSCopySpacesForWindows(CGSMainConnectionID(), 7, [windowNumber])` lists a window's desktops for any process (window numbers from `CGWindowListCopyWindowInfo`), and `CGSMoveWindowsToManagedSpace` moves a window to another desktop, but only the calling process's own windows: build the scratch HUD from a copy of `hud/` with a file that does it on request. Have the same file write each surface's desktop and flags to a state file, and call a button's action on request (`hud.showAsk()`): a test of the desktops then needs no screenshot, no click and no desktop switch.
