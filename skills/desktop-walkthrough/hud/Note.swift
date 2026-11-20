// Note popup of the HUD: a short explanation shown right next to the thing it explains (the selected
// lines of code, a button, a table row). The one-line bar is too short for it and the explainer page
// is too far from the code; `dw note` puts a few sentences where the reader is already looking.
import AppKit
import WebKit

/// `dw note` writes `{"id", "title", "width", "anchor": [x, y, width, height] | null}` here. The anchor
/// is the screen rectangle being explained, in points from the top-left corner (what accessibility
/// bounds and screenshots give). `dw note --clear` removes the file.
let notePath = "\(explainDir)/note.json"
/// The note rendered as a page (from `explainer/note.html`), beside the explainer's `vendor/` libraries.
let notePagePath = "\(explainDir)/note.html"

/// The note popup: Markdown in a small card that floats beside its anchor, placed like a tooltip.
///
/// Why it exists: explaining selected code in the status bar meant one or two truncated lines, and
/// the explainer page hides behind the app while the code is read. Created and owned by {@link HUD};
/// {@link HUD.refresh} calls {@link NotePopup.refresh} on every tick to pick up what `dw note` wrote.
final class NotePopup: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    private static let headerHeight: CGFloat = 32

    let panel = ReadingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let root = NSView()
    private let grip = DragHandle()
    private let titleIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private lazy var closeButton = IconButton(symbol: "xmark", label: "メモを閉じる", pointSize: 12, target: self, action: #selector(closeTapped))
    private let webView: ReadingWebView
    /// Modification time of the note file last loaded (nil = no note).
    private var stamp: Date?
    private var noteID = ""
    /// What the note explains, in Cocoa screen coordinates (nil = nothing in particular).
    private var anchor: NSRect?
    private var width: CGFloat = 460
    /// Height of the rendered text in points; 0 until the page has reported it.
    private var contentHeight: CGFloat = 0
    /// True after the user closed this note: it stays closed until the next one.
    private var dismissed = false
    /// Origin the HUD last gave the popup: a different origin later means the user dragged it.
    private var placedOrigin: NSPoint?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = ReadingWebView(frame: .zero, configuration: config)
        super.init()
    }

    /// Build the popup. Called once by the HUD at launch.
    func attach() {
        panel.delegate = self
        // A tooltip: above the app it points into, whichever app that is, on that app's desktop only
        panel.level = .floating
        panel.collectionBehavior = stageCollectionBehavior
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        root.wantsLayer = true
        root.layer?.cornerRadius = surfaceCornerRadius
        root.layer?.masksToBounds = true
        // Opaque: the note lies over code, and code under text makes both hard to read
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor
        applyLook()

        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "dw")
        if webView.responds(to: Selector(("_setDrawsBackground:"))) { webView.setValue(false, forKey: "drawsBackground") }

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = noteAccent
        titleIcon.image = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil)
        titleIcon.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        titleIcon.contentTintColor = noteAccent
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        grip.toolTip = "ドラッグでメモを移動"

        for v in [grip, webView, closeButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        for v in [titleIcon, titleLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            grip.addSubview(v)
        }
        NSLayoutConstraint.activate([
            grip.topAnchor.constraint(equalTo: root.topAnchor),
            grip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            grip.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            grip.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            titleIcon.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            titleIcon.leadingAnchor.constraint(equalTo: grip.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: titleIcon.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: grip.trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
            webView.topAnchor.constraint(equalTo: grip.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 2),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -2),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -2),
        ])
        panel.contentView = root
    }

    /// Outline of the popup: its own yellow, stronger with "Increase contrast". Called at launch and
    /// when a display setting changes.
    func applyLook() {
        root.layer?.borderColor = noteAccent.hudCG
        root.layer?.borderWidth = DisplayOptions.increaseContrast ? 2.5 : 1.5
    }

    /// Show the note `dw note` wrote, or hide the popup when the note is gone. Called on every refresh tick.
    func refresh() {
        guard let now = mtime(notePath) else {
            stamp = nil
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        if now != stamp {
            stamp = now
            load()
        }
        // A new note is ordered out until its page reports a height, so it appears on the desktop the
        // user is looking at when `dw note` runs: the one of the app it points into
        let wanted = contentHeight > 0 && !dismissed
        if wanted, !panel.isVisible { panel.orderFrontRegardless() }
        if !wanted, panel.isVisible { panel.orderOut(nil) }
        // Out of the way while `dw click-xy` clicks: a floating card would swallow a click that lands on it
        panel.setConcealed(exists(mirrorSuspendPath))
    }

    /// Read the note file and load its page; the popup appears once the page has reported its height.
    private func load() {
        guard let data = FileManager.default.contents(atPath: notePath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        noteID = "\(object["id"] ?? "")"
        let title = object["title"] as? String ?? ""
        titleLabel.stringValue = title.isEmpty ? "メモ" : title
        width = min(max(CGFloat((object["width"] as? NSNumber)?.doubleValue ?? 460), 280), 900)
        anchor = nil
        if let v = (object["anchor"] as? [NSNumber])?.map({ CGFloat($0.doubleValue) }), v.count == 4, let primary = NSScreen.screens.first {
            // Accessibility and screenshots count from the top left; AppKit from the bottom left
            anchor = NSRect(x: v[0], y: primary.frame.height - v[1] - v[3], width: v[2], height: v[3])
        }
        dismissed = false
        placedOrigin = nil
        contentHeight = 0
        webView.pageZoom = CGFloat(settings.value("explain.zoom"))
        // The page is laid out at the popup's width before it is shown, so the height it reports is the real one
        panel.setFrame(NSRect(origin: panel.frame.origin, size: NSSize(width: width, height: 240)), display: false)
        webView.loadFileURL(URL(fileURLWithPath: notePagePath), allowingReadAccessTo: URL(fileURLWithPath: explainDir, isDirectory: true))
    }

    /// Size the popup to its text and put it beside the anchor, on the first side with room.
    private func place() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = NSSize(width: width, height: min(Self.headerHeight + contentHeight + 4, max(180, visible.height * 0.62)))
        var frame: NSRect
        if let placed = placedOrigin, abs(panel.frame.minX - placed.x) > 1 || abs(panel.frame.minY - placed.y) > 1 {
            // The user dragged it: keep its top-left corner where they put it
            frame = NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height)
        } else if let anchor {
            // Beside the code first (nothing is covered), else under it, else over it
            frame = popupFrame(size: size, anchor: anchor, visible: visible, sides: [.right, .below, .above, .left], gap: 10)
            placedOrigin = frame.origin
        } else {
            frame = NSRect(x: visible.maxX - size.width - 24, y: visible.minY + 24, width: size.width, height: size.height)
            placedOrigin = frame.origin
        }
        panel.setFrame(frame, display: true)
    }

    @objc private func closeTapped() {
        dismissed = true
        panel.orderOut(nil)
    }

    /// Links in a note open in the app that handles them; the page itself is a local file.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "about" || (url.isFileURL && url.path.hasPrefix(explainDir)) { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated, let scheme = url.scheme, ["http", "https"].contains(scheme) {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    /// The page reports the height of its text (CSS pixels) whenever it changes.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], body["type"] as? String == "size",
              "\(body["id"] ?? "")" == noteID, let height = (body["height"] as? NSNumber)?.doubleValue else { return }
        let first = contentHeight == 0
        apply(cssHeight: CGFloat(height))
        // A page measured before the popup was on screen can report too little (it is laid out again
        // once the zoom applies, and a hidden page does not always say so): ask again when it shows
        if first {
            let id = noteID
            for delay in [0.25, 0.8] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.remeasure(id) }
            }
        }
    }

    /// Ask the page for its height now that it is on screen; a note that was replaced meanwhile is left alone.
    private func remeasure(_ id: String) {
        guard id == noteID else { return }
        webView.evaluateJavaScript("Math.ceil(document.body.getBoundingClientRect().height)") { [weak self] value, _ in
            guard let self, id == self.noteID, let height = (value as? NSNumber)?.doubleValue else { return }
            self.apply(cssHeight: CGFloat(height))
        }
    }

    /// Take a new text height: resize and place the popup, and tell `dw note` where it is.
    private func apply(cssHeight: CGFloat) {
        let points = cssHeight * webView.pageZoom
        guard abs(points - contentHeight) > 1 else { return }
        contentHeight = points
        place()
        let f = panel.frame
        let report: [String: Any] = ["id": noteID, "frame": [f.minX, f.minY, f.width, f.height]]
        if let data = try? JSONSerialization.data(withJSONObject: report) {
            try? data.write(to: URL(fileURLWithPath: "\(explainDir)/note-shown.json"), options: .atomic)
        }
    }
}
