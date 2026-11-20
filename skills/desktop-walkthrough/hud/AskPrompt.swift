// Approval prompt of the HUD: a compact card for one-click answers (`dw ask`, `dw wait-user`),
// with optional feedback buttons that tell the agent something without answering.
// It appears by the bar, never on the explainer, and can be dragged anywhere; the place is remembered.
// Methods of the HUD class; its stored views are in HUD.swift.
import AppKit

extension HUD {
    // MARK: approval prompt

    /// Widest the card gets: past this the question wraps and the buttons take a row of their own.
    static let askMaxWidth: CGFloat = 620

    /// Build the card. Frames are set by {@link HUD.layoutAsk} because the card has two shapes.
    func buildAskPanel() {
        askPanel.level = .statusBar
        askPanel.collectionBehavior = hudCollectionBehavior
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
        askLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        askLabel.textColor = .white
        askLabel.maximumNumberOfLines = 4
        askNo.bezelStyle = .rounded
        askNo.controlSize = .large
        askNo.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        askNo.target = self
        askNo.action = #selector(askNoTapped)
        // The main answer is drawn by its layer: a bezel turns grey in a panel that is never the key window
        askOK.isBordered = false
        askOK.wantsLayer = true
        askOK.layer?.cornerRadius = 7
        askOK.layer?.backgroundColor = accent.cgColor
        askOK.target = self
        askOK.action = #selector(askOKTapped)
        // The whole card is a drag handle under the buttons: it can be moved off whatever it covers
        askGrip.toolTip = "ドラッグで移動"
        askGripMark.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        askGripMark.textColor = NSColor.white.withAlphaComponent(0.7)
        askExtras.orientation = .horizontal
        askExtras.spacing = 6
        for v in [askGrip, askExtras, askNo, askOK] as [NSView] { root.addSubview(v) }
        for v in [askGripMark, askLabel] as [NSView] { askGrip.addSubview(v) }
        askPanel.contentView = root
    }

    /// Show the pending question (if any); hide it once answered or withdrawn.
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
            askOK.attributedTitle = NSAttributedString(string: (obj["ok"] as? String) ?? "OK", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.white,
            ])
            askNo.title = (obj["no"] as? String) ?? "キャンセル"
            askLabel.stringValue = ((obj["icon"] as? String) ?? "❓") + " " + text
            rebuildAskExtras((obj["buttons"] as? [String]) ?? [])
            askSize = layoutAsk()
            if settings.isOn("ask.sound") { NSSound(named: "Glass")?.play() }
        }
        guard !askID.isEmpty else { return }
        // Never move the prompt while a mouse button is down: that would fight the user's drag
        if askPanel.isVisible, NSEvent.pressedMouseButtons & 1 == 1 { return }
        // It is not where it was last placed: the user dragged it, so it stays there for later questions too
        if askPanel.isVisible, let placed = askPlacedOrigin,
           abs(askPanel.frame.origin.x - placed.x) > 1 || abs(askPanel.frame.origin.y - placed.y) > 1 {
            let o = askPanel.frame.origin
            try? "\(o.x),\(o.y)".write(toFile: askPositionPath, atomically: true, encoding: .utf8)
            askRevealed = false
            askRevealArmed = false
        }
        let frame = askFrame()
        askPlacedOrigin = frame.origin
        if askPanel.frame != frame { askPanel.setFrame(frame, display: true) }
        if !askPanel.isVisible { askPanel.orderFrontRegardless() }
    }

    /// Lay the card out for the current question: one row when everything fits in
    /// {@link HUD.askMaxWidth}, else the question (wrapped) above a row of buttons.
    ///
    /// @returns The size the card needs.
    func layoutAsk() -> NSSize {
        let pad: CGFloat = 14, gap: CGFloat = 8, textX: CGFloat = 34
        let font = askLabel.font ?? NSFont.systemFont(ofSize: 15, weight: .bold)
        let text = askLabel.stringValue as NSString
        let lineHeight = ceil(font.ascender - font.descender + font.leading) + 2
        let lineWidth = ceil(text.size(withAttributes: [.font: font]).width) + 8
        askNo.sizeToFit()
        let buttonHeight = max(askNo.frame.height, 30)
        let noWidth = max(askNo.frame.width, 96)
        let okWidth = max(ceil(askOK.attributedTitle.size().width) + 30, 84)
        let extras = askExtras.arrangedSubviews.isEmpty ? NSSize.zero : askExtras.fittingSize
        let buttonsWidth = (extras.width > 0 ? extras.width + gap + 4 : 0) + noWidth + gap + okWidth

        let size: NSSize
        let textFrame: NSRect
        let buttonsY: CGFloat
        let oneRow = textX + lineWidth + 12 + buttonsWidth + pad
        if oneRow <= Self.askMaxWidth {
            size = NSSize(width: max(oneRow, 340), height: 58)
            textFrame = NSRect(x: textX, y: (58 - lineHeight) / 2, width: lineWidth, height: lineHeight)
            buttonsY = (58 - buttonHeight) / 2
        } else {
            // As wide as the text or the button row needs, up to the limit; the text wraps in what is left
            let width = max(min(Self.askMaxWidth, textX + lineWidth + pad), textX + buttonsWidth + pad, 420)
            let textWidth = width - textX - pad
            let wrapped = text.boundingRect(with: NSSize(width: textWidth, height: 400),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
            let textHeight = min(ceil(wrapped.height) + 4, lineHeight * 4)
            size = NSSize(width: width, height: pad + textHeight + 10 + buttonHeight + pad - 2)
            textFrame = NSRect(x: textX, y: size.height - pad - textHeight, width: textWidth, height: textHeight)
            buttonsY = pad - 2
        }
        askGrip.frame = NSRect(origin: .zero, size: size)
        askLabel.frame = textFrame
        askGripMark.sizeToFit()
        askGripMark.frame.origin = NSPoint(x: 10, y: textFrame.maxY - lineHeight + (lineHeight - askGripMark.frame.height) / 2)
        // Buttons from the right: the main answer, the other answer, then the feedback buttons
        var x = size.width - pad - okWidth
        askOK.frame = NSRect(x: x, y: buttonsY + (buttonHeight - 28) / 2, width: okWidth, height: 28)
        x -= gap + noWidth
        askNo.frame = NSRect(x: x, y: buttonsY, width: noWidth, height: buttonHeight)
        if extras.width > 0 {
            x -= gap + 4 + extras.width
            askExtras.frame = NSRect(x: x, y: buttonsY + (buttonHeight - extras.height) / 2, width: extras.width, height: extras.height)
        } else {
            askExtras.frame = .zero
        }
        return size
    }

    /// Where the card goes: at the place the user dragged it to, else by the status bar (above it, or
    /// below when there is no room).
    ///
    /// The user may park it mostly off-screen, out of the way: a strip stays visible, and the card
    /// slides back in while the pointer is on it. A card that is fully on screen steps aside when it
    /// would cover the explainer.
    func askFrame() -> NSRect {
        let bar = panel.frame
        let w = ceil(askSize.width), h = ceil(askSize.height)
        var origin = NSPoint(x: bar.midX - w / 2, y: bar.maxY + 8)
        guard let display = panel.screen ?? NSScreen.main else { return NSRect(x: origin.x.rounded(), y: origin.y.rounded(), width: w, height: h) }
        let screen = display.frame, visible = display.visibleFrame
        if origin.y + h > visible.maxY { origin.y = bar.minY - h - 8 }
        if let saved = try? String(contentsOfFile: askPositionPath, encoding: .utf8) {
            let parts = saved.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if parts.count == 2 { origin = NSPoint(x: parts[0], y: parts[1]) }
        }
        // However far it was pushed out, this much of the card stays on screen to bring it back
        let strip: CGFloat = 44
        var frame = NSRect(x: min(max(screen.minX - w + strip, origin.x), screen.maxX - strip),
                           y: min(max(screen.minY - h + strip, origin.y), screen.maxY - strip), width: w, height: h)
        let parked = !screen.contains(frame)
        if parked {
            // Parked: show the whole card while the pointer is on its strip (or, once shown, on the card)
            let inside = NSRect(x: min(max(screen.minX, frame.minX), screen.maxX - w),
                                y: min(max(screen.minY, frame.minY), screen.maxY - h), width: w, height: h)
            let mouse = NSEvent.mouseLocation
            if askRevealed {
                askRevealed = inside.insetBy(dx: -14, dy: -14).contains(mouse)
            } else {
                // Right after it was dragged out, the pointer still rests on the strip: wait until it
                // has left once, or the card would jump back in under the hand that just parked it
                let onStrip = frame.intersection(screen).insetBy(dx: -4, dy: -4).contains(mouse)
                if !onStrip { askRevealArmed = true }
                askRevealed = askRevealArmed && onStrip
            }
            if askRevealed { frame = inside }
        } else {
            askRevealed = false
            // The user reads in the explainer: step aside to the nearest side that has room
            let reading = explainer.panel.frame
            if explainer.panel.isVisible, frame.intersects(reading) {
                if reading.minX - w - 8 >= visible.minX { frame.origin.x = reading.minX - w - 8 }
                else if reading.maxX + 8 + w <= visible.maxX { frame.origin.x = reading.maxX + 8 }
                else if reading.minY - h - 8 >= visible.minY { frame.origin.y = reading.minY - h - 8 }
                else if reading.maxY + 8 + h <= visible.maxY { frame.origin.y = reading.maxY + 8 }
            }
        }
        // A strip must not answer by accident: the buttons work only when the whole card is shown
        let usable = !parked || askRevealed
        for button in [askOK, askNo] + askExtras.arrangedSubviews.compactMap({ $0 as? NSButton }) where button.isEnabled != usable {
            // A feedback button that was just pressed stays disabled until its own timer re-enables it
            if usable, button.title.hasPrefix("✓ ") { continue }
            button.isEnabled = usable
        }
        // Whole points: a frame the window server would round could be mistaken for a drag
        return NSRect(x: frame.origin.x.rounded(), y: frame.origin.y.rounded(), width: w, height: h)
    }

    /// Settings → prompt → reset: follow the status bar again.
    func resetAskPosition() {
        try? FileManager.default.removeItem(atPath: askPositionPath)
        askPlacedOrigin = nil
    }

    /// Replace the feedback buttons with those of the current question (`"buttons"` of ask.json).
    func rebuildAskExtras(_ labels: [String]) {
        for view in askExtras.arrangedSubviews {
            askExtras.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        askExtraLabels = labels
        for (index, label) in labels.enumerated() {
            let button = NSButton(title: "✓ " + label, target: self, action: #selector(askExtraTapped(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            button.tag = index
            button.toolTip = "押すとエージェントに伝わります（確認は開いたままです）"
            // Sized for the pressed title ("✓ …"), so pressing it does not shift its neighbours
            button.widthAnchor.constraint(equalToConstant: button.fittingSize.width).isActive = true
            button.title = label
            askExtras.addArrangedSubview(button)
        }
    }

    /// A feedback button: tells the agent what the user is doing without answering the question.
    ///
    /// Why it exists: the user watches the app, not the agent's terminal, and a wait gives the agent no
    /// sign of whether they are reading, stuck or away. The label goes to the session as a message (the
    /// path the mirror's message box uses); the question stays open for its real answer.
    @objc func askExtraTapped(_ sender: NSButton) {
        guard !askID.isEmpty, askExtraLabels.indices.contains(sender.tag) else { return }
        let label = askExtraLabels[sender.tag]
        appendLine(inboxPath, ["text": "[HUD] フィードバック「\(label)」（確認「\(askLabel.stringValue)」は開いたままです）"])
        appendJournal("💬 フィードバック「\(label)」")
        notePending(label, route: .message)
        // Show that it was sent, then let it be pressed again later ("still reading")
        sender.title = "✓ " + label
        sender.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self, weak sender] in
            guard let self, let sender, self.askExtraLabels.indices.contains(sender.tag),
                  self.askExtraLabels[sender.tag] == label else { return }
            sender.title = label
            sender.isEnabled = true
        }
    }

    func answerAsk(_ answer: String) {
        guard !askID.isEmpty else { return }
        try? "\(askID) \(answer)".write(toFile: askAnswerPath, atomically: true, encoding: .utf8)
        // Until the agent reacts, the bar shows that the press is on its way and when it arrived
        notePending(answer == "ok" ? askOK.attributedTitle.string : askNo.title, route: askWaiterAlive() ? .answer : .message)
        // Nobody is waiting (the agent's bounded wait ended and its turn is over): deliver the answer
        // as a message, the same way the mirror's message box does, so the click is never lost
        if !askWaiterAlive() {
            let label = answer == "ok" ? askOK.attributedTitle.string : askNo.title
            let question = askLabel.stringValue
            appendLine(inboxPath, ["text": "[HUD] \(question) → 「\(label)」を押しました"])
            appendJournal("  → 「\(label)」（待ち受けが無かったので、メッセージで届けた）")
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
}
