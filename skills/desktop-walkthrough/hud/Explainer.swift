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
/// `dw explain --hide` / `--show` / `--back` leave "hide", "show" or "back" here: the agent steps the
/// panel aside while the app is the thing to watch (hidden, or behind the app's window like any
/// other window), and brings it back. Applied once, then removed.
let explainVisibilityRequestPath = "\(explainDir)/visibility-request"

/// Panel that never takes keyboard focus, and still comes forward when clicked.
///
/// Why it exists: the reader scrolls and clicks in the explainer while the agent drives another
/// app with shortcuts; a key window here would receive those keys instead of the app. A window
/// that cannot become key is not raised by a click, so the panel raises itself: it stacks with the
/// other apps' windows like an ordinary window (click it and it is in front, click the app and the
/// app is in front).
final class ReadingPanel: NSPanel {
    /// Called on every click in the panel, after it came forward. The HUD sends the prompt card
    /// behind the panel here ({@link HUD.tuckAsk}).
    var onMouseDown: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            orderFrontRegardless()
            onMouseDown?()
        }
        super.sendEvent(event)
    }
}

/// Web view whose first click acts even though its panel is never the key window.
final class ReadingWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Added to every page of a reading surface: the page says what is selected (`{type: "selection",
/// text}` on the `dw` channel) whenever that changes. Added by the HUD and not written in the page
/// templates, so pages rendered by an older version report it too.
private let selectionReportScript = """
(() => {
  let timer = 0;
  const report = () => {
    try { window.webkit.messageHandlers.dw.postMessage({ type: 'selection', text: String(window.getSelection()) }); } catch (_) { /* no HUD */ }
  };
  document.addEventListener('selectionchange', () => { clearTimeout(timer); timer = setTimeout(report, 60); });
})();
"""

/// What is selected in the page of a reading surface (explainer, note), and Command-C for it.
///
/// Why it exists: a reading panel never takes the keyboard ({@link ReadingPanel}), so Command-C goes
/// to the app in front and never reaches the page; only the page's context menu could copy. The
/// page reports its selection, and while that selection is what the reader is working with (their
/// last click was in this panel and the pointer is on it), the HUD takes Command-C as a hot key and
/// copies here ({@link HUD.updateCopyHotKey}). Created by the surface that owns the web view, which
/// passes on the page's "selection" messages.
final class PageSelection {
    let panel: NSPanel
    private weak var webView: WKWebView?
    /// The selected text as the page last reported it ("" = nothing is selected).
    private var text = ""
    /// False once the reader clicked anywhere else: the selection is still drawn, and Command-C
    /// belongs to the app they went to.
    private var isCurrent = false
    /// Called when {@link PageSelection.canCopy} may have changed.
    var onChange: (() -> Void)?

    /// Must be created before the web view loads its first page: the report script is added to pages loaded afterwards.
    init(panel: NSPanel, webView: WKWebView) {
        self.panel = panel
        self.webView = webView
        webView.configuration.userContentController.addUserScript(
            WKUserScript(source: selectionReportScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    /// True while Command-C should copy from this page: text is selected, the reader's last click was
    /// here, and the pointer is on the panel (not on a window lying over it).
    var canCopy: Bool {
        guard isCurrent, !text.isEmpty, panel.isVisible, panel.alphaValue > 0 else { return false }
        return NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == panel.windowNumber
    }

    /// The page reported its selection. Only the reader changes it, so it is theirs to copy now.
    func update(text reported: String) {
        text = reported
        isCurrent = !reported.isEmpty
        onChange?()
    }

    /// Another page was loaded: nothing is selected in it.
    func reset() {
        text = ""
        isCurrent = false
        onChange?()
    }

    /// A click landed in this panel (the selection is being worked with) or anywhere else (it is left behind).
    func clicked(inside: Bool) {
        isCurrent = inside
        onChange?()
    }

    /// Put the selection on the clipboard. Called for Command-C while {@link PageSelection.canCopy}.
    func copy() {
        guard !text.isEmpty, let webView else { return }
        let board = NSPasteboard.general
        let before = board.changeCount
        let plain = text
        // The page's own Copy, as its context menu does it: formatted text and plain text
        NSApp.sendAction(#selector(NSText.copy(_:)), to: webView, from: nil)
        // The page copies in its own process and may refuse a view that has no focus: the text it reported is the fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard board.changeCount == before else { return }
            board.clearContents()
            board.setString(plain, forType: .string)
        }
    }
}

extension HUD {
    /// The surfaces Command-C can copy from. The note first: it floats over the explainer.
    private var pageSelections: [PageSelection] { [notePopup.selection, explainer.selection] }

    /// Wire Command-C to the reading surfaces and watch where the reader clicks. Called once at launch.
    func startCopyShortcut() {
        copyHotKey.onPress = { [weak self] in self?.pageSelections.first { $0.canCopy }?.copy() }
        for selection in pageSelections { selection.onChange = { [weak self] in self?.updateCopyHotKey() } }
        // Every click, in the HUD or in another app: only the surface under it keeps its selection for Command-C
        copyClickWatcher.start(isInside: { _ in false }, onOutside: { [weak self] in
            guard let self else { return }
            let clicked = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
            for selection in self.pageSelections { selection.clicked(inside: selection.panel.windowNumber == clicked) }
        })
    }

    /// Take Command-C from the other apps only while it would copy here.
    ///
    /// Why it exists: a registered hot key is swallowed whichever app has the keyboard, so it is on
    /// only while a reading surface has a selection the reader is working with, under the pointer.
    /// Called as the pointer moves (every 30 ms) and when a selection or a click changes the answer.
    func updateCopyHotKey() {
        copyHotKey.setEnabled(pageSelections.contains { $0.canCopy })
    }
}

/// The count of blocks read on the page, in the explainer's header: "✓ 4/9", filled once all are read.
///
/// Why it exists: the page draws its own marks, but how far the reader is belongs where the page's
/// number and title are, in sight while the page scrolls. Owned by {@link Explainer}, which sets
/// it from what the page reports.
final class ReadChip: NSView {
    private let label = NSTextField(labelWithString: "")
    private var width: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let width = widthAnchor.constraint(equalToConstant: 0)
        self.width = width
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor), label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 20), width,
        ])
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Show `read` of `total`; a page without blocks (or with the marks switched off) shows no chip.
    func set(read: Int, total: Int, animated: Bool) {
        guard total > 0 else {
            isHidden = true
            width?.constant = 0
            return
        }
        let complete = read >= total
        label.stringValue = "✓ \(read)/\(total)"
        label.textColor = complete ? NSColor(calibratedRed: 0.05, green: 0.10, blue: 0.08, alpha: 1) : NSColor(calibratedRed: 0.65, green: 0.90, blue: 0.79, alpha: 1)
        layer?.backgroundColor = (complete ? explainAccent : explainAccent.withAlphaComponent(0.16)).hudCG
        isHidden = false
        width?.constant = ceil(label.intrinsicContentSize.width) + 18
        guard animated, !DisplayOptions.reduceMotion, let layer else { return }
        // A small bounce about the centre (a view's layer scales about its corner unless told otherwise)
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        func scaled(_ scale: CGFloat) -> NSValue {
            var transform = CATransform3DMakeTranslation(centre.x, centre.y, 0)
            transform = CATransform3DScale(transform, scale, scale, 1)
            return NSValue(caTransform3D: CATransform3DTranslate(transform, -centre.x, -centre.y, 0))
        }
        let bounce = CAKeyframeAnimation(keyPath: "transform")
        bounce.values = [scaled(0.9), scaled(1.12), scaled(1)]
        bounce.keyTimes = [0, 0.55, 1]
        bounce.duration = 0.26
        layer.add(bounce, forKey: "bounce")
    }
}

/// The line under the explainer's header that fills as the page is read.
final class ProgressLine: NSView {
    private let fill = CALayer()
    private var fraction: CGFloat = 0

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        fill.anchorPoint = .zero
        layer?.addSublayer(fill)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        // The panel was resized: the fill keeps its share of the new width, without animating
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = NSRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        CATransaction.commit()
    }

    /// Fill to `value` (0…1). Animated, the line goes a little too far and settles, with the mark that moved it.
    func set(_ value: CGFloat, animated: Bool) {
        fraction = max(0, min(1, value))
        fill.backgroundColor = explainAccent.hudCG
        CATransaction.begin()
        if animated, !DisplayOptions.reduceMotion {
            CATransaction.setAnimationDuration(0.5)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 1.5, 0.5, 1))
        } else {
            CATransaction.setDisableActions(true)
        }
        fill.frame = NSRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        CATransaction.commit()
    }
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

/// The explainer: a page of Markdown, diagrams and code beside the app being demonstrated. It stacks
/// with other windows like an ordinary one, unless the "explain.floating" setting keeps it on top.
///
/// Why it exists: the status bar holds one line and the mirror shows the raw conversation; a design
/// decision, a table or a sequence diagram needs a page the reader can scroll and return to.
/// Created and owned by {@link HUD}; `dw explain` adds pages through `index.json`, and
/// {@link HUD.refresh} calls {@link Explainer.refresh} to pick them up.
final class Explainer: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    /// Schemes a link in a page may open in another app (a browser, an IDE).
    private static let externalSchemes: Set<String> = ["http", "https", "phpstorm", "jetbrains", "vscode", "cursor"]
    private static let headerHeight: CGFloat = 36

    let panel = ReadingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let root = NSView()
    private let grip = DragHandle()
    private let heading = NSTextField(labelWithString: "⠿ 解説")
    private let pageLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "")
    private let webView: ReadingWebView
    private lazy var listButton = IconButton(symbol: "list.bullet", label: "解説の一覧", pointSize: 12, target: self, action: #selector(listTapped))
    private lazy var prevButton = IconButton(symbol: "chevron.left", label: "前の解説", pointSize: 12, target: self, action: #selector(prevTapped))
    private lazy var nextButton = IconButton(symbol: "chevron.right", label: "次の解説", pointSize: 12, target: self, action: #selector(nextTapped))
    private lazy var zoomOut = IconButton(symbol: "minus", label: "文字を小さく", pointSize: 12, target: self, action: #selector(zoomOutTapped))
    private lazy var zoomIn = IconButton(symbol: "plus", label: "文字を大きく", pointSize: 12, target: self, action: #selector(zoomInTapped))
    private lazy var closeButton = IconButton(symbol: "xmark", label: "解説を閉じる", pointSize: 12, target: self, action: #selector(closeTapped))
    private let handles: [EdgeResizeHandle] = [
        EdgeResizeHandle([.left]), EdgeResizeHandle([.right]), EdgeResizeHandle([.top]), EdgeResizeHandle([.bottom]),
        EdgeResizeHandle([.left, .top]), EdgeResizeHandle([.right, .top]), EdgeResizeHandle([.left, .bottom]), EdgeResizeHandle([.right, .bottom]),
    ]
    private var pages: [ExplainPage] = []
    /// Number of the page on screen (0 = none).
    private(set) var shown = 0
    /// `current` of the last index read: a change means `dw explain` added a page.
    private var announced = 0
    private var indexStamp: Date?
    /// The page's selection, for Command-C (see {@link PageSelection}).
    private(set) lazy var selection = PageSelection(panel: panel, webView: webView)
    /// How much of the page is marked as read (see Reading.swift): the count in the header, the line under it.
    private let readChip = ReadChip()
    private let progressLine = ProgressLine()
    /// The page reported a change of its reading marks (`{type: "reading", …}`).
    var onReading: (([String: Any]) -> Void)?
    /// A page finished loading: the number of the page on screen.
    var onPageLoaded: ((Int) -> Void)?

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
        applyLevel()
        panel.collectionBehavior = stageCollectionBehavior
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        root.wantsLayer = true
        root.layer?.cornerRadius = surfaceCornerRadius
        root.layer?.masksToBounds = true
        // A page is read for minutes: nothing of the app behind it shows through
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1).cgColor
        applyLook()

        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "dw")
        // Before the first page loads: its script goes into the pages loaded after this
        _ = selection
        // The page paints its own dark background; without this the view flashes white while loading
        if webView.responds(to: Selector(("_setDrawsBackground:"))) { webView.setValue(false, forKey: "drawsBackground") }
        applyZoom()

        // The surface's name carries the weight; page number and zoom are quiet facts beside it
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = .labelColor
        pageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        pageLabel.textColor = .secondaryLabelColor
        titleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.alignment = .center
        grip.toolTip = "ドラッグで解説パネルを移動"
        // Invisible borders on every side and corner: drag any of them to resize
        for h in handles { h.onResize = { [weak self] r in self?.resize(to: r) } }

        for v in [grip, webView, readChip, progressLine, listButton, prevButton, nextButton, zoomOut, zoomLabel, zoomIn, closeButton] as [NSView] {
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
            grip.trailingAnchor.constraint(equalTo: readChip.leadingAnchor, constant: -6),
            readChip.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            readChip.trailingAnchor.constraint(equalTo: listButton.leadingAnchor, constant: -6),
            // In the two points between the header and the page
            progressLine.topAnchor.constraint(equalTo: grip.bottomAnchor),
            progressLine.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 1),
            progressLine.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -1),
            progressLine.heightAnchor.constraint(equalToConstant: 2),
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

            // Clear of the 6-point edge handles: the web view sets its own cursor and would fight theirs
            webView.topAnchor.constraint(equalTo: grip.bottomAnchor, constant: 2),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
        ])
        // 28 points square: the system's size for a control on the Mac
        for button in [listButton, prevButton, nextButton, zoomOut, zoomIn, closeButton] {
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        // Under the header's buttons: a corner handle over the close button would resize on a click meant to close
        pinEdgeHandles(handles, to: root, below: listButton)
        panel.contentView = root
        // Pages that were there before this launch (a new build, the agent restarted) are not news:
        // the newest one is loaded again, and the panel stays open or closed as the user left it
        indexStamp = mtime(explainIndexPath)
        announced = readIndex()
        if announced > 0 { show(announced) }
        updateHeader()
    }

    // MARK: pages

    /// Pick up pages added by `dw explain` and keep the panel's visibility in step with the settings.
    /// Called by the HUD on every refresh tick.
    func refresh() {
        // What `dw explain --hide / --show / --back` asked for
        var raise = false, lower = false
        if let request = try? String(contentsOfFile: explainVisibilityRequestPath, encoding: .utf8) {
            try? FileManager.default.removeItem(atPath: explainVisibilityRequestPath)
            switch request.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "hide": settings.set("explain.visible", 0)
            case "back": lower = true
            default:
                settings.set("explain.visible", 1)
                raise = true
            }
        }
        let stamp = mtime(explainIndexPath)
        if stamp != indexStamp {
            indexStamp = stamp
            let current = readIndex()
            if current != announced {
                // A new page: show it in front, even if the reader had closed the panel or was on an older page
                announced = current
                if current > 0 { settings.set("explain.visible", 1) }
                show(current)
                raise = true
            } else if shown == current {
                // The page on screen was rewritten in place (`dw explain --replace`)
                show(current)
            }
            updateHeader()
        }
        updateVisibility()
        if raise { bringToFront() }
        if lower { sendBehind() }
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
        selection.reset()
        // Until the new page says what is read on it
        setProgress(read: 0, total: 0, animated: false)
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

    /// Show the panel when it is switched on and has a page; conceal it while `dw click-xy` needs it out of the way.
    func updateVisibility() {
        let wanted = settings.isOn("explain.visible") && shown > 0
        if wanted, !panel.isVisible { panel.orderFrontRegardless() }
        if !wanted, panel.isVisible { panel.orderOut(nil) }
        panel.setConcealed(exists(mirrorSuspendPath))
    }

    /// Outline of the panel: its own green, stronger with "Increase contrast". Called at launch and
    /// when a display setting changes.
    func applyLook() {
        root.layer?.borderColor = explainAccent.hudCG
        root.layer?.borderWidth = surfaceBorderWidth
    }

    // MARK: stacking

    /// Ordinary window level, or above every app while "explain.floating" is on.
    func applyLevel() { panel.level = settings.isOn("explain.floating") ? .floating : .normal }

    /// In front of the other apps' windows on the desktop the user is looking at, without taking focus
    /// from them. A new page, `dw explain --show` and the book button call it: a panel left open on
    /// another desktop comes here. Nothing else moves the panel between desktops.
    func bringToFront() {
        if panel.isVisible { panel.orderFrontOnActiveSpace() }
    }

    /// True while the panel is open on a desktop other than the one the user is looking at.
    var isOnAnotherSpace: Bool { panel.isOnAnotherSpace }

    /// Ordinary windows of other apps that overlap the panel, front to back (no menus, no Dock, no HUD surface).
    ///
    /// @param aboveOnly - true: only the windows in front of the panel; false: every window on screen.
    /// @returns Their window numbers.
    private func overlappingWindows(aboveOnly: Bool) -> [Int] {
        guard panel.isVisible, let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([aboveOnly ? .optionOnScreenAboveWindow : .optionOnScreenOnly, .excludeDesktopElements],
                                                    aboveOnly ? CGWindowID(panel.windowNumber) : kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        // Window bounds come with the origin at the top left of the primary screen
        let frame = panel.frame
        let mine = CGRect(x: frame.minX, y: primary.frame.height - frame.maxY, width: frame.width, height: frame.height)
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        return list.compactMap { info -> Int? in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowOwnerPID as String] as? NSNumber)?.intValue != me,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict), bounds.intersects(mine) else { return nil }
            return number
        }
    }

    /// True when a window of another app lies over part of the panel.
    var isCovered: Bool { !overlappingWindows(aboveOnly: true).isEmpty }

    /// Step behind the app the reader should look at: just below the frontmost window of another app
    /// that overlaps the panel. Where nothing overlaps there is nothing to step behind, and a panel
    /// on another desktop is out of the way already.
    func sendBehind() {
        guard panel.level == .normal, panel.isOnActiveSpace, let front = overlappingWindows(aboveOnly: false).first else { return }
        panel.order(.below, relativeTo: front)
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

    /// Messages from the page: its render report, the text of a code block's copy button, and what is
    /// selected (the panel never becomes key, so Command-C reaches the page through {@link PageSelection}).
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
        case "selection":
            selection.update(text: body["text"] as? String ?? "")
        case "reading":
            onReading?(body)
        default:
            break
        }
    }

    /// A page finished loading: the HUD gives it back what is kept for it (see Reading.swift).
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if shown > 0 { onPageLoaded?(shown) }
    }

    // MARK: reading marks

    /// Run a script in the page on screen.
    func evaluate(_ script: String) { webView.evaluateJavaScript(script) }

    /// Show how much of the page is read: the count in the header and the line under it. `total` 0 hides both.
    func setProgress(read: Int, total: Int, animated: Bool) {
        readChip.set(read: read, total: total, animated: animated)
        progressLine.isHidden = total <= 0
        progressLine.set(total > 0 ? CGFloat(read) / CGFloat(total) : 0, animated: animated)
    }

    /// Where the count in the header is on screen, or nil while it is not shown.
    func chipCentre() -> NSPoint? {
        guard !readChip.isHidden, let window = readChip.window else { return nil }
        let frame = window.convertToScreen(readChip.convert(readChip.bounds, to: nil))
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    /// The part of the panel under its header, on screen: where a page lies.
    var contentFrame: NSRect {
        let frame = panel.frame
        return NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - Self.headerHeight)
    }

    /// Title of page `n` ("" when there is no such page).
    func title(of n: Int) -> String { pages.first { $0.n == n }?.title ?? "" }
}
