// Status bar of the HUD: building, placing and resizing it, click-through, colours and the change
// effect. Methods of the HUD class; its stored views and the timers that call these are in HUD.swift.
import AppKit
import QuartzCore

/// Right edge of the bar: drag it to change the bar's width.
/// It draws nothing; the pointer turns into the right-edge resize cursor over it.
final class ResizeHandle: HoverCursorView {
    private let resizeCursor = frameResizeCursor(for: [.right])
    override var hoverCursor: NSCursor { resizeCursor }
    var onResize: ((CGFloat) -> Void)?
    private var startX: CGFloat = 0
    private var startWidth: CGFloat = 0
    override func mouseDown(with event: NSEvent) {
        startX = NSEvent.mouseLocation.x
        startWidth = window?.frame.width ?? 0
    }
    override func mouseDragged(with event: NSEvent) {
        resizeCursor.set()
        onResize?(startWidth + NSEvent.mouseLocation.x - startX)
    }
}

/// The status line of the bar: text that fills the bar's height line by line and leaves a hole empty.
///
/// Why it exists: on a MacBook the bar can be dragged up beside the display notch, and text drawn
/// under the camera housing cannot be read; and a taller bar should show more of a long status than
/// one truncated line. Each row is filled span by span (beside the hole there are two), and the
/// last span ends in an ellipsis when text is left over.
/// Built by {@link HUD.buildStatusBar}; {@link HUD.refresh} keeps `hole` in step with where the bar is.
final class StatusLabel: NSView {
    var stringValue = "" { didSet { if oldValue != stringValue { needsDisplay = true } } }
    var font = NSFont.systemFont(ofSize: 17, weight: .bold) { didSet { needsDisplay = true } }
    /// Part of the view that must stay empty, in this view's coordinates (nil = none).
    var hole: NSRect? { didSet { if oldValue != hole { needsDisplay = true } } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // One paragraph: a status that carries a command on further lines flows on like prose
        let flat = stringValue.replacingOccurrences(of: "\n", with: "  ")
        guard !flat.isEmpty else { return }
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 3
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: flat, attributes: [
            .font: font, .foregroundColor: NSColor.white, .shadow: shadow, .paragraphStyle: style,
        ])
        let lineHeight = ceil(font.ascender - font.descender + font.leading) + 2
        let maxRows = max(1, Int((bounds.height - 4) / lineHeight))
        let typesetter = CTTypesetterCreateWithAttributedString(text)

        /// One piece of the text and where it goes.
        struct Piece { let range: NSRange; let rect: NSRect }
        // Lay the text out in `rows` rows, centred vertically; nil when it needs more rows than that
        func layout(rows: Int, mustFit: Bool) -> [Piece]? {
            let top = (bounds.height - CGFloat(rows) * lineHeight) / 2
            var pieces: [Piece] = []
            var start = 0
            for row in 0..<rows {
                let y = top + CGFloat(row) * lineHeight
                // Where this row may hold text: all of it, or the parts beside the hole
                var spans: [(from: CGFloat, to: CGFloat)] = [(0, bounds.width)]
                if let hole, hole.minY < y + lineHeight, hole.maxY > y, hole.minX < bounds.width, hole.maxX > 0 {
                    spans = [(0, max(0, hole.minX)), (min(bounds.width, hole.maxX), bounds.width)].filter { $0.to - $0.from > 24 }
                }
                for (index, span) in spans.enumerated() where start < text.length {
                    let isLast = row == rows - 1 && index == spans.count - 1
                    let width = span.to - span.from
                    let fits = min(max(CTTypesetterSuggestLineBreak(typesetter, start, Double(width)), 0), text.length - start)
                    // The last span takes all that is left and ends in an ellipsis when it does not fit
                    let count = isLast ? text.length - start : fits
                    guard count > 0 else { continue }
                    if isLast, mustFit, fits < count { return nil }
                    pieces.append(Piece(range: NSRange(location: start, length: count),
                                        rect: NSRect(x: span.from, y: y, width: width + (isLast ? 0 : 6), height: lineHeight)))
                    start += count
                }
            }
            return pieces
        }
        // As few rows as hold the whole text, so a short status sits in the middle of a tall bar
        var pieces: [Piece] = []
        for rows in 1...maxRows {
            if let fitted = layout(rows: rows, mustFit: rows < maxRows) { pieces = fitted; break }
        }
        for piece in pieces {
            text.attributedSubstring(from: piece.range)
                .draw(with: piece.rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }
}

extension HUD {
    // MARK: status bar

    /// Part of the status text that the display notch would hide (in the label's coordinates, origin
    /// at its top left), when the bar sits beside the notch; nil on a display without one or with the bar elsewhere.
    func notchHole() -> NSRect? {
        guard let screen = panel.screen, screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        let notch = NSRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top,
                           width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
        let text = screenRect(of: label)
        guard notch.width > 0, text.intersects(notch) else { return nil }
        let margin: CGFloat = 10
        return NSRect(x: notch.minX - margin - text.minX, y: text.maxY - notch.maxY, width: notch.width + margin * 2, height: notch.height)
    }

    func buildStatusBar() {
        // Not .screenSaver: windows at screen-saver level make macOS refuse Space switching (3-finger swipe)
        panel.level = .statusBar
        panel.collectionBehavior = hudCollectionBehavior
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
        label.wantsLayer = true
        label.layerContentsRedrawPolicy = .onSetNeedsDisplay

        resizeHandle.onResize = { [weak self] w in self?.resizeBar(to: w) }
        // Top and bottom edges: drag either to change the bar's height
        for handle in [barTopHandle, barBottomHandle] {
            handle.onResize = { [weak self] frame in self?.resizeBarHeight(to: frame) }
            handle.toolTip = "ドラッグでバーの高さを変更"
        }
        gripLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        gripLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        gripLabel.translatesAutoresizingMaskIntoConstraints = false
        grip.addSubview(gripLabel)
        grip.toolTip = "ドラッグでバーを移動"
        resizeHandle.toolTip = "ドラッグでバーの幅を変更"
        // A hairline keeps the stop button visually apart from the everyday controls
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.35).cgColor

        for v in [grip, label, explainButton, mirrorButton, settingsButton, divider, stopButton, stateBadge, resizeHandle] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(v)
        }
        let stopSlot = stopButton.widthAnchor.constraint(equalToConstant: 88)
        stopWidth = stopSlot
        NSLayoutConstraint.activate([
            grip.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            grip.topAnchor.constraint(equalTo: box.topAnchor),
            grip.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            grip.widthAnchor.constraint(equalToConstant: 34),
            gripLabel.centerXAnchor.constraint(equalTo: grip.centerXAnchor),
            gripLabel.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: grip.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: explainButton.leadingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: box.topAnchor),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            explainButton.trailingAnchor.constraint(equalTo: mirrorButton.leadingAnchor, constant: -6),
            explainButton.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            explainButton.widthAnchor.constraint(equalToConstant: 38),
            explainButton.heightAnchor.constraint(equalToConstant: 36),
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
            stopSlot,
            stopButton.heightAnchor.constraint(equalToConstant: 36),
            // The badge takes the stop button's place (the slot widens for it, see applyActivity)
            stateBadge.trailingAnchor.constraint(equalTo: stopButton.trailingAnchor),
            stateBadge.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            stateBadge.widthAnchor.constraint(equalToConstant: StateBadge.width),
            stateBadge.heightAnchor.constraint(equalToConstant: 36),
            resizeHandle.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            resizeHandle.topAnchor.constraint(equalTo: box.topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 12),
        ])
        // The controls shrink with a thin bar: their heights are set by layoutBarForHeight()
        barControlHeights = [explainButton, mirrorButton, settingsButton, stopButton, stateBadge, divider].map { view in
            box.constraints.first { $0.firstItem === view && $0.firstAttribute == .height }
                ?? view.constraints.first { $0.firstAttribute == .height }!
        }
        // Edge handles go on last, above everything, as thin strips along the top and the bottom
        for (handle, edge) in [(barTopHandle, box.topAnchor), (barBottomHandle, box.bottomAnchor)] {
            handle.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(handle)
            NSLayoutConstraint.activate([
                handle.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
                handle.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
                handle.heightAnchor.constraint(equalToConstant: 5),
                handle === barTopHandle ? handle.topAnchor.constraint(equalTo: edge) : handle.bottomAnchor.constraint(equalTo: edge),
            ])
        }
        panel.contentView = box
        placeStatusBar()
        panel.orderFrontRegardless()
    }

    /// Fit the bar's contents to its height: control heights, corner radius, text sizes, the sweep.
    /// Called whenever the bar's frame is set.
    func layoutBarForHeight() {
        let h = panel.frame.height, w = panel.frame.width
        for (index, constraint) in barControlHeights.enumerated() {
            // The divider (last) is a hairline 10 points shorter than the buttons
            constraint.constant = index == barControlHeights.count - 1 ? min(26, max(8, h - 18)) : min(36, max(14, h - 8))
        }
        box.layer?.cornerRadius = min(14, h / 2)
        label.font = NSFont.systemFont(ofSize: min(17, max(11, (h - 8) * 0.42 + 2)), weight: .bold)
        gripLabel.font = NSFont.systemFont(ofSize: min(22, max(12, h * 0.42)), weight: .bold)
        sweep.frame = CGRect(x: -w * 0.35, y: 0, width: w * 0.35, height: h)
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
        var h = HUD.defaultBarHeight
        if let saved = try? String(contentsOfFile: heightPath, encoding: .utf8), let v = Double(saved.trimmingCharacters(in: .whitespacesAndNewlines)) {
            h = CGFloat(v)
        }
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: w, height: h), display: true)
        layoutBarForHeight()
    }

    /// Change the bar's height from its top or bottom edge (the opposite edge stays put) and remember it.
    func resizeBarHeight(to proposed: NSRect) {
        var frame = panel.frame
        let height = min(max(22, proposed.height), 400)
        // Dragging the bottom edge moves the origin; dragging the top edge leaves it
        if proposed.minY != frame.minY { frame.origin.y = frame.maxY - height }
        frame.size.height = height
        panel.setFrame(frame, display: true)
        layoutBarForHeight()
        try? "\(height)".write(toFile: heightPath, atomically: true, encoding: .utf8)
        try? "\(frame.origin.x),\(frame.origin.y)".write(toFile: positionPath, atomically: true, encoding: .utf8)
    }

    /// Change the bar's width from the right-edge handle and remember it.
    func resizeBar(to width: CGFloat) {
        guard let screen = NSScreen.main else { return }
        var frame = panel.frame
        frame.size.width = min(max(480, width), screen.frame.maxX - frame.minX)
        panel.setFrame(frame, display: true)
        layoutBarForHeight()
        try? "\(frame.width)".write(toFile: widthPath, atomically: true, encoding: .utf8)
    }

    /// Settings → bar → reset: back to the bottom centre at the default width and height.
    func resetBarFrame() {
        try? FileManager.default.removeItem(atPath: positionPath)
        try? FileManager.default.removeItem(atPath: widthPath)
        try? FileManager.default.removeItem(atPath: heightPath)
        positioned = false
        placeStatusBar()
    }

    func screenRect(of view: NSView) -> NSRect { panel.convertToScreen(view.convert(view.bounds, to: nil)) }

    /// Accept mouse events only over the controls and the handles; everything else clicks through.
    func updateClickThrough() {
        let mouse = NSEvent.mouseLocation
        // The stop button takes the pointer only while it shows; the state badge is a label and lets clicks through
        let controls: [NSView] = [explainButton, mirrorButton, settingsButton, resizeHandle, grip] + (stopButton.isHidden ? [] : [stopButton])
        var hot = controls.map { screenRect(of: $0).insetBy(dx: -4, dy: -4) }
        // The height handles are thin on purpose: only a few points along each edge take the pointer
        hot += [barTopHandle, barBottomHandle].map { screenRect(of: $0).insetBy(dx: 0, dy: -2) }
        explainButton.isHovered = screenRect(of: explainButton).contains(mouse)
        mirrorButton.isHovered = screenRect(of: mirrorButton).contains(mouse)
        settingsButton.isHovered = screenRect(of: settingsButton).contains(mouse)
        stopButton.isHovered = !stopButton.isHidden && screenRect(of: stopButton).contains(mouse)
        let dragging = NSEvent.pressedMouseButtons & 1 == 1 && !panel.ignoresMouseEvents
        panel.ignoresMouseEvents = !(hot.contains { $0.contains(mouse) } || dragging)
        // The bar ignores the pointer until it rests on a control, so a tracking area misses a pointer
        // that arrived meanwhile: this polling also shows the resize cursor over the three edges
        let edge: HoverCursorView? = screenRect(of: resizeHandle).contains(mouse) ? resizeHandle
            : [barTopHandle, barBottomHandle].first { screenRect(of: $0).insetBy(dx: 0, dy: -2).contains(mouse) }
        if let edge, panel.isVisible {
            edge.hoverCursor.set()
            barEdgeHovered = true
        } else if barEdgeHovered, !dragging {
            barEdgeHovered = false
            NSCursor.arrow.set()
        }
    }

    /// What the session is doing right now, held steady: between two performed steps the agent often
    /// reads or checks something for a second or two, and a stop button and a screen border that
    /// blink off and on would say "you may use the Mac" when the next key press is a moment away.
    /// So "acting" lasts a few seconds past its last sign, unless the agent has started to wait.
    ///
    /// @returns The state for the bar's trailing end and the screen border (see {@link Activity}).
    func currentActivity() -> Activity {
        let raw = rawActivity()
        let now = Date()
        if raw == .performing { lastPerformingAt = now }
        // Waiting and stopped mean it: the agent will not touch the screen until the user acts
        if raw == .other || raw == .skill, let last = lastPerformingAt, now.timeIntervalSince(last) < 6 { return .performing }
        return raw
    }

    /// The state as the files say it this instant, from the bridge's turn state, the class of its
    /// newest tool call and the times `dw` last acted or narrated.
    private func rawActivity() -> Activity {
        if isStopOn() { return .stopped }
        let tool = mtime(toolClassPath)
        let action = mtime(actionStampPath), narration = mtime(narrationStampPath)
        /// True when `dw` did that since the newest tool call began (without a tool class from the
        /// bridge: within the last seconds).
        func since(_ stamp: Date?) -> Bool {
            guard let stamp else { return false }
            return tool.map { stamp >= $0 } ?? (Date().timeIntervalSince(stamp) < 15)
        }
        guard let busy = modBusy else {
            // No bridge: only `dw` itself tells. Recent action or narration counts as the walkthrough acting
            let recent = [action, narration].compactMap { $0 }.max().map { Date().timeIntervalSince($0) < 15 } ?? false
            return recent ? .performing : (exists(askPath) ? .waiting : .other)
        }
        // The turn has ended: the agent waits for the user, or for something it started in the background
        if !busy { return .waiting }
        // Keys, clicks and window moves outrank everything: this is when a stop button is needed
        if since(action) { return .performing }
        let toolClass = ((try? String(contentsOfFile: toolClassPath, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if toolClass == "skill" { return .skill }
        if toolClass == "waiting" { return .waiting }
        return since(narration) ? .performing : .other
    }

    /// Show the stop button while the walkthrough acts (or was stopped), the state badge otherwise.
    func applyActivity(_ activity: Activity) {
        // Every tick: a screen that was connected or rearranged gets its border too
        updatePerformingBorder(visible: activity == .performing)
        guard activity != lastActivity else { return }
        lastActivity = activity
        let button = activity == .performing || activity == .stopped
        stopButton.isHidden = !button
        stateBadge.isHidden = button
        if !button { stateBadge.show(activity) }
        stopWidth?.constant = button ? 88 : StateBadge.width
    }

    /// The chat button: bring the mirror here when it is open on another desktop, otherwise show or hide it.
    @objc func toggleMirror() {
        if settings.isOn("mirror.visible"), mirror.isOnAnotherSpace {
            mirror.orderFrontOnActiveSpace()
        } else {
            settings.toggle("mirror.visible")
        }
    }

    /// The book button: bring the explainer forward when it is open on another desktop or another
    /// window covers it, otherwise show or hide it.
    @objc func toggleExplainer() {
        if settings.isOn("explain.visible"), explainer.isOnAnotherSpace || explainer.isCovered {
            explainer.bringToFront()
        } else {
            settings.toggle("explain.visible")
        }
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
}
