// Conversation mirror of the HUD: the feed, folding, zoom, the message box and focus hand-back,
// plus the panel and text classes it uses. Methods of the HUD class; its stored views are in HUD.swift.
import AppKit

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

/// One edge or corner of a HUD panel: dragging it moves only that side, like a normal window border,
/// and the pointer shows the matching resize shape over it.
final class EdgeResizeHandle: HoverCursorView {
    struct Edges: OptionSet { let rawValue: Int
        static let left = Edges(rawValue: 1), right = Edges(rawValue: 2), bottom = Edges(rawValue: 4), top = Edges(rawValue: 8) }
    let edges: Edges
    var onResize: ((NSRect) -> Void)?
    private var start = NSPoint.zero
    private var startFrame = NSRect.zero
    private lazy var resizeCursor = frameResizeCursor(for: edges)
    override var hoverCursor: NSCursor { resizeCursor }
    init(_ edges: Edges) { self.edges = edges; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("not used") }
    /// The first click must start the drag: the panel is never the key window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation
        startFrame = window?.frame ?? .zero
    }
    override func mouseDragged(with event: NSEvent) {
        resizeCursor.set()
        let p = NSEvent.mouseLocation
        let dx = p.x - start.x, dy = p.y - start.y
        var r = startFrame
        if edges.contains(.left) { r.origin.x += dx; r.size.width -= dx }
        if edges.contains(.right) { r.size.width += dx }
        if edges.contains(.bottom) { r.origin.y += dy; r.size.height -= dy }
        if edges.contains(.top) { r.size.height += dy }
        onResize?(r)
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

/// Pin resize handles to the borders of a floating panel's root view (6pt sides, 14pt corners).
/// Call it after the content was added, so the handles sit above it. Used by the mirror and the explainer.
///
/// @param sibling - A subview the handles go under (the first button of the header): a corner
///   handle that lay over the close button turned a click near the corner into a resize.
func pinEdgeHandles(_ handles: [EdgeResizeHandle], to root: NSView, below sibling: NSView? = nil) {
    let edge: CGFloat = 6, corner: CGFloat = 14
    for h in handles {
        h.translatesAutoresizingMaskIntoConstraints = false
        if let sibling { root.addSubview(h, positioned: .below, relativeTo: sibling) } else { root.addSubview(h) }
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

extension HUD {
    // MARK: mirror

    @objc func closeMirror() { settings.set("mirror.visible", 0) }

    /// The mod's state says busy/idle.
    func syncModState() {
        guard let data = FileManager.default.contents(atPath: statePath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            busyLabel.stringValue = "（Mod未接続）"
            modBusy = nil
            return
        }
        let busy = obj["busy"] as? Bool ?? false
        modBusy = busy
        busyLabel.stringValue = busy ? "● 作業中" : "○ 待機中（メッセージ待ち）"
        busyLabel.textColor = busy ? NSColor.systemGreen : NSColor.systemYellow
    }

    func buildMirror() {
        guard let screen = NSScreen.main else { return }
        mirror.setFrame(savedMirrorFrame(on: screen) ?? defaultMirrorFrame(on: screen), display: false)
        mirror.delegate = self
        mirror.level = .floating
        mirror.collectionBehavior = stageCollectionBehavior
        mirror.isOpaque = false
        mirror.backgroundColor = .clear
        mirror.hasShadow = true
        mirror.becomesKeyOnlyIfNeeded = false
        mirror.hidesOnDeactivate = false

        let root = mirrorRoot
        root.wantsLayer = true
        root.layer?.cornerRadius = surfaceCornerRadius
        root.layer?.masksToBounds = true
        // Under everything: a material that blurs what the mirror covers, then the mirror's own
        // colour as a tint, as see-through as the user chose
        mirrorTint.wantsLayer = true
        for layer in [mirrorMaterial, mirrorTint] as [NSView] {
            layer.frame = root.bounds
            layer.autoresizingMask = [.width, .height]
            root.addSubview(layer)
        }
        applyMirrorOpacity()

        mirrorTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        mirrorTitle.textColor = .labelColor
        busyLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)

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

        zoomLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.alignment = .center
        updateZoomLabel()

        // The page that draws the conversation: under the header, down to the Mirror's lower edge.
        // Hidden until the page and a Transcript are there (see updateMirrorPage)
        mirrorPage.attach()
        mirrorPage.webView.isHidden = true
        mirrorPage.onSubmit = { [weak self] text in self?.submitPrompt(text) }
        mirrorPage.onInterrupt = { [weak self] in
            // Esc in the terminal stops the running turn: here it is the stop button
            if !isStopOn() { self?.toggleStop() }
        }
        mirrorPage.onRelease = { [weak self] in self?.returnMirrorFocus() }
        mirrorPage.onFocus = { [weak self] focused in
            guard let self, focused, self.mirrorPreviousApp == nil, let last = lastOtherApp, !last.isTerminated else { return }
            self.mirrorPreviousApp = last
        }

        mirrorGrip.toolTip = "ドラッグでミラーを移動"
        // Invisible 6pt borders on every side and 14pt corners: drag any of them to resize
        for h in mirrorHandles { h.onResize = { [weak self] r in self?.resizeMirror(to: r) } }
        // The header labels sit inside the grip so a drag that starts on them moves the mirror too
        for v in [mirrorGrip, scroll, input, sendButton, mirrorPage.webView, zoomIn, zoomOut, zoomLabel, closeButton] as [NSView] {
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
            mirrorGrip.heightAnchor.constraint(equalToConstant: 36),
            mirrorTitle.centerYAnchor.constraint(equalTo: mirrorGrip.centerYAnchor),
            mirrorTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            busyLabel.centerYAnchor.constraint(equalTo: mirrorTitle.centerYAnchor),
            busyLabel.leadingAnchor.constraint(equalTo: mirrorTitle.trailingAnchor, constant: 12),

            closeButton.centerYAnchor.constraint(equalTo: mirrorGrip.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
            zoomIn.centerYAnchor.constraint(equalTo: mirrorGrip.centerYAnchor),
            zoomIn.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),
            zoomIn.widthAnchor.constraint(equalToConstant: 28),
            zoomIn.heightAnchor.constraint(equalToConstant: 28),
            zoomLabel.centerYAnchor.constraint(equalTo: mirrorGrip.centerYAnchor),
            zoomLabel.trailingAnchor.constraint(equalTo: zoomIn.leadingAnchor, constant: -2),
            zoomLabel.widthAnchor.constraint(equalToConstant: 42),
            zoomOut.centerYAnchor.constraint(equalTo: mirrorGrip.centerYAnchor),
            zoomOut.trailingAnchor.constraint(equalTo: zoomLabel.leadingAnchor, constant: -2),
            zoomOut.widthAnchor.constraint(equalToConstant: 28),
            zoomOut.heightAnchor.constraint(equalToConstant: 28),

            scroll.topAnchor.constraint(equalTo: mirrorGrip.bottomAnchor, constant: 2),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
            scroll.bottomAnchor.constraint(equalTo: input.topAnchor, constant: -6),
            input.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            input.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -6),
            input.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            input.heightAnchor.constraint(equalToConstant: 28),
            mirrorPage.webView.topAnchor.constraint(equalTo: mirrorGrip.bottomAnchor, constant: 2),
            mirrorPage.webView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            mirrorPage.webView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
            mirrorPage.webView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
            sendButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            sendButton.centerYAnchor.constraint(equalTo: input.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 70),
        ])
        // Under the header's buttons, over everything else (see pinEdgeHandles)
        pinEdgeHandles(mirrorHandles, to: root, below: zoomIn)
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

    /// Tint and outline of the mirror: as see-through as the user chose (opaque while "Reduce
    /// transparency" is on), its outline stronger with "Increase contrast".
    func applyMirrorOpacity() {
        mirrorTint.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: surfaceAlpha(CGFloat(settings.value("mirror.opacity")))).cgColor
        mirrorRoot.layer?.borderColor = accent.hudCG
        mirrorRoot.layer?.borderWidth = surfaceBorderWidth
    }

    /// Show the mirror unless it is switched off; conceal it while it is suspended for a click or the
    /// real chat window is in front (it comes back on the desktop it was on, not on the one the user
    /// went to next).
    func updateMirrorVisibility() {
        let off = !settings.isOn("mirror.visible")
        var claudeInFront = false
        if claudeWindowID != 0,
           let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            let normal = list.first { ($0[kCGWindowLayer as String] as? Int) == 0 }
            claudeInFront = (normal?[kCGWindowNumber as String] as? Int).map { CGWindowID($0) == claudeWindowID } ?? false
        }
        // Concealed before it is ordered in: a mirror that opens while the HUD is hidden never shows
        mirror.setConcealed(claudeInFront || exists(mirrorSuspendPath))
        if off {
            if mirror.isVisible { mirror.orderOut(nil) }
        } else if !mirror.isVisible {
            mirror.orderFrontRegardless()
        }
    }

    /// Show the Mirror's page in place of the feed and the message box whenever the page and the
    /// Bridge's Transcript are there, and hand the page what changed.
    ///
    /// Why it exists: the page needs a Bridge that writes the Transcript, and a session keeps the
    /// Bridge it loaded until its plugins are reloaded; until then the older feed keeps the Mirror
    /// useful. Called by {@link HUD.reloadFeed} on its timer.
    ///
    /// @returns True while the page is what the Mirror shows.
    func updateMirrorPage() -> Bool {
        let paged = mirrorPage.isAvailable
        if mirrorPage.webView.isHidden == paged {
            mirrorPage.webView.isHidden = !paged
            for view in [scroll, input, sendButton] as [NSView] { view.isHidden = paged }
        }
        if paged { mirrorPage.refresh(zoom: zoom) }
        return paged
    }

    /// Give the keyboard back to the app the user came from before the page's Input box took it.
    func returnMirrorFocus() {
        mirror.makeFirstResponder(nil)
        if let app = mirrorPreviousApp, !app.isTerminated {
            // Cooperative activation (macOS 14+): yield to the app first, then ask it to come forward
            NSApp.yieldActivation(to: app)
            app.activate()
        }
        mirrorPreviousApp = nil
    }

    /// Re-render the conversation when the mod rewrote the feed (or an option changed).
    /// `keepScroll` keeps the reader's position (used when an entry is folded or unfolded).
    func reloadFeed(force: Bool, keepScroll: Bool = false) {
        // The page draws the conversation when it can: the feed below is what shows until then
        if updateMirrorPage() { return }
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
                case "you": return ("あなた ", NSColor.systemGreen, NSColor.labelColor, NSFont.systemFont(ofSize: size, weight: .semibold))
                case "agent": return ("Claude ", accent, NSColor.labelColor, NSFont.systemFont(ofSize: size))
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
        // The page's Input box counts the same way: focused in the key Mirror, or holding a draft
        let paging = !mirrorPage.webView.isHidden && ((mirror.isKeyWindow && mirrorPage.isFocused) || mirrorPage.hasDraft)
        // Not while the HUD is hidden: the user cannot see that a draft keeps the agent waiting
        let typing = (editing || !input.stringValue.isEmpty || paging) && !hudHidden
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
        submitPrompt(text)
        input.stringValue = ""
        input.returnFocus()
    }

    /// Hand a Prompt to the Bridge through the inbox file; it reaches the Session without any GUI step.
    /// Called for the message box ({@link HUD.sendMessage}) and for the page's Input box.
    func submitPrompt(_ text: String) {
        appendLine(inboxPath, ["text": text.trimmingCharacters(in: .whitespacesAndNewlines)])
        notePending("メッセージ", route: .message)
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
