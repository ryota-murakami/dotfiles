// Approval prompt of the HUD: a compact card for one-click answers (`dw ask`, `dw wait-user`),
// with optional feedback buttons that tell the agent something without answering.
// It appears by the bar, never on the explainer, and can be dragged anywhere; the place is remembered.
// It stays above every window, except that a click in the explainer sends it behind the explainer.
// It shows on the desktop of the note or page it asks about; the hand button on the bar, lit while the
// card is before the user, calls it elsewhere and puts it away.
// Methods of the HUD class; its stored views are in HUD.swift.
import AppKit

/// Panel of the prompt card: reports a click anywhere on it.
///
/// Why it exists: a card that went behind the explainer ({@link HUD.tuckAsk}) comes back when the
/// part of it that still shows is clicked, whichever control is under the pointer.
final class AskPanel: NSPanel {
    /// Called on every click in the card, before the control under the pointer gets it.
    var onMouseDown: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { onMouseDown?() }
        super.sendEvent(event)
    }
}

extension HUD {
    // MARK: approval prompt

    /// Widest the card gets: past this the question wraps and the buttons take a row of their own.
    static let askMaxWidth: CGFloat = 620

    /// Build the card. Frames are set by {@link HUD.layoutAsk} because the card has two shapes.
    func buildAskPanel() {
        askPanel.level = .statusBar
        askPanel.collectionBehavior = stageCollectionBehavior
        askPanel.isOpaque = false
        askPanel.backgroundColor = .clear
        askPanel.hasShadow = true
        askPanel.becomesKeyOnlyIfNeeded = true
        askPanel.onMouseDown = { [weak self] in
            if self?.askTucked == true { self?.raiseAsk() }
        }
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = surfaceCornerRadius
        askPanel.contentView = root
        applyAskLook()
        askLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        askLabel.textColor = .labelColor
        askLabel.maximumNumberOfLines = 4
        askIcon.imageScaling = .scaleNone
        askIcon.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        askIcon.contentTintColor = .systemOrange
        // Both answers and the feedback buttons are the same control (see CapsuleButton)
        askNo.target = self
        askNo.action = #selector(askNoTapped)
        askOK.target = self
        askOK.action = #selector(askOKTapped)
        // The whole card is a drag handle under the buttons: it can be moved off whatever it covers
        askGrip.toolTip = "ドラッグで移動"
        askGripMark.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        askGripMark.textColor = .secondaryLabelColor
        askExtras.orientation = .horizontal
        askExtras.spacing = 6
        for v in [askGrip, askExtras, askNo, askOK] as [NSView] { root.addSubview(v) }
        for v in [askGripMark, askIcon, askLabel] as [NSView] { askGrip.addSubview(v) }
    }

    /// Background and outline of the card: opaque while "Reduce transparency" is on, a stronger
    /// outline with "Increase contrast". Called at launch and when a display setting changes.
    func applyAskLook() {
        guard let layer = askPanel.contentView?.layer else { return }
        layer.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: surfaceAlpha(0.96)).cgColor
        layer.borderColor = NSColor.systemOrange.hudCG
        layer.borderWidth = surfaceBorderWidth
    }

    /// The symbol for the icon `dw` gave a question (it writes an emoji): a question mark for a
    /// plain question, a raised hand when the agent hands the Mac over. Nil for any other icon,
    /// which is then shown as the text it is.
    private func askSymbol(for icon: String) -> String? {
        switch icon {
        case "❓", "": return "questionmark.circle.fill"
        case "🙋": return "hand.raised.fill"
        default: return nil
        }
    }

    /// The surface an open question is about: the note beside what it explains, else the explainer's
    /// page. Nil while neither is open: the question then stands alone.
    ///
    /// Why it exists: the card belongs with what the user is asked to read. Shown on whichever
    /// desktop was active when `dw` asked, it ended up over another app (the user's chat) while its
    /// page was on a different desktop. Read by {@link HUD.updateAsk} and {@link HUD.showAsk}.
    var askStage: NSWindow? {
        if notePopup.panel.isVisible { return notePopup.panel }
        if explainer.panel.isVisible { return explainer.panel }
        return nil
    }

    /// Show the pending question (if any); hide it once answered or withdrawn.
    func updateAsk() {
        guard exists(askPath) else {
            if askPanel.isVisible { askPanel.orderOut(nil) }
            askID = ""; askStamp = nil
            askSummoned = false
            askPutAway = false
            raiseAsk()
            setAskButton(shown: false)
            return
        }
        let stamp = mtime(askPath)
        if stamp != askStamp {
            askStamp = stamp
            guard let data = FileManager.default.contents(atPath: askPath),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String, let text = obj["text"] as? String else { return }
            // A new question is on top again, whatever the last one was sent behind or put away, and
            // no longer on the desktop the last one was called to
            if id != askID {
                raiseAsk()
                askPutAway = false
                if askSummoned {
                    askSummoned = false
                    if askPanel.isVisible { askPanel.orderOut(nil) }
                }
            }
            askID = id
            // A question that stands alone appears where the user is looking; a card still open on
            // another desktop comes along. One with a page goes where the page is (see below)
            if askStage == nil, askPanel.isOnAnotherSpace { askPanel.orderOut(nil) }
            // dw ask uses OK / キャンセル; dw wait-user asks for a hand-off with its own labels
            askOK.label = (obj["ok"] as? String) ?? "OK"
            askNo.label = (obj["no"] as? String) ?? "キャンセル"
            let icon = (obj["icon"] as? String) ?? "❓"
            askIconText = icon
            // What the session is told about this question keeps the icon as text
            askQuestion = icon + " " + text
            if let symbol = askSymbol(for: icon) {
                askIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                askIcon.isHidden = false
                askLabel.stringValue = text
            } else {
                askIcon.isHidden = true
                askLabel.stringValue = askQuestion
            }
            rebuildAskExtras((obj["buttons"] as? [String]) ?? [])
            askSize = layoutAsk()
            if settings.isOn("ask.sound") { NSSound(named: "Glass")?.play() }
            // A question is one of the few changes worth saying aloud
            announce("確認：" + text)
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
        // The card stays with what it asks about (see askStage)
        let stage = askStage
        if let stage, stage.isOnActiveSpace {
            // The user is at the page: a card called to another desktop, or left on one, comes along
            askSummoned = false
            if askPanel.isOnAnotherSpace { askPanel.orderOut(nil) }
        }
        // The page is open on another desktop: the card waits there with it and this desktop stays
        // clear of the walkthrough, unless the user called the card here
        let waitsWithStage = !askSummoned && (stage?.isOnAnotherSpace ?? false)
        // Out of sight while the user has hidden the HUD (the question stays open): concealed before
        // the card is ordered in, so one that arrives meanwhile never shows
        askPanel.setConcealed(false)
        if askPutAway {
            // Put away with the hand button: off every desktop until it is pressed again
            if askPanel.isVisible { askPanel.orderOut(nil) }
        } else if waitsWithStage {
            if askPanel.isVisible, askPanel.isOnActiveSpace { askPanel.orderOut(nil) }
        } else if !askPanel.isVisible {
            askPanel.orderFrontRegardless()
        }
        // Behind the explainer only while the explainer is what the user reads: it closed, moved off
        // the card, or an app's window came in front of it, so the card is on top again
        if askTucked, !explainer.panel.isVisible || explainer.isOnAnotherSpace || explainer.isCovered
            || !askPanel.frame.intersects(explainer.panel.frame) { raiseAsk() }
        setAskButton(shown: true)
        // Lit while the card is before the user, like the book and chat buttons. A dot instead while
        // the question waits out of sight: put away, behind the explainer, or on another desktop
        askButton.isActive = askInSight
        askButton.badgeColor = askInSight ? nil : .systemOrange
        updateAskBreathing()
    }

    /// True while the card of the open question is before the user: on the desktop they are looking
    /// at and above the explainer. A card parked at a screen edge counts: its strip shows.
    ///
    /// Why it exists: the hand button was lit while the card was out of sight, the opposite of the
    /// book and chat buttons beside it, and read as a wrong state. Read by {@link HUD.updateAsk}
    /// for the button's look and by {@link HUD.showAsk} for what a press does.
    var askInSight: Bool { !askID.isEmpty && askPanel.isVisible && askPanel.isOnActiveSpace && !askTucked }

    /// Send the card behind the explainer, the way a click on a window puts it over its neighbours.
    ///
    /// Why it exists: the card stays above every window so that a question is never lost, which also
    /// kept it over the page the user was reading; the page had no room beside it for the card to
    /// step aside to. Called by the explainer's panel on every click in it; {@link HUD.raiseAsk}
    /// undoes it.
    func tuckAsk() {
        guard !askID.isEmpty, askPanel.isVisible, !askTucked, explainer.panel.isVisible,
              askPanel.frame.intersects(explainer.panel.frame) else { return }
        askTucked = true
        // Same level as the explainer, then right under it: above the app the explainer lies over
        askPanel.level = explainer.panel.level
        askPanel.order(.below, relativeTo: explainer.panel.windowNumber)
    }

    /// Put the card back above every window. Called when the card or its button on the bar is
    /// clicked, when a new question arrives, and when the explainer no longer covers the card.
    func raiseAsk() {
        guard askTucked else { return }
        askTucked = false
        askPanel.level = .statusBar
        if askPanel.isVisible { askPanel.orderFrontRegardless() }
    }

    /// The hand button on the bar, a toggle like the book and chat buttons. Not lit (the question
    /// waits out of sight: put away, behind the explainer, or with its page on another desktop), a
    /// press brings the card in front on the desktop the user is looking at. Lit, a press takes the
    /// card out of sight: one that was called here goes back to its page, any other is put away.
    @objc func showAsk() {
        guard !askID.isEmpty else { return }
        let stageElsewhere = askStage?.isOnAnotherSpace ?? false
        if askInSight {
            if askSummoned, stageElsewhere { askSummoned = false } else { askPutAway = true }
            updateAsk()
            return
        }
        askPutAway = false
        // Away from its page it stays here until the user reaches the page's desktop or presses again
        askSummoned = stageElsewhere
        raiseAsk()
        askPanel.orderFrontOnActiveSpace()
        updateAsk()
    }

    /// Lay the card out for the current question: one row when everything fits in
    /// {@link HUD.askMaxWidth}, else the question (wrapped) above a row of buttons.
    ///
    /// @returns The size the card needs.
    func layoutAsk() -> NSSize {
        // The question starts after the grip mark, and after its symbol when it has one
        let pad: CGFloat = 14, gap: CGFloat = 8, iconX: CGFloat = 34
        let textX: CGFloat = askIcon.isHidden ? iconX : iconX + 24
        let font = askLabel.font ?? NSFont.systemFont(ofSize: 15, weight: .bold)
        let text = askLabel.stringValue as NSString
        let lineHeight = ceil(font.ascender - font.descender + font.leading) + 2
        let lineWidth = ceil(text.size(withAttributes: [.font: font]).width) + 8
        // The answers differ by style, not by size: one height for every button of the card
        let buttonHeight = CapsuleButton.height
        let noWidth = max(askNo.intrinsicContentSize.width, 96)
        let okWidth = max(askOK.intrinsicContentSize.width, 84)
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
        askIcon.frame = NSRect(x: iconX, y: textFrame.maxY - lineHeight, width: 20, height: lineHeight)
        // Buttons from the right: the main answer, the other answer, then the feedback buttons
        var x = size.width - pad - okWidth
        askOK.frame = NSRect(x: x, y: buttonsY, width: okWidth, height: buttonHeight)
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
    /// slides back in while the pointer is on it. A card by the bar (never dragged) steps aside when
    /// it would cover the explainer; a card the user dropped stays where they put it, over the
    /// explainer too (a click in the page sends it behind: {@link HUD.tuckAsk}).
    func askFrame() -> NSRect {
        let bar = panel.frame
        let w = ceil(askSize.width), h = ceil(askSize.height)
        var origin = NSPoint(x: bar.midX - w / 2, y: bar.maxY + 8)
        guard let display = panel.screen ?? NSScreen.main else { return NSRect(x: origin.x.rounded(), y: origin.y.rounded(), width: w, height: h) }
        let screen = display.frame, visible = display.visibleFrame
        if origin.y + h > visible.maxY { origin.y = bar.minY - h - 8 }
        // True when the place is the user's own: they dragged the card there
        var userPlaced = false
        if let saved = try? String(contentsOfFile: askPositionPath, encoding: .utf8) {
            let parts = saved.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if parts.count == 2 {
                origin = NSPoint(x: parts[0], y: parts[1])
                userPlaced = true
            }
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
            // The user reads in the explainer: step aside to the nearest side that has room. Only a
            // card that follows the bar does: moving one the user just dropped would undo their drag
            let reading = explainer.panel.frame
            if !userPlaced, explainer.panel.isVisible, frame.intersects(reading) {
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
            let button = CapsuleButton(style: .secondary)
            button.target = self
            button.action = #selector(askExtraTapped(_:))
            button.label = "✓ " + label
            button.tag = index
            button.toolTip = "押すとエージェントに伝わります（確認は開いたままです）"
            // Sized for the pressed title ("✓ …"), so pressing it does not shift its neighbours
            button.widthAnchor.constraint(equalToConstant: button.intrinsicContentSize.width).isActive = true
            button.heightAnchor.constraint(equalToConstant: CapsuleButton.height).isActive = true
            button.label = label
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
        appendLine(inboxPath, ["text": "[HUD] フィードバック「\(label)」（確認「\(askQuestion)」は開いたままです）"])
        appendJournal("💬 フィードバック「\(label)」")
        notePending(label, route: .message)
        feedbackPressed(sender)
        // Show that it was sent, then let it be pressed again later ("still reading")
        (sender as? CapsuleButton)?.label = "✓ " + label
        sender.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self, weak sender] in
            guard let self, let sender, self.askExtraLabels.indices.contains(sender.tag),
                  self.askExtraLabels[sender.tag] == label else { return }
            (sender as? CapsuleButton)?.label = label
            sender.isEnabled = true
        }
    }

    func answerAsk(_ answer: String) {
        guard !askID.isEmpty else { return }
        // While the card and what it was about are still on screen
        if answer == "ok" { celebrateClear() }
        askOK.isBreathing = false
        try? "\(askID) \(answer)".write(toFile: askAnswerPath, atomically: true, encoding: .utf8)
        // Until the agent reacts, the bar shows that the press is on its way and when it arrived
        notePending(answer == "ok" ? askOK.attributedTitle.string : askNo.title, route: askWaiterAlive() ? .answer : .message)
        // Nobody is waiting (the agent's bounded wait ended and its turn is over): deliver the answer
        // as a message, the same way the mirror's message box does, so the click is never lost
        if !askWaiterAlive() {
            let label = answer == "ok" ? askOK.attributedTitle.string : askNo.title
            let question = askQuestion
            appendLine(inboxPath, ["text": "[HUD] \(question) → 「\(label)」を押しました"])
            appendJournal("  → 「\(label)」（待ち受けが無かったので、メッセージで届けた）")
            if isStopOn() { setStop(false) }
        }
        try? FileManager.default.removeItem(atPath: askPath)
        askPanel.orderOut(nil)
        askID = ""
        raiseAsk()
        setAskButton(shown: false)
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
