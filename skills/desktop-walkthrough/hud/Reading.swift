// Reading feedback of the HUD: what the reader has read (blocks of a page marked as read, notes
// understood, pages cleared), kept across pages and restarts, and what the HUD answers with: a
// sound, the count in the explainer's header, an achievement, the banner of a cleared page.
// The marks themselves are drawn by the page (explainer/page.html) and the note (explainer/note.html).
import AppKit

/// The reading progress of the walkthrough:
/// `{"pages": {"13": {"read": [0, 1], "total": 9, "focus": 2, "cleared": false}}, "understood": ["<note id>"],
/// "notes": 3, "achievements": ["first-step"], "points": 5}`.
/// Written by the HUD on every change, with a copy in the record folder. `dw start` removes it (a new
/// walkthrough), `dw resume` puts the record's copy back, `dw explain --progress` prints it for the agent.
let progressPath = "\(explainDir)/progress.json"

/// What was read of one page.
struct PageProgress {
    /// Indexes of the blocks marked as read (in the order the page lists its blocks).
    var read: Set<Int> = []
    var total = 0
    /// The block the frame rests on; -1 once every block is read.
    var focus = 0
    /// True once 次へ was pressed with this page in front.
    var cleared = false
    var isComplete: Bool { total > 0 && read.count >= total }
}

/// The reading progress, loaded from and saved to {@link progressPath}.
///
/// Why it exists: the page forgets its marks whenever it is loaded again (paging back, a new HUD
/// build), and achievements count across pages. Created and owned by {@link HUD}; changed only
/// through the methods here, each of which saves.
final class ReadingStore {
    private(set) var pages: [Int: PageProgress] = [:]
    /// Ids of the notes understood, newest last (the last 40: a note is shown once).
    private(set) var understood: [String] = []
    /// How many notes were understood so far.
    private(set) var notes = 0
    private(set) var achievements: [String] = []
    private(set) var points = 0

    init() {
        guard let data = FileManager.default.contents(atPath: progressPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        for (key, value) in (object["pages"] as? [String: [String: Any]]) ?? [:] {
            guard let n = Int(key) else { continue }
            var page = PageProgress()
            page.read = Set(((value["read"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.intValue })
            page.total = (value["total"] as? NSNumber)?.intValue ?? 0
            page.focus = (value["focus"] as? NSNumber)?.intValue ?? 0
            page.cleared = (value["cleared"] as? Bool) ?? false
            pages[n] = page
        }
        understood = (object["understood"] as? [String]) ?? []
        notes = (object["notes"] as? NSNumber)?.intValue ?? 0
        achievements = (object["achievements"] as? [String]) ?? []
        points = (object["points"] as? NSNumber)?.intValue ?? 0
    }

    /// Pages of which every block is read.
    var pagesRead: Int { pages.values.filter { $0.isComplete }.count }

    func has(_ achievement: String) -> Bool { achievements.contains(achievement) }
    func isUnderstood(_ note: String) -> Bool { understood.contains(note) }

    /// Change what is known about a page.
    func update(page: Int, _ change: (inout PageProgress) -> Void) {
        var progress = pages[page] ?? PageProgress()
        change(&progress)
        pages[page] = progress
        save()
    }

    /// Remember a note as understood.
    ///
    /// @returns False when it already was.
    func understand(_ note: String) -> Bool {
        guard !note.isEmpty, !understood.contains(note) else { return false }
        understood = Array((understood + [note]).suffix(40))
        notes += 1
        save()
        return true
    }

    /// Record an achievement.
    ///
    /// @returns False when it was unlocked before.
    func unlock(_ achievement: String, points earned: Int) -> Bool {
        guard !achievements.contains(achievement) else { return false }
        achievements.append(achievement)
        points += earned
        save()
        return true
    }

    private func save() {
        var list: [String: Any] = [:]
        for (n, page) in pages {
            list[String(n)] = ["read": page.read.sorted(), "total": page.total, "focus": page.focus, "cleared": page.cleared] as [String: Any]
        }
        let object: [String: Any] = ["pages": list, "understood": understood, "notes": notes, "achievements": achievements, "points": points]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: progressPath), options: .atomic)
        // The record keeps a copy: a resumed walkthrough gets its marks and achievements back
        if let dir = (try? String(contentsOfFile: recordDirPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines),
           !dir.isEmpty, exists(dir) {
            try? data.write(to: URL(fileURLWithPath: "\(dir)/progress.json"), options: .atomic)
        }
    }
}

extension HUD {
    // MARK: reading feedback

    /// Connect the page, the note and the prompt card to the reading feedback. Called once at launch.
    func startReading() {
        explainer.onReading = { [weak self] body in self?.readingChanged(body) }
        explainer.onPageLoaded = { [weak self] page in self?.restoreReading(page) }
        notePopup.onUnderstood = { [weak self] id, title in self?.noteUnderstood(id: id, title: title) }
        notePopup.onLoaded = { [weak self] id in self?.restoreNote(id) }
    }

    /// Give a page that was just loaded what is kept for it: the blocks read, where the frame was,
    /// and the options. A page built before the marks existed has nothing to restore into.
    func restoreReading(_ page: Int) {
        guard page > 0 else { return }
        let saved = reading.pages[page] ?? PageProgress()
        let state: [String: Any] = ["read": saved.read.sorted(), "focus": saved.focus,
                                    "enabled": settings.isOn("reading.marks"), "dim": settings.isOn("reading.dim")]
        guard let data = try? JSONSerialization.data(withJSONObject: state), let json = String(data: data, encoding: .utf8) else { return }
        if !settings.isOn("reading.marks") { explainer.setProgress(read: 0, total: 0, animated: false) }
        explainer.evaluate("window.dwReading && dwReading.restore(\(json))")
    }

    /// Give the note that was just loaded its "understood" state and whether the button shows at all.
    func restoreNote(_ id: String) {
        let done = reading.isUnderstood(id)
        notePopup.restore(done: done, enabled: settings.isOn("reading.marks"))
    }

    /// The "reading.marks" or "reading.dim" setting changed: the open page and note follow at once.
    func applyReadingOptions() {
        restoreReading(explainer.shown)
        restoreNote(notePopup.currentID)
    }

    /// The page reported a change of its marks (`{type: "reading", event, page, total, read, focus}`).
    ///
    /// The HUD keeps the state, shows the count in the header and answers with the sound of the
    /// event: a mark climbs a scale that reaches its top with the last block of the page.
    func readingChanged(_ body: [String: Any]) {
        func int(_ key: String) -> Int? { (body[key] as? NSNumber)?.intValue }
        guard settings.isOn("reading.marks"), let page = int("page"), page == explainer.shown,
              let event = body["event"] as? String, let total = int("total"), total > 0 else { return }
        let read = Set(((body["read"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.intValue })
        let wasComplete = reading.pages[page]?.isComplete ?? false
        reading.update(page: page) { progress in
            progress.read = read
            progress.total = total
            progress.focus = int("focus") ?? -1
        }
        explainer.setProgress(read: read.count, total: total, animated: event != "init")
        switch event {
        case "mark":
            sounds.play("mark")
            marked(page: page, read: read.count, total: total, wasComplete: wasComplete)
        case "unmark": sounds.play("unmark")
        // The frame moved without a mark: the sound of a cursor moving in a menu
        case "focus": sounds.play("tick", gain: 0.8)
        default: break
        }
    }

    /// What a mark led to: the first step, the half of a long page, a page read to its end.
    private func marked(page: Int, read: Int, total: Int, wasComplete: Bool) {
        if !reading.has("first-step") {
            unlock("first-step", title: "はじめの一歩", desc: "最初のまとまりを読んだ", points: 5)
        }
        if read >= total, !wasComplete {
            // After the mark's own two notes
            sounds.play("complete", after: 0.42)
            appendJournal("✓ 解説 \(page) を全部読んだ（\(read)/\(total)）")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in self?.sparkChip() }
            guard !reading.has("read:\(page)") else { return }
            // Every third, fifth, tenth… page read is the bigger achievement, in place of the plain one
            let count = reading.pagesRead
            if [3, 5, 10, 20, 30, 50].contains(count) {
                _ = reading.unlock("read:\(page)", points: 0)
                unlock("pages-\(count)", title: "\(count) ページ読破", desc: "解説 \(page) で \(count) ページ目", points: count >= 10 ? 100 : (count >= 5 ? 50 : 30))
            } else {
                unlock("read:\(page)", title: "読破", desc: "解説 \(page) を全部読んだ", points: 20)
            }
        } else if total >= 8, read == (total + 1) / 2 {
            unlock("half:\(page)", title: "折り返し", desc: "解説 \(page) を半分まで読んだ", points: 10)
        }
    }

    /// Sparks from the count in the explainer's header: the page is read to its end.
    private func sparkChip() {
        guard let centre = explainer.chipCentre(), let screen = explainer.panel.screen ?? NSScreen.main,
              explainer.panel.isVisible, explainer.panel.isOnActiveSpace else { return }
        let at = effects.point(centre, on: screen)
        effects.play("burst", ["x": at.x, "y": at.y, "count": 10, "colors": ["#5ccc9e", "#ffffff", "#a6e6c9"], "speed": 150, "life": 600, "size": 3.5], on: screen)
    }

    /// "理解した" was pressed on the note: once per note, a sound, a light on the note, the count, then the note goes.
    func noteUnderstood(id: String, title: String) {
        guard settings.isOn("reading.marks"), reading.understand(id) else { return }
        sounds.play("note")
        notePopup.showUnderstood(animated: true)
        appendJournal("✓ メモ「\(title)」を理解した")
        if notePopup.panel.isVisible, let screen = notePopup.panel.screen ?? NSScreen.main {
            // From the button, at the lower right of the note
            let frame = notePopup.panel.frame
            let at = effects.point(NSPoint(x: frame.maxX - 60, y: frame.minY + 26), on: screen)
            effects.play("ring", ["x": at.x, "y": at.y, "color": "#ffc74d", "to": 60, "ms": 520], on: screen)
            effects.play("burst", ["x": at.x, "y": at.y, "count": 8, "colors": ["#ffc74d", "#fff3c4"], "speed": 140, "life": 550, "size": 3.5], on: screen)
        }
        // The note has done its job: it goes once its light has played, out of the way of the code
        notePopup.dismissUnderstood(after: 0.8)
        let count = reading.notes
        if count == 1 {
            unlock("first-note", title: "なるほど", desc: "はじめてメモを理解した", points: 15)
        } else if [5, 10, 20, 30, 50].contains(count) {
            unlock("notes-\(count)", title: "メモ \(count) 個", desc: "\(count) 個のメモを理解した", points: count >= 10 ? 50 : 30)
        }
    }

    /// Unlock an achievement once: it opens under the status bar, and the record's journal keeps it.
    /// It has no sound of its own: what led to it (a mark, a page read, a note) already sounded.
    private func unlock(_ id: String, title: String, desc: String, points: Int) {
        guard reading.unlock(id, points: points) else { return }
        appendJournal("🏆 実績「\(title)」\(desc)（\(points) G）")
        guard let screen = panel.screen ?? NSScreen.main else { return }
        // Under the bar, or over it when the bar lies at the bottom of the screen
        let bar = panel.frame
        let below = bar.minY - 8 - 52 >= screen.frame.minY + 40
        let top = effects.point(NSPoint(x: bar.midX, y: below ? bar.minY - 8 : bar.maxY + 8 + 52), on: screen)
        effects.play("toast", ["cx": top.x, "top": top.y, "title": title, "desc": desc, "points": points], on: screen)
    }

    /// 次へ: the first answer of a hand-over question clears what the question was about.
    ///
    /// A page in front gets the banner across it and the fanfare; a note beside code gets the small
    /// banner and the shorter sound (there are many of them in a code tour); a step of the user's own
    /// gets one quiet sound. An approval (`dw ask`) is not a stage: nothing happens. Called by
    /// {@link HUD.answerAsk} before the card goes.
    func celebrateClear() {
        guard askIconText == "🙋" else { return }
        let pageInFront = explainer.shown > 0 && explainer.panel.isVisible && explainer.panel.isOnActiveSpace && !explainer.isCovered
        if pageInFront, let screen = explainer.panel.screen ?? NSScreen.main {
            let page = explainer.shown
            var stats: [String] = []
            if settings.isOn("reading.marks"), let progress = reading.pages[page], progress.total > 0 {
                stats.append("✓ 読んだまとまり \(progress.read.count)/\(progress.total)")
            }
            if notePopup.panel.isVisible, reading.isUnderstood(notePopup.currentID) { stats.append("💡 メモ 理解した") }
            sounds.play("next")
            var payload = effects.rect(explainer.contentFrame, on: screen)
            payload["kicker"] = "QUEST COMPLETE"
            payload["title"] = "解説 \(page)　\(explainer.title(of: page))"
            payload["stats"] = stats
            payload["radius"] = surfaceCornerRadius
            effects.play("banner", payload, on: screen)
            reading.update(page: page) { $0.cleared = true }
        } else if notePopup.panel.isVisible, notePopup.panel.isOnActiveSpace, let screen = notePopup.panel.screen ?? NSScreen.main {
            sounds.play("complete")
            var payload = effects.rect(notePopup.panel.frame, on: screen)
            payload["compact"] = true
            payload["kicker"] = "CLEAR"
            payload["title"] = notePopup.title
            payload["stats"] = reading.isUnderstood(notePopup.currentID) ? ["💡 理解した"] : []
            payload["radius"] = surfaceCornerRadius
            effects.play("banner", payload, on: screen)
        } else {
            sounds.play("mark")
        }
    }

    /// A feedback button of the prompt card was pressed ("読んでいます"): the tick of a cursor, and a ring from the button.
    func feedbackPressed(_ button: NSView) {
        sounds.play("tick")
        guard let window = button.window, let screen = window.screen ?? NSScreen.main else { return }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let at = effects.point(NSPoint(x: frame.midX, y: frame.midY), on: screen)
        effects.play("ring", ["x": at.x, "y": at.y, "color": "#ff9f0a", "from": 20, "to": 70, "ms": 380, "width": 1.5], on: screen)
    }

    /// The main answer glows while the page in front is read to its end and a hand-over question
    /// waits: the next move is there. Called on every refresh tick by {@link HUD.updateAsk}.
    func updateAskBreathing() {
        let page = explainer.shown
        let ready = !askID.isEmpty && askIconText == "🙋" && settings.isOn("reading.marks")
            && (reading.pages[page]?.isComplete ?? false)
            && explainer.panel.isVisible && explainer.panel.isOnActiveSpace && !explainer.isCovered
        if askOK.isBreathing != ready { askOK.isBreathing = ready }
    }
}
