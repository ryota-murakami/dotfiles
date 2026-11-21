// Status HUD for desktop walkthroughs: shows what the agent is doing while it operates the Mac.
//
// - Status bar: translucent and click-through; drag the grip to move it, the right edge to change its
//   width, the top or bottom edge to change its height (a taller bar shows more lines of the status).
//   Beside the display notch the text leaves the notch's span empty.
//   Always-visible controls: mirror on/off, settings, and a one-click stop at the trailing end.
// - Mirror: the conversation of the agent session with a message box; close button in its header,
//   drag the header to move, any edge to resize.
// - Settings: one registry (Settings.swift) shown as a card above the bar (SettingsCard.swift).
// - Stop: the red button on the bar, or Control-Option-Command-Period from anywhere.
// - Hide: right Command with right Option, pressed together and let go (the user can record other
//   keys in the settings), takes every surface off the screen and brings it back; the HUD keeps
//   running meanwhile.
//
// The status bar never takes focus. Clicking the mirror makes the HUD the frontmost app so dictation
// tools can reach its message box; Enter or Esc gives focus back to the app that had it.
// Everything is driven by small files under <state-dir>, shared with `scripts/dw` and the mod.
//
// Files: this one holds the paths shared with `scripts/dw` and the mod, and the HUD class with its
// stored views, launch, settings, stop and lifecycle. Each surface adds its methods in a file of
// its own: Bar.swift (status bar), Mirror.swift (conversation and message box), AskPrompt.swift
// (one-click answers), SettingsCard.swift (settings UI over Settings.swift), Controls.swift
// (shared controls and the stop shortcut). Reading.swift holds the reading feedback (what was read,
// achievements, the cleared page), with Sound.swift and Effects.swift for what answers it.
import AppKit
import Carbon.HIToolbox
import QuartzCore

/// State folder shared with the `dw` script and the hud-bridge mod: argument 1, else the default.
let stateDir: String = CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("--")
    ? CommandLine.arguments[1]
    : "\(NSHomeDirectory())/.local/state/desktop-walkthrough"
let bridgeDir = "\(stateDir)/bridge"
let statusPath = "\(stateDir)/status.txt"
/// Present while `dw click-xy` needs the mirror out of the way.
let mirrorSuspendPath = "\(stateDir)/mirror-suspend"
/// `dw stage` asks for frames here: `{"bar": [x, y, width], "explain": [x, y, width, height], "mirror": [x, y, width, height]}`
/// in screen points from the bottom-left corner. Applied once, then the file is removed.
let placeRequestPath = "\(stateDir)/place.json"
let positionPath = "\(stateDir)/hud-position"
let widthPath = "\(stateDir)/hud-width"
/// Bar height chosen by dragging its top or bottom edge (points).
let heightPath = "\(stateDir)/hud-height"
/// Mirror frame chosen by dragging ("x,y,width,height" in screen points).
let mirrorFramePath = "\(stateDir)/mirror-frame"
/// `dw ask` / `dw wait-user` write {"id","text"[,"ok","no","icon"]} here; the answer goes to askAnswerPath ("<id> ok|no").
let askPath = "\(stateDir)/ask.json"
let askAnswerPath = "\(stateDir)/ask-answer"
/// Where the user dragged the prompt ("x,y" in screen points); absent = it follows the status bar.
let askPositionPath = "\(stateDir)/ask-position"
/// Pid of the `dw` process currently waiting for the answer (absent or dead = nobody waiting).
let askWaiterPath = "\(stateDir)/ask-waiter"
let feedPath = "\(bridgeDir)/feed.jsonl"
let statePath = "\(bridgeDir)/state.json"
let inboxPath = "\(bridgeDir)/inbox.jsonl"
let controlPath = "\(bridgeDir)/control.jsonl"
/// Stop switch shared with the hud-bridge mod and the agent's shell helpers: "on" / "off"
let stopSwitchPath = "\(bridgeDir)/stop"
/// What the newest tool call of the running turn is, by the bridge mod: "skill", "waiting" or "other".
let toolClassPath = "\(bridgeDir)/tool-class"
/// Touched by `dw` whenever it acts on the screen (keys, clicks, windows, terminal commands)…
let actionStampPath = "\(stateDir)/activity-action"
/// …and whenever it narrates (say, step, explain, note). Their times against the tool call's tell
/// whether the walkthrough itself is what is running.
let narrationStampPath = "\(stateDir)/activity-narration"
/// Present while the person is typing in the HUD's message box: the agent's GUI steps wait
let typingPath = "\(stateDir)/typing"

func isStopOn() -> Bool {
    ((try? String(contentsOfFile: stopSwitchPath, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "on"
}

func setStop(_ on: Bool) {
    try? FileManager.default.createDirectory(atPath: bridgeDir, withIntermediateDirectories: true)
    try? (on ? "on" : "off").write(toFile: stopSwitchPath, atomically: true, encoding: .utf8)
}

/// CGWindowID of the terminal window hosting the agent's chat (0 = unknown): the mirror hides while it is in front.
let claudeWindowID = CGWindowID(ProcessInfo.processInfo.environment["DW_CLAUDE_WINDOW"] ?? "") ?? 0
/// PID of the agent process at launch (0 = none). The agent CLI can restart under the same session
/// (model or effort change, update), so `dw` rewrites the current pid to `owner.pid` on every call.
let launchOwnerPID = pid_t(ProcessInfo.processInfo.environment["DW_OWNER_PID"] ?? "") ?? 0
let ownerPidPath = "\(stateDir)/owner.pid"
/// Seconds the owner may be gone before the HUD quits: long enough for a restarted agent to call `dw` again.
let ownerGraceSeconds: TimeInterval = 600
/// Written only when the user quits from the settings, so `dw` does not reopen a HUD the user closed.
let closedByUserPath = "\(stateDir)/hud-closed-by-user"
/// `dw end` creates this file to ask the HUD to quit through the same path as the settings item.
let quitRequestPath = "\(stateDir)/quit"
/// `dw start` writes the id of the walkthrough's agent-desktop session here; that session draws the cursor overlay.
let adSessionPath = "\(stateDir)/ad_session"
/// Rewritten every second: the mod and `dw` ignore the typing flag once this heartbeat is stale.
let alivePath = "\(stateDir)/hud.alive"
let pidPath = "\(stateDir)/hud.pid"
/// Present while the user has hidden the HUD with its shortcut ({@link HUD.toggleHidden}); it holds
/// the keys that bring the HUD back ("右⌥右⌘"). Read by `dw`, which tells the agent that what it
/// shows is out of sight.
let hiddenPath = "\(stateDir)/hud-hidden"

/// Option values, shared by the HUD and the settings card.
let settings = SettingsStore(stateDir: stateDir)

func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
func mtime(_ path: String) -> Date? { (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date }

/// Holds the folder of the walkthrough being recorded (written by `dw start` / `dw record`).
let recordDirPath = "\(stateDir)/record_dir"

/// Add a line to the journal of the walkthrough being recorded, for events only the HUD sees
/// (a feedback button, an answer nobody was waiting for). `dw` writes the other lines.
func appendJournal(_ text: String) {
    guard let dir = (try? String(contentsOfFile: recordDirPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines),
          !dir.isEmpty, let handle = FileHandle(forWritingAtPath: "\(dir)/journal.md") else { return }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    handle.seekToEndOfFile()
    handle.write("- \(formatter.string(from: Date())) \(text)\n".data(using: .utf8)!)
    handle.closeFile()
}

/// Append one JSON object as a line to a bridge file the mod polls.
func appendLine(_ path: String, _ object: [String: String]) {
    try? FileManager.default.createDirectory(atPath: bridgeDir, withIntermediateDirectories: true)
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          var line = String(data: data, encoding: .utf8) else { return }
    line += "\n"
    if !exists(path) { FileManager.default.createFile(atPath: path, contents: nil) }
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    }
}

/// Drag handle: dragging it moves the window it sits in (the grip of the bar and of each panel),
/// and the pointer shows an open hand over it.
final class DragHandle: HoverCursorView {
    override var hoverCursor: NSCursor { .openHand }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

/// The HUD: status bar, conversation mirror and approval prompt.
///
/// Why it exists: it is the user's window into what the agent is doing, and their controls over it.
/// Created once at launch; timers poll the state files.
final class HUD: NSObject, NSWindowDelegate, NSTextViewDelegate {
    static let defaultBarHeight: CGFloat = 60
    let settingsCard = SettingsCard()

    // Status bar
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let box = NSView()
    let label = StatusLabel()
    lazy var explainButton = IconButton(symbol: "book", label: "解説パネルを表示／隠す", target: self, action: #selector(toggleExplainer))
    lazy var mirrorButton = IconButton(symbol: "bubble.left.and.text.bubble.right", label: "ミラーを表示／隠す", target: self, action: #selector(toggleMirror))
    lazy var settingsButton = IconButton(symbol: "slider.horizontal.3", label: "設定", target: self, action: #selector(toggleSettings))
    /// Shown only while a question is open: shows or hides the prompt card (see {@link HUD.showAsk}).
    lazy var askButton = IconButton(symbol: "hand.raised", label: "確認の枠を表示／隠す", target: self, action: #selector(showAsk))
    /// Width of {@link HUD.askButton} and its gap to the next button: both zero while no question is open.
    var askButtonWidth: NSLayoutConstraint?
    var askButtonGap: NSLayoutConstraint?
    lazy var stopButton = StopButton(target: self, action: #selector(toggleStop))
    /// Shown in the stop button's place while the walkthrough is not acting (see {@link Activity}).
    let stateBadge = StateBadge()
    /// Width of the stop button's slot: the badge is wider than the button.
    var stopWidth: NSLayoutConstraint?
    var lastActivity: Activity?
    /// `busy` of the bridge's state file: true while a turn runs, nil without a bridge.
    var modBusy: Bool?
    /// One outline window per screen, shown while the walkthrough acts (see Border.swift).
    var performingBorders: [NSPanel] = []
    /// When the walkthrough was last seen acting: the state holds for a moment after that (see currentActivity).
    var lastPerformingAt: Date?
    /// The input the user gave last, until the agent has reacted to it (see Pending.swift).
    var pendingInput: PendingInput?
    /// Thin progress line along the bottom of the bar while an input is on its way.
    let pendingBar = CALayer()
    let divider = NSView()
    let resizeHandle = ResizeHandle()
    let barTopHandle = EdgeResizeHandle([.top])
    let barBottomHandle = EdgeResizeHandle([.bottom])
    /// True while the pointer shows a resize cursor set by the bar's polling (see updateClickThrough).
    var barEdgeHovered = false
    /// Height constraints of the bar's controls (buttons, then the divider), adjusted to the bar's height.
    var barControlHeights: [NSLayoutConstraint] = []
    let grip = DragHandle()
    let gripLabel = NSTextField(labelWithString: "⠿")
    /// Material under the bar's tint: it blurs what the bar covers (see {@link makeHUDMaterial}).
    let barMaterial = makeHUDMaterial(cornerRadius: 14)
    /// Symbol before the status line (stopped, typing, a press on its way); empty for the agent's narration.
    let statusIcon = NSImageView()
    var statusIconWidth: NSLayoutConstraint?
    var statusIconGap: NSLayoutConstraint?
    var lastText = ""
    var lastMode = ""
    var positioned = false

    // Mirror
    // Not .nonactivatingPanel: clicking the mirror must make the HUD the frontmost app, or dictation tools
    // (which insert into the frontmost app's focused element) cannot reach the message box
    let mirror = KeyablePanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    let mirrorTitle = NSTextField(labelWithString: "⠿ Claude Code")
    let mirrorRoot = NSView()
    /// Material under the conversation and the mirror's colour over it (see {@link HUD.applyMirrorOpacity}).
    let mirrorMaterial = makeHUDMaterial(cornerRadius: surfaceCornerRadius)
    let mirrorTint = NSView()
    let mirrorGrip = DragHandle()
    lazy var closeButton = IconButton(symbol: "xmark", label: "ミラーを閉じる", pointSize: 12, target: self, action: #selector(closeMirror))
    let mirrorHandles: [EdgeResizeHandle] = [
        EdgeResizeHandle([.left]), EdgeResizeHandle([.right]), EdgeResizeHandle([.top]), EdgeResizeHandle([.bottom]),
        EdgeResizeHandle([.left, .top]), EdgeResizeHandle([.right, .top]), EdgeResizeHandle([.left, .bottom]), EdgeResizeHandle([.right, .bottom]),
    ]
    let busyLabel = NSTextField(labelWithString: "")
    let scroll = NSScrollView()
    let textView = FeedTextView()
    let input = MessageField()
    let sendButton = NSButton(title: "送信", target: nil, action: nil)
    lazy var zoomIn = IconButton(symbol: "plus", label: "文字を大きく", pointSize: 12, target: self, action: #selector(zoomInTapped))
    lazy var zoomOut = IconButton(symbol: "minus", label: "文字を小さく", pointSize: 12, target: self, action: #selector(zoomOutTapped))
    let zoomLabel = NSTextField(labelWithString: "")
    var feedStamp: Date?
    /// Keys of long tool entries the user expanded (like an open <details>), kept while the HUD runs.
    var expandedEntries = Set<String>()
    var zoom: CGFloat { CGFloat(settings.value("mirror.zoom")) }

    // Explainer (dw explain): long-form pages, see Explainer.swift
    let explainer = Explainer()
    // Note popup (dw note): a short explanation beside what it explains, see Note.swift
    let notePopup = NotePopup()
    // Reading feedback, see Reading.swift: what was read, the sounds that answer it, the layer that celebrates it
    let reading = ReadingStore()
    let sounds = SoundPlayer()
    let effects = Effects()

    // Approval prompt (dw ask)
    let askPanel = AskPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let askLabel = NSTextField(wrappingLabelWithString: "")
    /// Symbol before the question (a question mark, a raised hand); hidden when `dw` gave another icon.
    let askIcon = NSImageView()
    /// The question as the session is told about it: its icon as text, then the words.
    var askQuestion = ""
    let askOK = CapsuleButton(style: .primary)
    let askNo = CapsuleButton(style: .secondary)
    /// Feedback buttons of the current question (`--button`): a press sends its label to the agent and leaves the question open.
    let askExtras = NSStackView()
    var askExtraLabels: [String] = []
    /// The card's background: dragging it anywhere outside the buttons moves the prompt.
    let askGrip = DragHandle()
    let askGripMark = NSTextField(labelWithString: "⠿")
    /// Size the card needs for the current question (see `layoutAsk`).
    var askSize = NSSize(width: 420, height: 58)
    var askID = ""
    /// The icon `dw` gave the open question: "🙋" for a hand-over (read this, do this), "❓" for an approval.
    var askIconText = "❓"
    var askStamp: Date?
    /// Origin the HUD last gave the prompt: a different origin later means the user dragged it.
    var askPlacedOrigin: NSPoint?
    /// True while a prompt parked off-screen is shown in full because the pointer is on it.
    var askRevealed = false
    /// False from the moment the user drags the prompt until the pointer has left it once.
    var askRevealArmed = true
    /// True while the card is behind the explainer because the user clicked the explainer (see {@link HUD.tuckAsk}).
    var askTucked = false
    /// True while the card is on a desktop the user called it to with the hand button, away from the
    /// page it asks about (see {@link HUD.showAsk}).
    var askSummoned = false
    /// True while the user has put the card away with the hand button: it stays off every desktop
    /// until the button is pressed again or another question arrives (see {@link HUD.showAsk}).
    var askPutAway = false

    /// Control-Option-Command-Period stops the agent: while the agent moves the pointer, aiming at a
    /// button is hard; a key works wherever the pointer is.
    let stopHotKey = HotKey(id: 1, keyCode: kVK_ANSI_Period, modifiers: controlKey | optionKey | cmdKey)
    /// Command-C over the explainer or the note, registered only while it would copy something there
    /// (see {@link HUD.updateCopyHotKey}).
    let copyHotKey = HotKey(id: 2, keyCode: kVK_ANSI_C, modifiers: cmdKey)
    /// Sees clicks in other apps: a selection left behind in a page is no longer what Command-C means.
    let copyClickWatcher = OutsideClickWatcher()
    /// Hide and show the whole HUD with the keys of the "hud.toggleKey" setting: the chord while the
    /// setting is modifier keys alone, the hot key while it is a key with modifiers (see {@link HUD.applyToggleKey}).
    let toggleChord = ModifierChord()
    let toggleHotKey = HotKey(id: 3, keyCode: kVK_ANSI_H, modifiers: controlKey | optionKey | cmdKey)

    /// When the owning agent process was first seen missing (nil while it is alive).
    var ownerGoneSince: Date?

    var mode: String { isStopOn() ? "stopped" : (exists(typingPath) ? "typing" : "running") }

    override init() {
        super.init()
        buildStatusBar()
        buildMirror()
        buildAskPanel()
        explainer.attach()
        // A click in the explainer puts it over the prompt card too
        explainer.panel.onMouseDown = { [weak self] in self?.tuckAsk() }
        notePopup.attach()
        effects.attach()
        startReading()
        settings.actions["explain.reset"] = { [weak self] in self?.explainer.resetFrame() }
        settings.actions["ask.reset"] = { [weak self] in self?.resetAskPosition() }
        settings.actions["mirror.reset"] = { [weak self] in self?.resetMirrorFrame() }
        settings.actions["bar.reset"] = { [weak self] in self?.resetBarFrame() }
        settings.actions["hud.quit"] = { [weak self] in self?.quitByUser() }
        NotificationCenter.default.addObserver(forName: SettingsStore.changed, object: settings, queue: .main) { [weak self] note in
            if let id = note.userInfo?["id"] as? String { self?.applySetting(id) }
        }
        // The shortcut only ever stops: pressing it again must not clear a stop by accident
        stopHotKey.onPress = { [weak self] in
            if !isStopOn() { self?.toggleStop() }
        }
        stopHotKey.setEnabled(settings.isOn("stop.hotkey"))
        startCopyShortcut()
        // A HUD starts in sight, whatever the last one was
        try? FileManager.default.removeItem(atPath: hiddenPath)
        toggleHotKey.onPress = { [weak self] in self?.toggleHidden() }
        toggleChord.onPress = { [weak self] in self?.toggleHidden() }
        applyToggleKey()
        // While the user records new keys the current ones must reach the recorder, not hide the HUD
        NotificationCenter.default.addObserver(forName: ShortcutRecorder.recordingChanged, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            if (note.userInfo?["recording"] as? Bool) == true {
                self.toggleHotKey.setEnabled(false)
                self.toggleChord.setEnabled(false)
            } else {
                self.applyToggleKey()
            }
        }
        settingsCard.attach(to: self)
        // Contrast, transparency and motion are the user's system-wide choices: follow them as they change
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in self?.applyDisplayOptions() }
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.refresh() }
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.updateClickThrough()
            self?.updatePending()
            self?.updateCopyHotKey()
        }
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.reloadFeed(force: false) }
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.updateTypingFlag() }
        try? FileManager.default.createDirectory(atPath: bridgeDir, withIntermediateDirectories: true)
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(toFile: pidPath, atomically: true, encoding: .utf8)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.housekeeping() }
        housekeeping()
        refresh()
        reloadFeed(force: true)
    }

    // MARK: settings

    /// React to a changed option; called for every change, whichever control made it.
    func applySetting(_ id: String) {
        switch id {
        case "explain.visible": explainer.updateVisibility()
        case "explain.floating": explainer.applyLevel()
        case "border.performing": updatePerformingBorder(visible: lastActivity == .performing)
        case "explain.zoom": explainer.applyZoom()
        case "mirror.visible": updateMirrorVisibility()
        case "mirror.fold": reloadFeed(force: true, keepScroll: true)
        case "mirror.zoom":
            updateZoomLabel()
            reloadFeed(force: true, keepScroll: true)
        case "mirror.opacity": applyMirrorOpacity()
        case "bar.opacity": applyBarColor()
        case "stop.hotkey": stopHotKey.setEnabled(settings.isOn(id))
        case "hud.toggleKey": applyToggleKey()
        case "reading.marks", "reading.dim": applyReadingOptions()
        default: break
        }
    }

    /// Redraw every surface for the accessibility display settings ({@link DisplayOptions}).
    /// Called whenever the user changes one of them.
    func applyDisplayOptions() {
        // The high-contrast variant of the dark appearance: system colours and native controls follow
        NSApp.appearance = hudAppearance
        applyBarColor()
        applyMirrorOpacity()
        applyAskLook()
        explainer.applyLook()
        notePopup.applyLook()
        settingsCard.applyLook()
        updatePerformingBorder(visible: lastActivity == .performing)
    }

    @objc func toggleSettings() {
        settingsCard.toggle()
        settingsButton.isActive = settingsCard.isOpen
    }

    // MARK: hide and show

    /// Put the shortcut that hides and shows the HUD to work with the keys of the "hud.toggleKey"
    /// setting: modifier keys alone are watched as a chord, a key with modifiers is a hot key, and
    /// "なし" (no shortcut) is neither. Called at launch, when the setting changes and when a
    /// recording of new keys ends.
    func applyToggleKey() {
        let shortcut = Shortcut(packed: settings.value("hud.toggleKey"))
        let chord = shortcut.flatMap { $0.isModifiersOnly ? $0 : nil }
        let key = shortcut.flatMap { $0.isModifiersOnly ? nil : $0 }
        toggleChord.setKeys(chord?.modifiers ?? 0)
        toggleChord.setEnabled(chord != nil)
        if let key { toggleHotKey.setKeys(keyCode: key.keyCode, modifiers: key.modifiers) }
        toggleHotKey.setEnabled(key != nil)
        // Keys the system refuses are not kept: the setting then says what is true, no shortcut
        if key != nil, !toggleHotKey.isEnabled { settings.set("hud.toggleKey", 0) }
    }

    /// Hide every surface of the HUD, or bring them back as they were.
    ///
    /// Why it exists: the HUD lies over whatever the user works on, all day. For a screenshot, a call
    /// or a quiet moment they take it off the screen without quitting it. The surfaces are concealed,
    /// not closed ({@link NSWindow.setConcealed}): each keeps its desktop, its place and what it
    /// showed, the agent's commands keep working and the stop shortcut still stops. Only the same
    /// keys bring a hidden HUD back; `dw` tells the agent that it is hidden ({@link hiddenPath}).
    /// Called by {@link HUD.toggleChord} and {@link HUD.toggleHotKey}.
    func toggleHidden() {
        hudHidden.toggle()
        if hudHidden {
            let keys = Shortcut(packed: settings.value("hud.toggleKey"))?.display ?? ""
            try? keys.write(toFile: hiddenPath, atomically: true, encoding: .utf8)
            settingsCard.dismiss()
            effects.hide()
            // A message box left focused would take the user's typing unseen
            if mirror.isKeyWindow { input.returnFocus() }
            // The bar's polling no longer runs: a resize cursor it had set would stay
            if barEdgeHovered {
                barEdgeHovered = false
                NSCursor.arrow.set()
            }
        } else {
            try? FileManager.default.removeItem(atPath: hiddenPath)
        }
        // Every surface conceals or shows itself in its own refresh
        refresh()
        announce(hudHidden ? "HUD を隠しました" : "HUD を表示しました")
    }

    // MARK: stop and lifecycle

    /// Stop: the mod aborts the running turn; the flag file also stops the agent's shell helpers.
    /// Pressed again, it only clears the red state (sending a message clears it too).
    @objc func toggleStop() {
        if isStopOn() {
            setStop(false)
            appendLine(controlPath, ["cmd": "resume"])
        } else {
            setStop(true)
            appendLine(controlPath, ["cmd": "stop"])
            notePending("停止", route: .stop)
            // The next thing the person does is tell the agent what to do instead
            settings.set("mirror.visible", 1)
        }
        refresh()
    }

    func windowDidMove(_ notification: Notification) {
        if (notification.object as? NSPanel) === mirror { saveMirrorFrame(); return }
        guard (notification.object as? NSPanel) === panel else { return }
        let o = panel.frame.origin
        try? "\(o.x),\(o.y)".write(toFile: positionPath, atomically: true, encoding: .utf8)
    }

    /// Heartbeat for the mod and `dw`, plus the two ways to quit without the settings:
    /// a quit request file (`dw end`) and the owning agent session having exited.
    func housekeeping() {
        try? "\(Date().timeIntervalSince1970)".write(toFile: alivePath, atomically: true, encoding: .utf8)
        if exists(quitRequestPath) { quitHUD() }
        // Quit only after the owner has been gone for the whole grace period
        if ownerIsGone() {
            if ownerGoneSince == nil { ownerGoneSince = Date() }
            if let since = ownerGoneSince, Date().timeIntervalSince(since) > ownerGraceSeconds { quitHUD() }
        } else {
            ownerGoneSince = nil
        }
    }

    /// True when the latest known owner pid (from `owner.pid`, else the launch pid) no longer exists.
    func ownerIsGone() -> Bool {
        let text = ((try? String(contentsOfFile: ownerPidPath, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = pid_t(text) ?? launchOwnerPID
        guard pid > 0 else { return false }
        return kill(pid, 0) != 0 && errno == ESRCH
    }

    /// Settings → quit: the user's own decision to close the HUD, remembered so `dw` does not reopen it.
    @objc func quitByUser() {
        FileManager.default.createFile(atPath: closedByUserPath, contents: Data())
        hideCursorOverlay()
        quitHUD()
    }

    /// Take the agent's cursor overlay off the screen along with the HUD.
    ///
    /// Why it exists: the overlay (an arrow with a label) is drawn by a process of the agent-desktop
    /// session, which outlives the HUD: after the user quit the HUD it stayed on screen until the
    /// next `dw end`. The session itself stays open, so a `dw ad` that follows still works. Called by
    /// {@link HUD.quitByUser}; `dw start` and `dw end` end the session.
    func hideCursorOverlay() {
        let session = ((try? String(contentsOfFile: adSessionPath, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !session.isEmpty else { return }
        let task = Process()
        // Found through PATH, as `dw` finds it: the HUD inherits the environment of the shell that ran `dw`
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["agent-desktop", "cursor-overlay", "disable"]
        var environment = ProcessInfo.processInfo.environment
        environment["AGENT_DESKTOP_SESSION"] = session
        task.environment = environment
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    /// Quit the HUD. Removes every flag that could keep the agent waiting (typing, mirror suspend)
    /// so automation never blocks on a HUD that is no longer there.
    @objc func quitHUD() {
        for path in [typingPath, mirrorSuspendPath, quitRequestPath, pidPath, alivePath, hiddenPath] {
            try? FileManager.default.removeItem(atPath: path)
        }
        NSApp.terminate(nil)
    }

    /// Move HUD surfaces where `dw stage` asked: the explainer beside the app, the bar under it.
    /// Called on every refresh tick; a request is applied once and removed, and the new frames are
    /// remembered like a drag.
    func applyPlaceRequest() {
        guard let data = FileManager.default.contents(atPath: placeRequestPath) else { return }
        try? FileManager.default.removeItem(atPath: placeRequestPath)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        func numbers(_ key: String, _ count: Int) -> [CGFloat]? {
            guard let list = object[key] as? [NSNumber], list.count == count else { return nil }
            return list.map { CGFloat($0.doubleValue) }
        }
        if let v = numbers("bar", 3) {
            panel.setFrame(NSRect(x: v[0], y: v[1], width: max(480, v[2]), height: panel.frame.height), display: true)
            layoutBarForHeight()
            try? "\(panel.frame.width)".write(toFile: widthPath, atomically: true, encoding: .utf8)
        }
        if let v = numbers("explain", 4) { explainer.place(NSRect(x: v[0], y: v[1], width: v[2], height: v[3])) }
        if let v = numbers("mirror", 4) {
            mirror.setFrame(NSRect(x: v[0], y: v[1], width: v[2], height: v[3]), display: true)
            saveMirrorFrame()
        }
    }

    func refresh() {
        applyPlaceRequest()
        syncModState()
        let raw = (try? String(contentsOfFile: statusPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let m = mode
        // The symbol before the line says what kind of line it is; the agent's own narration has none
        let status: (symbol: String?, tint: NSColor, text: String)
        switch m {
        case "stopped": status = ("stop.circle.fill", .labelColor, "停止しました。ミラーの入力欄からメッセージを送ると再開します")
        case "typing": status = ("keyboard", .labelColor, "入力中のため、エージェントの画面操作は待機しています")
        // An input on its way to the session is said first; the agent's next line takes over when it reacts
        default: status = pendingStatus() ?? (nil, .labelColor, raw)
        }
        let line = (status.symbol ?? "") + "\u{1F}" + status.text
        if line != lastText || m != lastMode {
            // The first line after launch is not a change of mode
            let modeChanged = !lastMode.isEmpty && m != lastMode
            lastText = line
            lastMode = m
            stopButton.setStopped(m == "stopped")
            setStatusIcon(status.symbol, tint: status.tint)
            label.stringValue = status.text
            playChangeEffect(modeChanged: modeChanged, flashColor: m == "stopped" ? .systemRed : .systemOrange,
                             base: barColor(stopped: m == "stopped"))
            if modeChanged { announce(status.text) }
        }
        label.hole = notchHole()
        settingsButton.isActive = settingsCard.isOpen
        explainer.refresh()
        notePopup.refresh()
        applyActivity(currentActivity())
        updateMirrorVisibility()
        // Lit while the surface is before the user on this desktop. One that is switched on but lies
        // behind another app's window, or is open on another desktop, is not lit: a press brings it forward
        explainButton.isActive = explainer.isInSight
        mirrorButton.isActive = settings.isOn("mirror.visible") && !mirror.isOnAnotherSpace
        updateAsk()
        settingsCard.follow()
        panel.orderFrontRegardless()
        // Out of sight while the user has hidden the HUD
        panel.setConcealed(false)
    }
}
