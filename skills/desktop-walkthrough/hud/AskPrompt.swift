// Approval prompt of the HUD: the small panel above the bar for one-click answers (`dw ask`,
// `dw wait-user`). Methods of the HUD class; its stored views are in HUD.swift.
import AppKit

extension HUD {
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
}
