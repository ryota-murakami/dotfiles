// Status HUD for desktop walkthroughs: shows what the agent is doing while it operates the Mac.
//
// - Status bar: translucent and click-through; drag the grip to move it, the right edge to resize.
//   Always-visible controls: mirror on/off, settings, and a one-click stop at the trailing end.
// - Mirror: the conversation of the agent session with a message box; close button in its header,
//   drag the header to move, any edge to resize.
// - Settings: one registry (Settings.swift) shown as a card above the bar (SettingsCard.swift).
// - Stop: the red button on the bar, or Control-Option-Command-Period from anywhere.
//
// The status bar never takes focus. Clicking the mirror makes the HUD the frontmost app so dictation
// tools can reach its message box; Enter or Esc gives focus back to the app that had it.
// Everything is driven by small files under <state-dir>, shared with `scripts/dw` and the mod.
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
let positionPath = "\(stateDir)/hud-position"
let widthPath = "\(stateDir)/hud-width"
/// Mirror frame chosen by dragging ("x,y,width,height" in screen points).
let mirrorFramePath = "\(stateDir)/mirror-frame"
/// `dw ask` / `dw wait-user` write {"id","text"[,"ok","no","icon"]} here; the answer goes to askAnswerPath ("<id> ok|no").
let askPath = "\(stateDir)/ask.json"
let askAnswerPath = "\(stateDir)/ask-answer"
/// Pid of the `dw` process currently waiting for the answer (absent or dead = nobody waiting).
let askWaiterPath = "\(stateDir)/ask-waiter"
let feedPath = "\(bridgeDir)/feed.jsonl"
let statePath = "\(bridgeDir)/state.json"
let inboxPath = "\(bridgeDir)/inbox.jsonl"
let controlPath = "\(bridgeDir)/control.jsonl"
/// Stop switch shared with the hud-bridge mod and the agent's shell helpers: "on" / "off"
let stopSwitchPath = "\(bridgeDir)/stop"
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

/// Panel that can take keyboard input (for the message box) without activating the app.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The app that was frontmost before the HUD, updated whenever another app activates.
var lastOtherApp: NSRunningApplication?
private var activationObserver: NSObjectProtocol?

/// Start remembering which app the person was using, so the message box can hand focus back.
/// Called once at launch.
func startActivationObserver() {
    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { note in
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastOtherApp = app
        }
    }
}

/// Message box that makes the HUD the frontmost app while focused, so dictation tools (Aqua Voice etc.)
/// that insert into the frontmost app's focused element reach it; the previous app gets focus back afterwards.
final class MessageField: NSTextField {
    var previousApp: NSRunningApplication?
    var onCancel: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, previousApp == nil, let last = lastOtherApp, !last.isTerminated { previousApp = last }
        return accepted
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// Give focus back to the app the person was using before they clicked the box.
    func returnFocus() {
        window?.makeFirstResponder(nil)
        if let app = previousApp, !app.isTerminated {
            // Cooperative activation (macOS 14+): yield to the app first, then ask it to come forward
            NSApp.yieldActivation(to: app)
            app.activate()
        }
        previousApp = nil
    }
}

/// Conversation view whose folded entries open on the first click, even when the mirror is not key.
final class FeedTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Drag handle: dragging it moves the window it sits in (the bar's grip, the mirror's header).
final class DragHandle: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

/// One edge or corner of the mirror: dragging it moves only that side, like a normal window border.
final class EdgeResizeHandle: NSView {
    struct Edges: OptionSet { let rawValue: Int
        static let left = Edges(rawValue: 1), right = Edges(rawValue: 2), bottom = Edges(rawValue: 4), top = Edges(rawValue: 8) }
    let edges: Edges
    var onResize: ((NSRect) -> Void)?
    private var start = NSPoint.zero
    private var startFrame = NSRect.zero
    init(_ edges: Edges) { self.edges = edges; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("not used") }
    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation
        startFrame = window?.frame ?? .zero
    }
    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - start.x, dy = p.y - start.y
        var r = startFrame
        if edges.contains(.left) { r.origin.x += dx; r.size.width -= dx }
        if edges.contains(.right) { r.size.width += dx }
        if edges.contains(.bottom) { r.origin.y += dy; r.size.height -= dy }
        if edges.contains(.top) { r.size.height += dy }
        onResize?(r)
    }
    override func resetCursorRects() {
        let horizontal = edges.contains(.left) || edges.contains(.right)
        let vertical = edges.contains(.top) || edges.contains(.bottom)
        addCursorRect(bounds, cursor: horizontal && vertical ? .crosshair : (horizontal ? .resizeLeftRight : .resizeUpDown))
    }
    override func draw(_ dirtyRect: NSRect) {
        // Only the bottom-right corner shows grip lines; the other handles are invisible borders
        guard edges == [.right, .bottom] else { return }
        NSColor.white.withAlphaComponent(0.55).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        for d in [4.0, 8.0, 12.0] {
            path.move(to: NSPoint(x: bounds.maxX - d, y: 2))
            path.line(to: NSPoint(x: bounds.maxX - 2, y: d))
        }
        path.stroke()
    }
}

/// Right edge of the bar: drag it to change the bar's width.
/// It draws nothing; the pointer turns into a left-right resize cursor over it.
final class ResizeHandle: NSView {
    var onResize: ((CGFloat) -> Void)?
    private var startX: CGFloat = 0
    private var startWidth: CGFloat = 0
    override func mouseDown(with event: NSEvent) {
        startX = NSEvent.mouseLocation.x
        startWidth = window?.frame.width ?? 0
    }
    override func mouseDragged(with event: NSEvent) { onResize?(startWidth + NSEvent.mouseLocation.x - startX) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
}

/// The HUD: status bar, conversation mirror and approval prompt.
///
/// Why it exists: it is the user's window into what the agent is doing, and their controls over it.
/// Created once at launch; timers poll the state files.
final class HUD: NSObject, NSWindowDelegate, NSTextViewDelegate {
    static let barHeight: CGFloat = 60
    let settingsCard = SettingsCard()

    // Status bar
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let box = NSView()
    let label = NSTextField(labelWithString: "")
    lazy var mirrorButton = IconButton(symbol: "bubble.left.and.text.bubble.right", label: "ミラーを表示／隠す", target: self, action: #selector(toggleMirror))
    lazy var settingsButton = IconButton(symbol: "slider.horizontal.3", label: "設定", target: self, action: #selector(toggleSettings))
    lazy var stopButton = StopButton(target: self, action: #selector(toggleStop))
    let divider = NSView()
    let resizeHandle = ResizeHandle()
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

    // Approval prompt (dw ask)
    let askPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let askLabel = NSTextField(wrappingLabelWithString: "")
    let askOK = NSButton(title: "OK", target: nil, action: nil)
    let askNo = NSButton(title: "キャンセル", target: nil, action: nil)
    var askID = ""
    var askStamp: Date?

    let stopHotKey = StopHotKey()

    var mode: String { isStopOn() ? "stopped" : (exists(typingPath) ? "typing" : "running") }

    override init() {
        super.init()
        buildStatusBar()
        buildMirror()
        buildAskPanel()
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

    // MARK: status bar

    func buildStatusBar() {
        // Not .screenSaver: windows at screen-saver level make macOS refuse Space switching (3-finger swipe)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.delegate = self

        box.wantsLayer = true
        box.layer?.cornerRadius = 14
        box.layer?.masksToBounds = true
        box.layer?.borderColor = accent.withAlphaComponent(0.55).cgColor
        box.layer?.borderWidth = 1
        applyBarColor()

        sweep.colors = [NSColor.clear.cgColor, NSColor.white.withAlphaComponent(0.16).cgColor, NSColor.clear.cgColor]
        sweep.startPoint = CGPoint(x: 0, y: 0.5)
        sweep.endPoint = CGPoint(x: 1, y: 0.5)
        sweep.opacity = 0
        box.layer?.addSublayer(sweep)

        label.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        label.textColor = .white
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 3
        label.shadow = shadow
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.wantsLayer = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        resizeHandle.onResize = { [weak self] w in self?.resizeBar(to: w) }
        gripLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        gripLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        gripLabel.translatesAutoresizingMaskIntoConstraints = false
        grip.addSubview(gripLabel)
        grip.toolTip = "ドラッグでバーを移動"
        resizeHandle.toolTip = "ドラッグでバーの幅を変更"
        // A hairline keeps the stop button visually apart from the everyday controls
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.35).cgColor

        for v in [grip, label, mirrorButton, settingsButton, divider, stopButton, resizeHandle] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(v)
        }
        NSLayoutConstraint.activate([
            grip.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            grip.topAnchor.constraint(equalTo: box.topAnchor),
            grip.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            grip.widthAnchor.constraint(equalToConstant: 34),
            gripLabel.centerXAnchor.constraint(equalTo: grip.centerXAnchor),
            gripLabel.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: grip.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: mirrorButton.leadingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            mirrorButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -6),
            mirrorButton.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            mirrorButton.widthAnchor.constraint(equalToConstant: 38),
            mirrorButton.heightAnchor.constraint(equalToConstant: 36),
            settingsButton.trailingAnchor.constraint(equalTo: divider.leadingAnchor, constant: -12),
            settingsButton.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 38),
            settingsButton.heightAnchor.constraint(equalToConstant: 36),
            divider.trailingAnchor.constraint(equalTo: stopButton.leadingAnchor, constant: -12),
            divider.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 26),
            stopButton.trailingAnchor.constraint(equalTo: resizeHandle.leadingAnchor, constant: -6),
            stopButton.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 88),
            stopButton.heightAnchor.constraint(equalToConstant: 36),
            resizeHandle.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            resizeHandle.topAnchor.constraint(equalTo: box.topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 12),
        ])
        panel.contentView = box
        placeStatusBar()
        panel.orderFrontRegardless()
    }

    /// Bar background: the chosen opacity, or red while stopped.
    func barColor(stopped: Bool) -> NSColor {
        let alpha = CGFloat(settings.value("bar.opacity"))
        return stopped
            ? NSColor(calibratedRed: 0.70, green: 0.08, blue: 0.10, alpha: max(0.66, alpha))
            : NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.08, alpha: alpha)
    }

    func applyBarColor() { box.layer?.backgroundColor = barColor(stopped: isStopOn()).cgColor }

    func placeStatusBar() {
        guard !positioned, let screen = NSScreen.main else { return }
        positioned = true
        let f = screen.frame
        var w: CGFloat = min(1240, f.width - 40)
        if let saved = try? String(contentsOfFile: widthPath, encoding: .utf8), let v = Double(saved.trimmingCharacters(in: .whitespacesAndNewlines)) {
            w = CGFloat(v)
        }
        var origin = NSPoint(x: f.midX - w / 2, y: f.minY + 22)
        if let saved = try? String(contentsOfFile: positionPath, encoding: .utf8) {
            let parts = saved.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if parts.count == 2 { origin = NSPoint(x: parts[0], y: parts[1]) }
        }
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: w, height: HUD.barHeight), display: true)
        sweep.frame = CGRect(x: -w * 0.35, y: 0, width: w * 0.35, height: HUD.barHeight)
    }

    /// Change the bar's width from the right-edge handle and remember it.
    func resizeBar(to width: CGFloat) {
        guard let screen = NSScreen.main else { return }
        var frame = panel.frame
        frame.size.width = min(max(480, width), screen.frame.maxX - frame.minX)
        panel.setFrame(frame, display: true)
        sweep.frame = CGRect(x: -frame.width * 0.35, y: 0, width: frame.width * 0.35, height: HUD.barHeight)
        try? "\(frame.width)".write(toFile: widthPath, atomically: true, encoding: .utf8)
    }

    /// Settings → bar → reset: back to the bottom centre at the default width.
    func resetBarFrame() {
        try? FileManager.default.removeItem(atPath: positionPath)
        try? FileManager.default.removeItem(atPath: widthPath)
        positioned = false
        placeStatusBar()
    }

    func windowDidMove(_ notification: Notification) {
        if (notification.object as? NSPanel) === mirror { saveMirrorFrame(); return }
        guard (notification.object as? NSPanel) === panel else { return }
        let o = panel.frame.origin
        try? "\(o.x),\(o.y)".write(toFile: positionPath, atomically: true, encoding: .utf8)
    }

    func screenRect(of view: NSView) -> NSRect { panel.convertToScreen(view.convert(view.bounds, to: nil)) }

    /// Accept mouse events only over the controls and the handles; everything else clicks through.
    func updateClickThrough() {
        let mouse = NSEvent.mouseLocation
        let hot = ([mirrorButton, settingsButton, stopButton, resizeHandle, grip] as [NSView]).map { screenRect(of: $0).insetBy(dx: -4, dy: -4) }
        mirrorButton.isHovered = screenRect(of: mirrorButton).contains(mouse)
        settingsButton.isHovered = screenRect(of: settingsButton).contains(mouse)
        stopButton.isHovered = screenRect(of: stopButton).contains(mouse)
        let dragging = NSEvent.pressedMouseButtons & 1 == 1 && !panel.ignoresMouseEvents
        panel.ignoresMouseEvents = !(hot.contains { $0.contains(mouse) } || dragging)
    }

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

    @objc func toggleMirror() { settings.toggle("mirror.visible") }
    @objc func closeMirror() { settings.set("mirror.visible", 0) }

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

    /// When the owning agent process was first seen missing (nil while it is alive).
    var ownerGoneSince: Date?

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

    func playChangeEffect(flashColor: NSColor, base: NSColor) {
        guard let layer = box.layer else { return }
        // The text slide-in is independent of the flash option
        let slide = CATransition()
        slide.type = .push
        slide.subtype = .fromBottom
        slide.duration = 0.35
        slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        label.layer?.add(slide, forKey: "slide")

        guard settings.isOn("bar.flash") else {
            layer.backgroundColor = base.cgColor
            return
        }
        let flash = CABasicAnimation(keyPath: "backgroundColor")
        flash.fromValue = flashColor.withAlphaComponent(0.38).cgColor
        flash.toValue = base.cgColor
        flash.duration = 0.6
        flash.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(flash, forKey: "flash")
        layer.backgroundColor = base.cgColor

        let border = CABasicAnimation(keyPath: "borderWidth")
        border.fromValue = 2
        border.toValue = 1
        border.duration = 0.6
        layer.add(border, forKey: "border")

        let w = box.bounds.width
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -w * 0.2
        move.toValue = w * 1.2
        move.duration = 0.8
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.8, 0.8, 0]
        fade.keyTimes = [0, 0.15, 0.8, 1]
        fade.duration = 0.8
        sweep.add(move, forKey: "move")
        sweep.add(fade, forKey: "fade")
    }

    /// The mod's state says busy/idle.
    func syncModState() {
        guard let data = FileManager.default.contents(atPath: statePath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            busyLabel.stringValue = "（Mod未接続）"
            return
        }
        let busy = obj["busy"] as? Bool ?? false
        busyLabel.stringValue = busy ? "● 作業中" : "○ 待機中（メッセージ待ち）"
        busyLabel.textColor = busy ? NSColor.systemGreen : NSColor.systemYellow
    }

    func refresh() {
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
        mirrorButton.isActive = settings.isOn("mirror.visible")
        settingsButton.isActive = settingsCard.isOpen
        updateMirrorVisibility()
        updateAsk()
        settingsCard.follow()
        panel.orderFrontRegardless()
    }

    // MARK: approval prompt

    /// A small clickable panel above the status bar for one-click answers asked by `dw ask` / `dw wait-user`.
    func buildAskPanel() {
        askPanel.level = .statusBar
        askPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        askPanel.isOpaque = false
        askPanel.backgroundColor = .clear
        askPanel.hasShadow = true
        askPanel.becomesKeyOnlyIfNeeded = true
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.96).cgColor
        root.layer?.borderColor = NSColor.systemOrange.cgColor
        root.layer?.borderWidth = 2
        askLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        askLabel.textColor = .white
        askLabel.maximumNumberOfLines = 4
        for (b, sel) in [(askOK, #selector(askOKTapped)), (askNo, #selector(askNoTapped))] {
            b.bezelStyle = .rounded
            b.controlSize = .large
            b.font = NSFont.systemFont(ofSize: 14, weight: .bold)
            b.target = self
            b.action = sel
        }
        askOK.bezelColor = .systemBlue
        for v in [askLabel, askOK, askNo] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            askLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            askLabel.trailingAnchor.constraint(equalTo: askNo.leadingAnchor, constant: -12),
            askLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            askOK.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            askOK.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            askOK.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
            askNo.trailingAnchor.constraint(equalTo: askOK.leadingAnchor, constant: -8),
            askNo.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            askNo.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
        ])
        askPanel.contentView = root
    }

    /// Show the pending question (if any) just above the status bar; hide it once answered or withdrawn.
    func updateAsk() {
        guard exists(askPath) else {
            if askPanel.isVisible { askPanel.orderOut(nil) }
            askID = ""; askStamp = nil
            return
        }
        let stamp = mtime(askPath)
        if stamp != askStamp {
            askStamp = stamp
            guard let data = FileManager.default.contents(atPath: askPath),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String, let text = obj["text"] as? String else { return }
            askID = id
            // dw ask uses OK / キャンセル; dw wait-user asks for a hand-off with its own labels
            askOK.title = (obj["ok"] as? String) ?? "OK"
            askNo.title = (obj["no"] as? String) ?? "キャンセル"
            askLabel.stringValue = ((obj["icon"] as? String) ?? "❓") + " " + text
            if settings.isOn("ask.sound") { NSSound(named: "Glass")?.play() }
        }
        guard !askID.isEmpty else { return }
        let bar = panel.frame
        let w = max(bar.width, 560)
        let h: CGFloat = 76
        var y = bar.maxY + 8
        if let screen = panel.screen ?? NSScreen.main, y + h > screen.visibleFrame.maxY { y = bar.minY - h - 8 }
        let frame = NSRect(x: bar.midX - w / 2, y: y, width: w, height: h)
        if askPanel.frame != frame { askPanel.setFrame(frame, display: true) }
        if !askPanel.isVisible { askPanel.orderFrontRegardless() }
    }

    func answerAsk(_ answer: String) {
        guard !askID.isEmpty else { return }
        try? "\(askID) \(answer)".write(toFile: askAnswerPath, atomically: true, encoding: .utf8)
        // Nobody is waiting (the agent's bounded wait ended and its turn is over): deliver the answer
        // as a message, the same way the mirror's message box does, so the click is never lost
        if !askWaiterAlive() {
            let label = answer == "ok" ? askOK.title : askNo.title
            let question = askLabel.stringValue
            appendLine(inboxPath, ["text": "[HUD] \(question) → 「\(label)」を押しました"])
            if isStopOn() { setStop(false) }
        }
        try? FileManager.default.removeItem(atPath: askPath)
        askPanel.orderOut(nil)
        askID = ""
    }

    /// True while a `dw ask` / `dw wait-user` process is polling for the answer (its pid is in ask-waiter).
    func askWaiterAlive() -> Bool {
        let text = ((try? String(contentsOfFile: askWaiterPath, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = pid_t(text), pid > 0 else { return false }
        return kill(pid, 0) == 0
    }

    @objc func askOKTapped() { answerAsk("ok") }
    @objc func askNoTapped() { answerAsk("no") }

    // MARK: mirror

    func buildMirror() {
        guard let screen = NSScreen.main else { return }
        mirror.setFrame(savedMirrorFrame(on: screen) ?? defaultMirrorFrame(on: screen), display: false)
        mirror.delegate = self
        mirror.level = .floating
        mirror.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        mirror.isOpaque = false
        mirror.backgroundColor = .clear
        mirror.hasShadow = true
        mirror.becomesKeyOnlyIfNeeded = false
        mirror.hidesOnDeactivate = false

        let root = mirrorRoot
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        applyMirrorOpacity()
        root.layer?.borderColor = accent.cgColor
        root.layer?.borderWidth = 2

        mirrorTitle.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        mirrorTitle.textColor = NSColor.white.withAlphaComponent(0.85)
        busyLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)

        textView.delegate = self
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        input.placeholderString = "エージェントへのメッセージ（Enterで送信。作業中でも次の手順の合間に届きます）"
        input.font = NSFont.systemFont(ofSize: 14)
        input.target = self
        input.action = #selector(sendMessage)
        input.onCancel = { [weak self] in self?.input.returnFocus() }
        sendButton.bezelStyle = .rounded
        sendButton.target = self
        sendButton.action = #selector(sendMessage)

        zoomLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        zoomLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        zoomLabel.alignment = .center
        updateZoomLabel()

        mirrorGrip.toolTip = "ドラッグでミラーを移動"
        // Invisible 6pt borders on every side and 14pt corners: drag any of them to resize
        for h in mirrorHandles { h.onResize = { [weak self] r in self?.resizeMirror(to: r) } }
        // The header labels sit inside the grip so a drag that starts on them moves the mirror too
        for v in [mirrorGrip, scroll, input, sendButton, zoomIn, zoomOut, zoomLabel, closeButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        for v in [mirrorTitle, busyLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            mirrorGrip.addSubview(v)
        }
        NSLayoutConstraint.activate([
            mirrorGrip.topAnchor.constraint(equalTo: root.topAnchor),
            mirrorGrip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            mirrorGrip.trailingAnchor.constraint(equalTo: zoomOut.leadingAnchor, constant: -6),
            mirrorGrip.heightAnchor.constraint(equalToConstant: 32),
            mirrorTitle.centerYAnchor.constraint(equalTo: mirrorGrip.centerYAnchor),
            mirrorTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            busyLabel.centerYAnchor.constraint(equalTo: mirrorTitle.centerYAnchor),
            busyLabel.leadingAnchor.constraint(equalTo: mirrorTitle.trailingAnchor, constant: 12),

            closeButton.centerYAnchor.constraint(equalTo: mirrorGrip.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 22),
            zoomIn.centerYAnchor.constraint(equalTo: mirrorGrip.centerYAnchor),
            zoomIn.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),
            zoomIn.widthAnchor.constraint(equalToConstant: 24),
            zoomIn.heightAnchor.constraint(equalToConstant: 22),
            zoomLabel.centerYAnchor.constraint(equalTo: mirrorGrip.centerYAnchor),
            zoomLabel.trailingAnchor.constraint(equalTo: zoomIn.leadingAnchor, constant: -2),
            zoomLabel.widthAnchor.constraint(equalToConstant: 42),
            zoomOut.centerYAnchor.constraint(equalTo: mirrorGrip.centerYAnchor),
            zoomOut.trailingAnchor.constraint(equalTo: zoomLabel.leadingAnchor, constant: -2),
            zoomOut.widthAnchor.constraint(equalToConstant: 24),
            zoomOut.heightAnchor.constraint(equalToConstant: 22),

            scroll.topAnchor.constraint(equalTo: mirrorGrip.bottomAnchor, constant: 2),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
            scroll.bottomAnchor.constraint(equalTo: input.topAnchor, constant: -6),
            input.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            input.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -6),
            input.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            input.heightAnchor.constraint(equalToConstant: 28),
            sendButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            sendButton.centerYAnchor.constraint(equalTo: input.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 70),
        ])
        layoutMirrorHandles(in: root)
        mirror.contentView = root
    }

    /// Pin the resize handles to the mirror's borders; added last so they sit above the content.
    func layoutMirrorHandles(in root: NSView) {
        let edge: CGFloat = 6, corner: CGFloat = 14
        for h in mirrorHandles {
            h.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(h)
            let e = h.edges
            var c: [NSLayoutConstraint] = []
            let isCorner = (e.contains(.left) || e.contains(.right)) && (e.contains(.top) || e.contains(.bottom))
            if e.contains(.left) { c.append(h.leadingAnchor.constraint(equalTo: root.leadingAnchor)) }
            if e.contains(.right) { c.append(h.trailingAnchor.constraint(equalTo: root.trailingAnchor)) }
            if e.contains(.top) { c.append(h.topAnchor.constraint(equalTo: root.topAnchor)) }
            if e.contains(.bottom) { c.append(h.bottomAnchor.constraint(equalTo: root.bottomAnchor)) }
            if isCorner {
                c += [h.widthAnchor.constraint(equalToConstant: corner), h.heightAnchor.constraint(equalToConstant: corner)]
            } else if e.contains(.left) || e.contains(.right) {
                c += [h.widthAnchor.constraint(equalToConstant: edge), h.topAnchor.constraint(equalTo: root.topAnchor, constant: corner),
                      h.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -corner)]
            } else {
                c += [h.heightAnchor.constraint(equalToConstant: edge), h.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: corner),
                      h.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -corner)]
            }
            NSLayoutConstraint.activate(c)
        }
    }

    /// Top-right quarter below the menu bar: the mirror's place until the user moves it.
    func defaultMirrorFrame(on screen: NSScreen) -> NSRect {
        let f = screen.frame
        let w = f.width / 2, h = (f.height - 33) / 2
        return NSRect(x: f.maxX - w, y: f.maxY - 33 - h, width: w, height: h)
    }

    /// The frame saved by the last drag, if it still fits on a connected screen.
    func savedMirrorFrame(on screen: NSScreen) -> NSRect? {
        guard let s = try? String(contentsOfFile: mirrorFramePath, encoding: .utf8) else { return nil }
        let v = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard v.count == 4 else { return nil }
        let r = NSRect(x: v[0], y: v[1], width: v[2], height: v[3])
        // A display that is no longer attached would leave the mirror unreachable
        return NSScreen.screens.contains { $0.frame.intersects(r) } ? r : nil
    }

    func saveMirrorFrame() {
        let r = mirror.frame
        try? "\(r.minX),\(r.minY),\(r.width),\(r.height)".write(toFile: mirrorFramePath, atomically: true, encoding: .utf8)
    }

    /// Edge or corner drag: apply the dragged frame, keeping the side opposite the drag in place,
    /// with a usable minimum size and inside the visible screen area.
    func resizeMirror(to proposed: NSRect) {
        var r = proposed
        let old = mirror.frame
        if r.width < 360 { if r.minX != old.minX { r.origin.x = old.maxX - 360 }; r.size.width = 360 }
        if r.height < 220 { if r.minY != old.minY { r.origin.y = old.maxY - 220 }; r.size.height = 220 }
        if let f = (mirror.screen ?? NSScreen.main)?.visibleFrame { r = r.intersection(f).isNull ? old : r.intersection(f) }
        mirror.setFrame(r, display: true)
        saveMirrorFrame()
    }

    @objc func resetMirrorFrame() {
        guard let screen = NSScreen.main else { return }
        try? FileManager.default.removeItem(atPath: mirrorFramePath)
        mirror.setFrame(defaultMirrorFrame(on: screen), display: true)
    }

    func applyMirrorOpacity() {
        mirrorRoot.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: CGFloat(settings.value("mirror.opacity"))).cgColor
    }

    /// Show the mirror unless it is switched off, suspended for a click, or the real chat window is in front.
    func updateMirrorVisibility() {
        let off = !settings.isOn("mirror.visible") || exists(mirrorSuspendPath)
        var claudeInFront = false
        if claudeWindowID != 0,
           let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            let normal = list.first { ($0[kCGWindowLayer as String] as? Int) == 0 }
            claudeInFront = (normal?[kCGWindowNumber as String] as? Int).map { CGWindowID($0) == claudeWindowID } ?? false
        }
        if off || claudeInFront {
            if mirror.isVisible { mirror.orderOut(nil) }
        } else if !mirror.isVisible {
            mirror.orderFrontRegardless()
        }
    }

    /// Re-render the conversation when the mod rewrote the feed (or an option changed).
    /// `keepScroll` keeps the reader's position (used when an entry is folded or unfolded).
    func reloadFeed(force: Bool, keepScroll: Bool = false) {
        let stamp = mtime(feedPath)
        guard force || stamp != feedStamp else { return }
        feedStamp = stamp
        guard let data = FileManager.default.contents(atPath: feedPath), let text = String(data: data, encoding: .utf8) else { return }
        let size = 13 * zoom
        let fold = settings.isOn("mirror.fold")
        let out = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 6 * zoom
        para.lineBreakMode = .byWordWrapping
        for line in text.split(separator: "\n") {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let role = obj["role"] as? String, let body = obj["text"] as? String else { continue }
            let (tag, tagColor, bodyColor, bodyFont): (String, NSColor, NSColor, NSFont) = {
                switch role {
                case "you": return ("あなた ", NSColor.systemGreen, NSColor.white, NSFont.systemFont(ofSize: size, weight: .semibold))
                case "agent": return ("Claude ", accent, NSColor(calibratedWhite: 0.93, alpha: 1), NSFont.systemFont(ofSize: size))
                case "tool": return ("  ▸ ", NSColor.systemGray, NSColor.systemGray, NSFont.monospacedSystemFont(ofSize: size * 0.85, weight: .regular))
                default: return ("HUD ", NSColor.systemOrange, NSColor.systemOrange, NSFont.systemFont(ofSize: size, weight: .semibold))
                }
            }()
            let lines = body.components(separatedBy: "\n")
            let isLong = role == "tool" && (lines.count > 3 || body.count > 280)
            // Long tool entries behave like <details>: a one-line summary that opens on click
            if isLong && fold {
                let key = "\((obj["ts"] as? NSNumber)?.stringValue ?? "")-\(body.hashValue)"
                let open = expandedEntries.contains(key)
                let link = URL(string: "dwfold:" + (key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key))!
                let marker = open ? "  ▼ " : "  ▶ "
                let summary = open ? body : (lines.first ?? "") + "  … (\(lines.count)行・\(body.count)文字)"
                out.append(NSAttributedString(string: marker, attributes: [.font: NSFont.systemFont(ofSize: size * 0.85, weight: .bold), .foregroundColor: accent, .link: link, .paragraphStyle: para]))
                out.append(NSAttributedString(string: summary + "\n", attributes: [.font: bodyFont, .foregroundColor: bodyColor, .paragraphStyle: para, .link: link]))
                continue
            }
            out.append(NSAttributedString(string: tag, attributes: [.font: NSFont.systemFont(ofSize: size * 0.85, weight: .bold), .foregroundColor: tagColor, .paragraphStyle: para]))
            out.append(NSAttributedString(string: body + "\n", attributes: [.font: bodyFont, .foregroundColor: bodyColor, .paragraphStyle: para]))
        }
        // Links look like the surrounding text, not blue underlined web links
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        let visible = scroll.contentView.bounds.origin
        textView.textStorage?.setAttributedString(out)
        if keepScroll { scroll.contentView.scroll(to: visible); scroll.reflectScrolledClipView(scroll.contentView) }
        else { textView.scrollToEndOfDocument(nil) }
    }

    /// Click on a folded entry: open or close it, keeping the scroll position.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL, url.scheme == "dwfold" else { return false }
        let key = url.absoluteString.dropFirst("dwfold:".count).removingPercentEncoding ?? ""
        if expandedEntries.contains(key) { expandedEntries.remove(key) } else { expandedEntries.insert(key) }
        reloadFeed(force: true, keepScroll: true)
        return true
    }

    /// While the message box is being edited (focused, or holding a draft), keep the agent's GUI steps waiting.
    func updateTypingFlag() {
        let editing = mirror.isKeyWindow && mirror.firstResponder is NSTextView && (mirror.firstResponder as? NSTextView)?.delegate === input
        let typing = editing || !input.stringValue.isEmpty
        if typing && !exists(typingPath) {
            FileManager.default.createFile(atPath: typingPath, contents: Data())
        } else if !typing && exists(typingPath) {
            try? FileManager.default.removeItem(atPath: typingPath)
        }
    }

    func updateZoomLabel() { zoomLabel.stringValue = percentText(Double(zoom)) }

    @objc func zoomInTapped() { settings.set("mirror.zoom", Double(zoom) + 0.1) }
    @objc func zoomOutTapped() { settings.set("mirror.zoom", Double(zoom) - 0.1) }

    /// Hand the typed message to the mod through the inbox file; it reaches the session without any GUI step.
    @objc func sendMessage() {
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        appendLine(inboxPath, ["text": text])
        input.stringValue = ""
        input.returnFocus()
        // Speaking lifts a stop, as typing in Claude Code would
        if isStopOn() { setStop(false) }
    }
}

/// A main menu with the standard Edit items: their key equivalents make paste/copy/select-all work in the box.
func installEditMenu() {
    let main = NSMenu()
    let appItem = NSMenuItem()
    main.addItem(appItem)
    appItem.submenu = NSMenu(title: "HUD")
    let editItem = NSMenuItem()
    main.addItem(editItem)
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    NSApp.mainMenu = main
}
