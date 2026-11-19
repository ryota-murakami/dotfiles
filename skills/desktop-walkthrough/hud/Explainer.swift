// Explainer panel of the HUD: explanations too long for the one-line bar (Markdown text, tables,
// diagrams, code). `dw explain <file.md>` writes each one as a page; this panel shows the newest
// and lets the reader page back through the earlier ones.
import AppKit
import WebKit

/// Pages written by `dw explain`: `pages/NNN.html`, their list in `index.json`, the libraries in `vendor/`.
let explainDir = "\(stateDir)/explain"
/// `{"current": N, "pages": [{"n", "title", "step", "file"}]}`, rewritten by `dw explain` for every page.
let explainIndexPath = "\(explainDir)/index.json"
/// Written when a page finished rendering: `{"page", "diagrams", "errors"}`. `dw explain` waits for it.
let explainRenderedPath = "\(explainDir)/rendered.json"
/// Explainer frame chosen by dragging ("x,y,width,height" in screen points).
let explainFramePath = "\(stateDir)/explain-frame"
/// `dw explain --hide` / `--show` leave "hide" or "show" here: the agent steps the panel aside while
/// the app behind it is the thing to watch, and brings it back. Applied once, then removed.
let explainVisibilityRequestPath = "\(explainDir)/visibility-request"
/// Border and highlight colour of the explainer, so it is not mistaken for the mirror.
let explainAccent = NSColor(calibratedRed: 0.36, green: 0.80, blue: 0.62, alpha: 1)

/// Panel that never takes keyboard focus.
///
/// Why it exists: the reader scrolls and clicks in the explainer while the agent drives another
/// app with shortcuts; a key window here would receive those keys instead of the app.
final class ReadingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Web view whose first click acts even though its panel is never the key window.
final class ReadingWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// One entry of `index.json`.
struct ExplainPage {
    let n: Int
    let title: String
    /// Section name (`dw step`) that was current when the page was written.
    let step: String
    /// Path of the page relative to {@link explainDir}.
    let file: String
}

/// The explainer: a floating page of Markdown, diagrams and code beside the app being demonstrated.
///
/// Why it exists: the status bar holds one line and the mirror shows the raw conversation; a design
/// decision, a table or a sequence diagram needs a page the reader can scroll and return to.
/// Created and owned by {@link HUD}; `dw explain` adds pages through `index.json`, and
/// {@link HUD.refresh} calls {@link Explainer.refresh} to pick them up.
final class Explainer: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    /// Schemes a link in a page may open in another app (a browser, an IDE).
    private static let externalSchemes: Set<String> = ["http", "https", "phpstorm", "jetbrains", "vscode", "cursor"]
    private static let headerHeight: CGFloat = 34

    let panel = ReadingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let root = NSView()
    private let grip = DragHandle()
    private let heading = NSTextField(labelWithString: "⠿ 解説")
    private let pageLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "")
    private let webView: ReadingWebView
    private lazy var listButton = IconButton(symbol: "list.bullet", label: "解説の一覧", pointSize: 11, target: self, action: #selector(listTapped))
    private lazy var prevButton = IconButton(symbol: "chevron.left", label: "前の解説", pointSize: 11, target: self, action: #selector(prevTapped))
    private lazy var nextButton = IconButton(symbol: "chevron.right", label: "次の解説", pointSize: 11, target: self, action: #selector(nextTapped))
    private lazy var zoomOut = IconButton(symbol: "minus", label: "文字を小さく", pointSize: 11, target: self, action: #selector(zoomOutTapped))
    private lazy var zoomIn = IconButton(symbol: "plus", label: "文字を大きく", pointSize: 11, target: self, action: #selector(zoomInTapped))
    private lazy var closeButton = IconButton(symbol: "xmark", label: "解説を閉じる", pointSize: 11, target: self, action: #selector(closeTapped))
    private let handles: [EdgeResizeHandle] = [
        EdgeResizeHandle([.left]), EdgeResizeHandle([.right]), EdgeResizeHandle([.top]), EdgeResizeHandle([.bottom]),
        EdgeResizeHandle([.left, .top]), EdgeResizeHandle([.right, .top]), EdgeResizeHandle([.left, .bottom]), EdgeResizeHandle([.right, .bottom]),
    ]
    private var pages: [ExplainPage] = []
    /// Number of the page on screen (0 = none).
    private var shown = 0
    /// `current` of the last index read: a change means `dw explain` added a page.
    private var announced = 0
    private var indexStamp: Date?

    override init() {
        let config = WKWebViewConfiguration()
        // Pages are local and self-contained: nothing is kept between launches
        config.websiteDataStore = .nonPersistent()
        webView = ReadingWebView(frame: .zero, configuration: config)
        super.init()
    }

    /// Build the panel. Called once by the HUD at launch.
    func attach() {
        guard let screen = NSScreen.main else { return }
        panel.setFrame(savedFrame() ?? defaultFrame(on: screen), display: false)
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = hudCollectionBehavior
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.98).cgColor
        root.layer?.borderColor = explainAccent.cgColor
        root.layer?.borderWidth = 2

        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "dw")
        // The page paints its own dark background; without this the view flashes white while loading
        if webView.responds(to: Selector(("_setDrawsBackground:"))) { webView.setValue(false, forKey: "drawsBackground") }
        applyZoom()

        heading.font = .systemFont(ofSize: 12, weight: .bold)
        heading.textColor = NSColor.white.withAlphaComponent(0.85)
        pageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        pageLabel.textColor = explainAccent
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        zoomLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        zoomLabel.alignment = .center
        grip.toolTip = "ドラッグで解説パネルを移動"
        // Invisible borders on every side and corner: drag any of them to resize
        for h in handles { h.onResize = { [weak self] r in self?.resize(to: r) } }

        for v in [grip, webView, listButton, prevButton, nextButton, zoomOut, zoomLabel, zoomIn, closeButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        // The labels sit inside the grip so a drag that starts on them moves the panel too
        for v in [heading, pageLabel, titleLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            grip.addSubview(v)
        }
        NSLayoutConstraint.activate([
            grip.topAnchor.constraint(equalTo: root.topAnchor),
            grip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            grip.trailingAnchor.constraint(equalTo: listButton.leadingAnchor, constant: -6),
            grip.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            heading.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            pageLabel.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            pageLabel.leadingAnchor.constraint(equalTo: heading.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: grip.trailingAnchor, constant: -4),

            closeButton.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            zoomIn.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            zoomIn.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),
            zoomLabel.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            zoomLabel.trailingAnchor.constraint(equalTo: zoomIn.leadingAnchor, constant: -2),
            zoomLabel.widthAnchor.constraint(equalToConstant: 42),
            zoomOut.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            zoomOut.trailingAnchor.constraint(equalTo: zoomLabel.leadingAnchor, constant: -2),
            nextButton.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            nextButton.trailingAnchor.constraint(equalTo: zoomOut.leadingAnchor, constant: -12),
            prevButton.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            prevButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -2),
            listButton.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            listButton.trailingAnchor.constraint(equalTo: prevButton.leadingAnchor, constant: -6),

            webView.topAnchor.constraint(equalTo: grip.bottomAnchor, constant: 2),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 2),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -2),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -2),
        ])
        for button in [listButton, prevButton, nextButton, zoomOut, zoomIn, closeButton] {
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        }
        pinEdgeHandles(handles, to: root)
        panel.contentView = root
        updateHeader()
    }

    // MARK: pages

    /// Pick up pages added by `dw explain` and keep the panel's visibility in step with the settings.
    /// Called by the HUD on every refresh tick.
    func refresh() {
        if let request = try? String(contentsOfFile: explainVisibilityRequestPath, encoding: .utf8) {
            try? FileManager.default.removeItem(atPath: explainVisibilityRequestPath)
            settings.set("explain.visible", request.trimmingCharacters(in: .whitespacesAndNewlines) == "hide" ? 0 : 1)
        }
        let stamp = mtime(explainIndexPath)
        if stamp != indexStamp {
            indexStamp = stamp
            let current = readIndex()
            if current != announced {
                // A new page: show it even if the reader had closed the panel or was on an older page
                announced = current
                if current > 0 { settings.set("explain.visible", 1) }
                show(current)
            } else if shown == current {
                // The page on screen was rewritten in place (`dw explain --replace`)
                show(current)
            }
            updateHeader()
        }
        updateVisibility()
    }

    /// Load `index.json` into {@link pages}.
    ///
    /// @returns Its `current` page number (0 when there is no page).
    private func readIndex() -> Int {
        guard let data = FileManager.default.contents(atPath: explainIndexPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            pages = []
            return 0
        }
        pages = ((object["pages"] as? [[String: Any]]) ?? []).compactMap { entry in
            guard let n = (entry["n"] as? NSNumber)?.intValue, let file = entry["file"] as? String else { return nil }
            return ExplainPage(n: n, title: entry["title"] as? String ?? "", step: entry["step"] as? String ?? "", file: file)
        }
        return (object["current"] as? NSNumber)?.intValue ?? 0
    }

    /// Put page `n` on screen; an unknown number (the pages were cleared) empties the panel.
    private func show(_ n: Int) {
        guard let page = pages.first(where: { $0.n == n }) else {
            shown = 0
            webView.loadHTMLString("", baseURL: nil)
            updateHeader()
            return
        }
        shown = n
        // Read access to the whole folder: pages load the shared libraries from `vendor/`
        webView.loadFileURL(URL(fileURLWithPath: "\(explainDir)/\(page.file)"), allowingReadAccessTo: URL(fileURLWithPath: explainDir, isDirectory: true))
        updateHeader()
    }

    private func updateHeader() {
        let position = pages.firstIndex { $0.n == shown }
        let page = position.map { pages[$0] }
        pageLabel.stringValue = position.map { "\($0 + 1)/\(pages.count)" } ?? ""
        titleLabel.stringValue = page.map { $0.step.isEmpty ? $0.title : "【\($0.step)】\($0.title)" } ?? ""
        prevButton.isEnabled = (position ?? 0) > 0
        nextButton.isEnabled = position.map { $0 < pages.count - 1 } ?? false
        listButton.isEnabled = !pages.isEmpty
    }

    /// Show the panel when it is switched on and has a page, except while `dw click-xy` needs it out of the way.
    func updateVisibility() {
        let wanted = settings.isOn("explain.visible") && shown > 0 && !exists(mirrorSuspendPath)
        if wanted, !panel.isVisible { panel.orderFrontRegardless() }
        if !wanted, panel.isVisible { panel.orderOut(nil) }
    }

    func applyZoom() {
        webView.pageZoom = CGFloat(settings.value("explain.zoom"))
        zoomLabel.stringValue = percentText(settings.value("explain.zoom"))
    }

    // MARK: header controls

    @objc private func prevTapped() { step(by: -1) }
    @objc private func nextTapped() { step(by: 1) }

    private func step(by offset: Int) {
        guard let position = pages.firstIndex(where: { $0.n == shown }), pages.indices.contains(position + offset) else { return }
        show(pages[position + offset].n)
    }

    /// The list button: every page by number and title, the one on screen ticked.
    @objc private func listTapped() {
        let menu = NSMenu()
        for page in pages {
            let title = "\(page.n). " + (page.step.isEmpty ? "" : "【\(page.step)】") + page.title
            let item = NSMenuItem(title: title, action: #selector(pagePicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = page.n
            item.state = page.n == shown ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: listButton.bounds.height + 4), in: listButton)
    }

    @objc private func pagePicked(_ item: NSMenuItem) { show(item.tag) }
    @objc private func zoomInTapped() { settings.set("explain.zoom", settings.value("explain.zoom") + 0.1) }
    @objc private func zoomOutTapped() { settings.set("explain.zoom", settings.value("explain.zoom") - 0.1) }
    @objc private func closeTapped() { settings.set("explain.visible", 0) }

    // MARK: frame

    /// Right-hand 42% of the screen, full height: beside the app being demonstrated.
    private func defaultFrame(on screen: NSScreen) -> NSRect {
        let v = screen.visibleFrame
        let w = min(max(560, v.width * 0.42), v.width)
        return NSRect(x: v.maxX - w, y: v.minY, width: w, height: v.height)
    }

    /// The frame saved by the last drag, if it still fits on a connected screen.
    private func savedFrame() -> NSRect? {
        guard let s = try? String(contentsOfFile: explainFramePath, encoding: .utf8) else { return nil }
        let v = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard v.count == 4 else { return nil }
        let r = NSRect(x: v[0], y: v[1], width: v[2], height: v[3])
        return NSScreen.screens.contains { $0.frame.intersects(r) } ? r : nil
    }

    private func saveFrame() {
        let r = panel.frame
        try? "\(r.minX),\(r.minY),\(r.width),\(r.height)".write(toFile: explainFramePath, atomically: true, encoding: .utf8)
    }

    /// Edge or corner drag: apply the dragged frame with a usable minimum size, inside the visible screen area.
    private func resize(to proposed: NSRect) {
        var r = proposed
        let old = panel.frame
        if r.width < 380 { if r.minX != old.minX { r.origin.x = old.maxX - 380 }; r.size.width = 380 }
        if r.height < 240 { if r.minY != old.minY { r.origin.y = old.maxY - 240 }; r.size.height = 240 }
        if let f = (panel.screen ?? NSScreen.main)?.visibleFrame { r = r.intersection(f).isNull ? old : r.intersection(f) }
        panel.setFrame(r, display: true)
        saveFrame()
    }

    /// Settings → explainer → reset: back to the default place and size.
    func resetFrame() {
        guard let screen = NSScreen.main else { return }
        try? FileManager.default.removeItem(atPath: explainFramePath)
        panel.setFrame(defaultFrame(on: screen), display: true)
    }

    /// Put the panel at a frame chosen by `dw stage` and remember it like a drag.
    func place(_ frame: NSRect) {
        panel.setFrame(frame, display: true)
        saveFrame()
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }

    // MARK: web view

    /// Pages are local files; a clicked link to anything else opens in the app that handles it.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "about" || (url.isFileURL && url.path.hasPrefix(explainDir)) { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated, let scheme = url.scheme, Self.externalSchemes.contains(scheme) {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    /// Messages from the page script: its render report, and text for the clipboard (the panel never
    /// becomes key, so Command-C cannot reach it).
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "rendered":
            if let data = try? JSONSerialization.data(withJSONObject: body) {
                try? data.write(to: URL(fileURLWithPath: explainRenderedPath), options: .atomic)
            }
        case "copy":
            guard let text = body["text"] as? String else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        default:
            break
        }
    }
}
