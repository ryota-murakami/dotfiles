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
//
// The status bar never takes focus. Clicking the mirror makes the HUD the frontmost app so dictation
// tools can reach its message box; Enter or Esc gives focus back to the app that had it.
// Everything is driven by small files under <state-dir>, shared with `scripts/dw` and the mod.
//
// Files: this one holds the paths shared with `scripts/dw` and the mod, and the HUD class with its
// stored views, launch, settings, stop and lifecycle. Each surface adds its methods in a file of
// its own: Bar.swift (status bar), Mirror.swift (conversation and message box), AskPrompt.swift
// (one-click answers), SettingsCard.swift (settings UI over Settings.swift), Controls.swift
// (shared controls and the stop shortcut).
import AppKit
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
/// Rewritten every second: the mod and `dw` ignore the typing flag once this heartbeat is stale.
let alivePath = "\(stateDir)/hud.alive"
let pidPath = "\(stateDir)/hud.pid"

let accent = NSColor(calibratedRed: 0.26, green: 0.60, blue: 1.0, alpha: 1)

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

/// Drag handle: dragging it moves the window it sits in (the bar's grip, the mirror's header).
final class DragHandle: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
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
    lazy var stopButton = StopButton(target: self, action: #selector(toggleStop))
    /// Shown in the stop button's place while the walkthrough is not acting (see {@link Activity}).
    let stateBadge = StateBadge()
    /// Width of the stop button's slot: the badge is wider than the button.
    var stopWidth: NSLayoutConstraint?
    var lastActivity: Activity?
    /// `busy` of the bridge's state file: true while a turn runs, nil without a bridge.
    var modBusy: Bool?
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
    let sweep = CAGradientLayer()
    var lastText = ""
    var lastMode = ""
    var positioned = false

    // Mirror
    // Not .nonactivatingPanel: clicking the mirror must make the HUD the frontmost app, or dictation tools
    // (which insert into the frontmost app's focused element) cannot reach the message box
    let mirror = KeyablePanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    let mirrorTitle = NSTextField(labelWithString: "⠿ Claude Code")
    let mirrorRoot = NSView()
    let mirrorGrip = DragHandle()
    lazy var closeButton = IconButton(symbol: "xmark", label: "ミラーを閉じる", pointSize: 11, target: self, action: #selector(closeMirror))
    let mirrorHandles: [EdgeResizeHandle] = [
        EdgeResizeHandle([.left]), EdgeResizeHandle([.right]), EdgeResizeHandle([.top]), EdgeResizeHandle([.bottom]),
        EdgeResizeHandle([.left, .top]), EdgeResizeHandle([.right, .top]), EdgeResizeHandle([.left, .bottom]), EdgeResizeHandle([.right, .bottom]),
    ]
    let busyLabel = NSTextField(labelWithString: "")
    let scroll = NSScrollView()
    let textView = FeedTextView()
    let input = MessageField()
    let sendButton = NSButton(title: "送信", target: nil, action: nil)
    lazy var zoomIn = IconButton(symbol: "plus", label: "文字を大きく", pointSize: 11, target: self, action: #selector(zoomInTapped))
    lazy var zoomOut = IconButton(symbol: "minus", label: "文字を小さく", pointSize: 11, target: self, action: #selector(zoomOutTapped))
    let zoomLabel = NSTextField(labelWithString: "")
    var feedStamp: Date?
    /// Keys of long tool entries the user expanded (like an open <details>), kept while the HUD runs.
    var expandedEntries = Set<String>()
    var zoom: CGFloat { CGFloat(settings.value("mirror.zoom")) }

    // Explainer (dw explain): long-form pages, see Explainer.swift
    let explainer = Explainer()
    // Note popup (dw note): a short explanation beside what it explains, see Note.swift
    let notePopup = NotePopup()

    // Approval prompt (dw ask)
    let askPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let askLabel = NSTextField(wrappingLabelWithString: "")
    let askOK = NSButton(title: "OK", target: nil, action: nil)
    let askNo = NSButton(title: "キャンセル", target: nil, action: nil)
    /// Feedback buttons of the current question (`--button`): a press sends its label to the agent and leaves the question open.
    let askExtras = NSStackView()
    var askExtraLabels: [String] = []
    /// The card's background: dragging it anywhere outside the buttons moves the prompt.
    let askGrip = DragHandle()
    let askGripMark = NSTextField(labelWithString: "⠿")
    /// Size the card needs for the current question (see `layoutAsk`).
    var askSize = NSSize(width: 420, height: 58)
    var askID = ""
    var askStamp: Date?
    /// Origin the HUD last gave the prompt: a different origin later means the user dragged it.
    var askPlacedOrigin: NSPoint?
    /// True while a prompt parked off-screen is shown in full because the pointer is on it.
    var askRevealed = false
    /// False from the moment the user drags the prompt until the pointer has left it once.
    var askRevealArmed = true

    let stopHotKey = StopHotKey()

    /// When the owning agent process was first seen missing (nil while it is alive).
    var ownerGoneSince: Date?

    var mode: String { isStopOn() ? "stopped" : (exists(typingPath) ? "typing" : "running") }

    override init() {
        super.init()
        buildStatusBar()
        buildMirror()
        buildAskPanel()
        explainer.attach()
        notePopup.attach()
        settings.actions["explain.reset"] = { [weak self] in self?.explainer.resetFrame() }
        settings.actions["ask.reset"] = { [weak self] in self?.resetAskPosition() }
        settings.actions["mirror.reset"] = { [weak self] in self?.resetMirrorFrame() }
        settings.actions["bar.reset"] = { [weak self] in self?.resetBarFrame() }
        settings.actions["hud.quit"] = { [weak self] in self?.quitByUser() }
        NotificationCenter.default.addObserver(forName: SettingsStore.changed, object: settings, queue: .main) { [weak self] note in
            if let id = note.userInfo?["id"] as? String { self?.applySetting(id) }
        }
        // The shortcut only ever stops: pressing it again must not clear a stop by accident
        StopHotKey.onPress = { [weak self] in
            if !isStopOn() { self?.toggleStop() }
        }
        stopHotKey.setEnabled(settings.isOn("stop.hotkey"))
        // "Open" is a passing state, so the settings button lights up more quietly than the mirror toggle
        settingsButton.activeColor = NSColor.white.withAlphaComponent(0.34)
        settingsCard.attach(to: self)
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.refresh() }
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in self?.updateClickThrough() }
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
        case "explain.zoom": explainer.applyZoom()
        case "mirror.visible": updateMirrorVisibility()
        case "mirror.fold": reloadFeed(force: true, keepScroll: true)
        case "mirror.zoom":
            updateZoomLabel()
            reloadFeed(force: true, keepScroll: true)
        case "mirror.opacity": applyMirrorOpacity()
        case "bar.opacity": applyBarColor()
        case "stop.hotkey": stopHotKey.setEnabled(settings.isOn(id))
        default: break
        }
    }

    @objc func toggleSettings() {
        settingsCard.toggle()
        settingsButton.isActive = settingsCard.isOpen
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
        quitHUD()
    }

    /// Quit the HUD. Removes every flag that could keep the agent waiting (typing, mirror suspend)
    /// so automation never blocks on a HUD that is no longer there.
    @objc func quitHUD() {
        for path in [typingPath, mirrorSuspendPath, quitRequestPath, pidPath, alivePath] {
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
        let text: String
        switch m {
        case "stopped": text = "⏹ 停止しました。ミラーの入力欄からメッセージを送ると再開します"
        case "typing": text = "✍️ 入力中のため、エージェントの画面操作は待機しています"
        default: text = "🤖 " + raw
        }
        if text != lastText || m != lastMode {
            let modeChanged = m != lastMode
            lastText = text
            lastMode = m
            stopButton.setStopped(m == "stopped")
            label.stringValue = text
            playChangeEffect(flashColor: modeChanged ? (m == "stopped" ? NSColor.systemRed : NSColor.systemOrange) : accent,
                             base: barColor(stopped: m == "stopped"))
        }
        label.hole = notchHole()
        explainButton.isActive = settings.isOn("explain.visible")
        mirrorButton.isActive = settings.isOn("mirror.visible")
        settingsButton.isActive = settingsCard.isOpen
        explainer.refresh()
        notePopup.refresh()
        applyActivity(currentActivity())
        updateMirrorVisibility()
        updateAsk()
        settingsCard.follow()
        panel.orderFrontRegardless()
    }
}
