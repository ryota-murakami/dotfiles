// Status bar of the HUD: building, placing and resizing it, click-through, colours and the change
// effect. Methods of the HUD class; its stored views and the timers that call these are in HUD.swift.
import AppKit
import QuartzCore

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

extension HUD {
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

    @objc func toggleMirror() { settings.toggle("mirror.visible") }

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
