// Status HUD for desktop walkthroughs: shows what the agent is doing while it operates the Mac.
//
// Usage: StatusHUD <state-dir>   (env: DW_CLAUDE_WINDOW = CGWindowID of the chat terminal, DW_OWNER_PID)
//
// - Status bar: translucent, click-through, shows the current step; drag ⠿ to move, ‖ to resize
// - ☰ menu: ⏸ takeover (pause GUI automation), ⏹ stop (abort the turn), 🪞 mirror, ✨ flash, ✕ quit
// - 🪞 Mirror: conversation view (top-right quarter until dragged by its header; resized from the
//   bottom-right corner; background opacity in the ☰ menu) rendered from the hud-bridge mod's feed, with a
//   message box whose text the mod delivers into the session (no Space switch, no typing into a terminal)
//
// The status bar never takes focus. Clicking the mirror makes the HUD the frontmost app so dictation
// tools can reach its message box; Enter or Esc gives focus back to the app that had it.
// Everything is driven by small files under <state-dir>, shared with `scripts/dw` and the mod.
import AppKit
import QuartzCore

/// State folder shared with the `dw` script and the hud-bridge mod: argument 1, else the default.
let stateDir: String = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "\(NSHomeDirectory())/.local/state/desktop-walkthrough"
let bridgeDir = "\(stateDir)/bridge"
let statusPath = "\(stateDir)/status.txt"
let pausePath = "\(stateDir)/paused"
let mirrorOffPath = "\(stateDir)/mirror-off"
let mirrorSuspendPath = "\(stateDir)/mirror-suspend"
let positionPath = "\(stateDir)/hud-position"
let widthPath = "\(stateDir)/hud-width"
/// Present = flash / border / sweep effects are off (the text slide-in always plays)
let flashOffPath = "\(stateDir)/hud-flash-off"
let zoomPath = "\(stateDir)/mirror-zoom"
/// Mirror frame chosen by dragging ("x,y,width,height" in screen points) and background opacity (0.2–1.0).
let mirrorFramePath = "\(stateDir)/mirror-frame"
let mirrorOpacityPath = "\(stateDir)/mirror-opacity"
/// `dw ask` writes {"id","text"} here; the HUD shows it with OK / キャンセル and answers in askAnswerPath ("<id> ok|no").
let askPath = "\(stateDir)/ask.json"
let askAnswerPath = "\(stateDir)/ask-answer"
let feedPath = "\(bridgeDir)/feed.jsonl"
let statePath = "\(bridgeDir)/state.json"
let inboxPath = "\(bridgeDir)/inbox.jsonl"
let controlPath = "\(bridgeDir)/control.jsonl"
/// ⏹ switch shared with the hud-bridge mod and the agent's shell helpers: "on" / "off"
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
/// Written only when the user quits from the ☰ menu, so `dw` does not reopen a HUD the user closed.
let closedByUserPath = "\(stateDir)/hud-closed-by-user"
/// `dw end` creates this file to ask the HUD to quit through the same path as the menu item.
let quitRequestPath = "\(stateDir)/quit"
/// Rewritten every second: the mod and `dw` ignore pause/typing flags once this heartbeat is stale.
let alivePath = "\(stateDir)/hud.alive"
let pidPath = "\(stateDir)/hud.pid"

let accent = NSColor(calibratedRed: 0.26, green: 0.60, blue: 1.0, alpha: 1)
let baseColor = NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.08, alpha: 0.42)
let pausedColor = NSColor(calibratedRed: 0.75, green: 0.35, blue: 0.0, alpha: 0.62)
let stoppedColor = NSColor(calibratedRed: 0.70, green: 0.08, blue: 0.10, alpha: 0.66)

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
let activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
) { note in
    if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
       app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
        lastOtherApp = app
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

/// Drag handle for the status bar.
final class GripView: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

/// Mirror header: drag it to move the mirror (the labels inside it are part of the handle).
final class MirrorGrip: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

/// Bottom-right corner of the mirror: drag to resize it while its top-left corner stays put.
final class CornerResizeHandle: NSView {
    var onResize: ((NSSize) -> Void)?
    private var start = NSPoint.zero
    private var startSize = NSSize.zero
    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation
        startSize = window?.frame.size ?? .zero
    }
    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        // Screen y grows upward, so dragging down (smaller y) makes the mirror taller
        onResize?(NSSize(width: startSize.width + p.x - start.x, height: startSize.height + start.y - p.y))
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
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

/// Right-edge handle: drag to change the HUD's width.
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
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.45).setFill()
        for dx in [3.0, 7.0] { NSBezierPath(roundedRect: NSRect(x: dx, y: bounds.midY - 10, width: 2, height: 20), xRadius: 1, yRadius: 1).fill() }
    }
}

final class HUD: NSObject, NSWindowDelegate {
    // Status bar
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let box = NSView()
    let label = NSTextField(labelWithString: "")
    let menuButton = NSButton(title: "☰", target: nil, action: nil)
    let resizeHandle = ResizeHandle()
    let grip = GripView()
    let gripLabel = NSTextField(labelWithString: "⠿")
    let sweep = CAGradientLayer()
    var lastText = ""
    var lastMode = ""
    var positioned = false

    // Mirror
    // Not .nonactivatingPanel: clicking the mirror must make the HUD the frontmost app, or dictation tools
    // (which insert into the frontmost app's focused element) cannot reach the message box
    let mirror = KeyablePanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    let mirrorHeader = NSTextField(labelWithString: "⠿ 🪞 Claude Code")
    let mirrorRoot = NSView()
    let mirrorGrip = MirrorGrip()
    let mirrorResize = CornerResizeHandle()
    var mirrorOpacity: CGFloat = {
        if let s = try? String(contentsOfFile: mirrorOpacityPath, encoding: .utf8), let v = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return CGFloat(v) }
        return 0.95
    }()
    let busyLabel = NSTextField(labelWithString: "")
    let scroll = NSScrollView()
    let textView = NSTextView()
    let input = MessageField()
    let sendButton = NSButton(title: "送信", target: nil, action: nil)
    let zoomIn = NSButton(title: "＋", target: nil, action: nil)
    let zoomOut = NSButton(title: "－", target: nil, action: nil)
    let zoomLabel = NSTextField(labelWithString: "")
    var feedStamp: Date?
    var zoom: CGFloat = {
        if let s = try? String(contentsOfFile: zoomPath, encoding: .utf8), let v = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return CGFloat(v) }
        return 1.0
    }()

    // Approval prompt (dw ask)
    let askPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let askLabel = NSTextField(wrappingLabelWithString: "")
    let askOK = NSButton(title: "OK", target: nil, action: nil)
    let askNo = NSButton(title: "キャンセル", target: nil, action: nil)
    var askID = ""
    var askStamp: Date?

    var mode: String { isStopOn() ? "stopped" : (exists(pausePath) ? "paused" : (exists(typingPath) ? "typing" : "running")) }

    override init() {
        super.init()
        buildStatusBar()
        buildMirror()
        buildAskPanel()
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.refresh() }
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateClickThrough() }
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.reloadFeed(force: false) }
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.updateTypingFlag() }
        try? FileManager.default.createDirectory(atPath: bridgeDir, withIntermediateDirectories: true)
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(toFile: pidPath, atomically: true, encoding: .utf8)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.housekeeping() }
        housekeeping()
        refresh()
        reloadFeed(force: true)
    }

    // MARK: status bar

    func styleButton(_ b: NSButton, _ action: Selector) {
        b.bezelStyle = .rounded
        b.controlSize = .large
        b.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        b.target = self
        b.action = action
        b.translatesAutoresizingMaskIntoConstraints = false
    }

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
        box.layer?.backgroundColor = baseColor.cgColor
        box.layer?.borderColor = accent.withAlphaComponent(0.55).cgColor
        box.layer?.borderWidth = 1

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
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Pause / stop / mirror live in the ☰ menu so the status text gets the full width
        styleButton(menuButton, #selector(showMenu))
        menuButton.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        menuButton.toolTip = "一時停止・停止・ミラー表示"
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.onResize = { [weak self] w in self?.resizeBar(to: w) }

        grip.translatesAutoresizingMaskIntoConstraints = false
        gripLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        gripLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        gripLabel.translatesAutoresizingMaskIntoConstraints = false
        grip.addSubview(gripLabel)

        for v in [grip, label, menuButton, resizeHandle] as [NSView] { box.addSubview(v) }
        NSLayoutConstraint.activate([
            grip.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            grip.topAnchor.constraint(equalTo: box.topAnchor),
            grip.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            grip.widthAnchor.constraint(equalToConstant: 34),
            gripLabel.centerXAnchor.constraint(equalTo: grip.centerXAnchor),
            gripLabel.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: grip.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            menuButton.trailingAnchor.constraint(equalTo: resizeHandle.leadingAnchor, constant: -2),
            menuButton.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            resizeHandle.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            resizeHandle.topAnchor.constraint(equalTo: box.topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 12),
        ])
        panel.contentView = box
        placeStatusBar()
        panel.orderFrontRegardless()
    }

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
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: w, height: 60), display: true)
        sweep.frame = CGRect(x: -w * 0.35, y: 0, width: w * 0.35, height: 60)
    }

    /// Change the bar's width from the right-edge handle and remember it.
    func resizeBar(to width: CGFloat) {
        guard let screen = NSScreen.main else { return }
        var frame = panel.frame
        frame.size.width = min(max(360, width), screen.frame.maxX - frame.minX)
        panel.setFrame(frame, display: true)
        sweep.frame = CGRect(x: -frame.width * 0.35, y: 0, width: frame.width * 0.35, height: 60)
        try? "\(frame.width)".write(toFile: widthPath, atomically: true, encoding: .utf8)
    }

    /// ☰: the controls that used to sit on the bar.
    @objc func showMenu() {
        let menu = NSMenu()
        let m = mode
        let items: [(String, Selector)] = [
            (m == "paused" ? "▶ 再開（エージェントに戻す）" : "⏸ 一時停止（操作を引き取る）", #selector(togglePause)),
            (m == "stopped" ? "⏹ 停止を解除" : "⏹ 停止して話しかける", #selector(toggleStop)),
            (exists(mirrorOffPath) ? "🪞 Claudeミラーを表示" : "🪞 Claudeミラーを隠す", #selector(toggleMirror)),
        ]
        for (title, action) in items {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        let opacityItem = menu.addItem(withTitle: "🌫 ミラー背景の不透明度", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for percent in [100, 95, 90, 75, 60, 45, 30] {
            let item = opacityMenu.addItem(withTitle: "\(percent)%", action: #selector(chooseMirrorOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = percent
            item.state = Int((mirrorOpacity * 100).rounded()) == percent ? .on : .off
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(withTitle: "↺ ミラーの位置とサイズを初期状態に戻す", action: #selector(resetMirrorFrame), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let flashItem = menu.addItem(withTitle: "✨ 更新時のフラッシュ効果", action: #selector(toggleFlash), keyEquivalent: "")
        flashItem.target = self
        flashItem.state = exists(flashOffPath) ? .off : .on
        menu.addItem(.separator())
        menu.addItem(withTitle: "✕ HUDを終了", action: #selector(quitByUser), keyEquivalent: "").target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: menuButton.bounds.height + 4), in: menuButton)
    }

    func windowDidMove(_ notification: Notification) {
        if (notification.object as? NSPanel) === mirror { saveMirrorFrame(); return }
        guard (notification.object as? NSPanel) === panel else { return }
        let o = panel.frame.origin
        try? "\(o.x),\(o.y)".write(toFile: positionPath, atomically: true, encoding: .utf8)
    }

    /// Accept mouse events only over the buttons and the grip; everything else clicks through.
    func updateClickThrough() {
        let mouse = NSEvent.mouseLocation
        let hot = [menuButton, resizeHandle, grip].map {
            panel.convertToScreen($0.convert($0.bounds, to: nil)).insetBy(dx: -4, dy: -4)
        }
        let dragging = NSEvent.pressedMouseButtons & 1 == 1 && !panel.ignoresMouseEvents
        panel.ignoresMouseEvents = !(hot.contains { $0.contains(mouse) } || dragging)
    }

    @objc func togglePause() {
        if exists(pausePath) {
            try? FileManager.default.removeItem(atPath: pausePath)
        } else {
            FileManager.default.createFile(atPath: pausePath, contents: Data())
        }
        refresh()
    }

    /// ⏹: the mod aborts the running turn; the flag file also stops the agent's shell helpers.
    @objc func toggleStop() {
        if isStopOn() {
            setStop(false)
            appendLine(controlPath, ["cmd": "resume"])
        } else {
            setStop(true)
            try? FileManager.default.removeItem(atPath: pausePath)
            appendLine(controlPath, ["cmd": "stop"])
            try? FileManager.default.removeItem(atPath: mirrorOffPath)
        }
        refresh()
    }

    /// Heartbeat for the mod and `dw`, plus the two ways to quit without the menu:
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

    /// ☰ → ✕: the user's own decision to close the HUD, remembered so `dw` does not reopen it.
    @objc func quitByUser() {
        FileManager.default.createFile(atPath: closedByUserPath, contents: Data())
        quitHUD()
    }

    /// Quit the HUD. Removes every flag that could keep the agent waiting (pause, typing, mirror
    /// suspend) so automation never blocks on a HUD that is no longer there.
    @objc func quitHUD() {
        for path in [pausePath, typingPath, mirrorSuspendPath, quitRequestPath, pidPath, alivePath] {
            try? FileManager.default.removeItem(atPath: path)
        }
        NSApp.terminate(nil)
    }

    @objc func toggleFlash() {
        if exists(flashOffPath) {
            try? FileManager.default.removeItem(atPath: flashOffPath)
        } else {
            FileManager.default.createFile(atPath: flashOffPath, contents: Data())
        }
    }

    @objc func toggleMirror() {
        if exists(mirrorOffPath) {
            try? FileManager.default.removeItem(atPath: mirrorOffPath)
        } else {
            FileManager.default.createFile(atPath: mirrorOffPath, contents: Data())
        }
        refresh()
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

        guard !exists(flashOffPath) else {
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

    /// The mod's state says busy/idle; a stop it already lifted (you spoke) clears the flag file.
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
        case "stopped": text = "⏹ 停止中：処理を止めました。右上の入力欄からメッセージを送ると再開します"
        case "paused": text = "⏸ 一時停止中：あなたが自由に操作できます（終わったら「▶ 再開」）"
        case "typing": text = "✍️ 入力中のため、エージェントの画面操作は待機しています"
        default: text = "🤖 " + raw
        }
        if text != lastText || m != lastMode {
            let modeChanged = m != lastMode
            lastText = text
            lastMode = m
            menuButton.title = m == "paused" ? "⏸" : (m == "stopped" ? "⏹" : "☰")
            label.stringValue = text
            let base = m == "stopped" ? stoppedColor : (m == "paused" ? pausedColor : baseColor)
            playChangeEffect(flashColor: modeChanged ? (m == "stopped" ? NSColor.systemRed : NSColor.systemOrange) : accent, base: base)
        }
        updateMirrorVisibility()
        updateAsk()
        panel.orderFrontRegardless()
    }

    // MARK: approval prompt

    /// A small clickable panel above the status bar for one-click approvals asked by `dw ask`.
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
            askOK.widthAnchor.constraint(equalToConstant: 90),
            askNo.trailingAnchor.constraint(equalTo: askOK.leadingAnchor, constant: -8),
            askNo.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            askNo.widthAnchor.constraint(equalToConstant: 110),
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
            askLabel.stringValue = "❓ " + text
            NSSound(named: "Glass")?.play()
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
        try? FileManager.default.removeItem(atPath: askPath)
        askPanel.orderOut(nil)
        askID = ""
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

        mirrorHeader.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        mirrorHeader.textColor = NSColor.white.withAlphaComponent(0.85)
        busyLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)

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

        for (b, sel) in [(zoomIn, #selector(zoomInTapped)), (zoomOut, #selector(zoomOutTapped))] {
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.font = NSFont.systemFont(ofSize: 13, weight: .bold)
            b.target = self
            b.action = sel
        }
        zoomLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        zoomLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        updateZoomLabel()

        mirrorGrip.toolTip = "ドラッグでミラーを移動"
        mirrorResize.toolTip = "ドラッグでミラーのサイズを変更"
        mirrorResize.onResize = { [weak self] size in self?.resizeMirror(to: size) }
        // The header labels sit inside the grip so a drag that starts on them moves the mirror too
        for v in [mirrorGrip, scroll, input, sendButton, zoomIn, zoomOut, zoomLabel, mirrorResize] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        for v in [mirrorHeader, busyLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            mirrorGrip.addSubview(v)
        }
        NSLayoutConstraint.activate([
            mirrorGrip.topAnchor.constraint(equalTo: root.topAnchor),
            mirrorGrip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            mirrorGrip.trailingAnchor.constraint(equalTo: zoomOut.leadingAnchor, constant: -6),
            mirrorGrip.bottomAnchor.constraint(equalTo: mirrorHeader.bottomAnchor, constant: 5),
            mirrorResize.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            mirrorResize.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            mirrorResize.widthAnchor.constraint(equalToConstant: 16),
            mirrorResize.heightAnchor.constraint(equalToConstant: 16),
            mirrorHeader.topAnchor.constraint(equalTo: root.topAnchor, constant: 7),
            mirrorHeader.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            busyLabel.centerYAnchor.constraint(equalTo: mirrorHeader.centerYAnchor),
            busyLabel.leadingAnchor.constraint(equalTo: mirrorHeader.trailingAnchor, constant: 12),
            zoomIn.centerYAnchor.constraint(equalTo: mirrorHeader.centerYAnchor),
            zoomIn.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            zoomLabel.centerYAnchor.constraint(equalTo: mirrorHeader.centerYAnchor),
            zoomLabel.trailingAnchor.constraint(equalTo: zoomIn.leadingAnchor, constant: -4),
            zoomOut.centerYAnchor.constraint(equalTo: mirrorHeader.centerYAnchor),
            zoomOut.trailingAnchor.constraint(equalTo: zoomLabel.leadingAnchor, constant: -4),
            scroll.topAnchor.constraint(equalTo: mirrorHeader.bottomAnchor, constant: 6),
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
        mirror.contentView = root
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

    /// Corner drag: keep the top-left corner fixed, clamp to a usable minimum and to the screen.
    func resizeMirror(to size: NSSize) {
        let screen = mirror.screen ?? NSScreen.main
        var r = mirror.frame
        let top = r.maxY
        r.size.width = max(360, size.width)
        r.size.height = max(220, size.height)
        if let f = screen?.visibleFrame {
            r.size.width = min(r.width, f.maxX - r.minX)
            r.size.height = min(r.height, top - f.minY)
        }
        r.origin.y = top - r.height
        mirror.setFrame(r, display: true)
        saveMirrorFrame()
    }

    @objc func resetMirrorFrame() {
        guard let screen = NSScreen.main else { return }
        try? FileManager.default.removeItem(atPath: mirrorFramePath)
        mirror.setFrame(defaultMirrorFrame(on: screen), display: true)
    }

    func applyMirrorOpacity() {
        mirrorRoot.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: mirrorOpacity).cgColor
    }

    /// ☰ → 🌫: the item's tag is the opacity in percent.
    @objc func chooseMirrorOpacity(_ sender: NSMenuItem) {
        mirrorOpacity = CGFloat(sender.tag) / 100
        try? "\(mirrorOpacity)".write(toFile: mirrorOpacityPath, atomically: true, encoding: .utf8)
        applyMirrorOpacity()
    }

    /// Show the mirror unless it is switched off, suspended for a click, or the real Claude window is in front.
    func updateMirrorVisibility() {
        let off = exists(mirrorOffPath) || exists(mirrorSuspendPath)
        var claudeInFront = false
        if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            let normal = list.first { ($0[kCGWindowLayer as String] as? Int) == 0 }
            claudeInFront = (normal?[kCGWindowNumber as String] as? Int).map { CGWindowID($0) == claudeWindowID } ?? false
        }
        if off || claudeInFront {
            if mirror.isVisible { mirror.orderOut(nil) }
        } else if !mirror.isVisible {
            mirror.orderFrontRegardless()
        }
    }

    /// Re-render the conversation when the mod rewrote the feed (or the zoom changed).
    func reloadFeed(force: Bool) {
        let stamp = mtime(feedPath)
        guard force || stamp != feedStamp else { return }
        feedStamp = stamp
        guard let data = FileManager.default.contents(atPath: feedPath), let text = String(data: data, encoding: .utf8) else { return }
        let size = 13 * zoom
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
            out.append(NSAttributedString(string: tag, attributes: [.font: NSFont.systemFont(ofSize: size * 0.85, weight: .bold), .foregroundColor: tagColor, .paragraphStyle: para]))
            out.append(NSAttributedString(string: body + "\n", attributes: [.font: bodyFont, .foregroundColor: bodyColor, .paragraphStyle: para]))
        }
        textView.textStorage?.setAttributedString(out)
        textView.scrollToEndOfDocument(nil)
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

    func updateZoomLabel() { zoomLabel.stringValue = String(format: "%.0f%%", zoom * 100) }

    func setZoom(_ z: CGFloat) {
        zoom = min(2.5, max(0.6, (z * 10).rounded() / 10))
        try? "\(zoom)".write(toFile: zoomPath, atomically: true, encoding: .utf8)
        updateZoomLabel()
        reloadFeed(force: true)
    }

    @objc func zoomInTapped() { setZoom(zoom + 0.1) }
    @objc func zoomOutTapped() { setZoom(zoom - 0.1) }

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

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
installEditMenu()
let hud = HUD()
app.run()
