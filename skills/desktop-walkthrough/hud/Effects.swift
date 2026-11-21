// Effects layer of the HUD: a see-through, click-through window over the screen that draws what
// celebrates a moment and is gone (the banner across a cleared page, an achievement under the bar,
// sparks, the ring around a pressed button). The drawing itself is a web page, `explainer/effects.html`.
import AppKit
import WebKit

/// The effects page, copied by `dw` from the skill's `explainer/effects.html` before the HUD starts.
let effectsPagePath = "\(explainDir)/effects.html"

/// The effects layer.
///
/// Why it exists: a celebration belongs to no single surface (the banner lies over the explainer or
/// a note, an achievement opens under the bar) and must outlive the page it is about, which the
/// agent replaces seconds after 次へ. So it is drawn in a window of its own, shown only while
/// something plays. Created and owned by {@link HUD}; Reading.swift and AskPrompt.swift call
/// {@link Effects.play}. The "feedback.effects" setting switches it off.
final class Effects: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let webView: WKWebView
    private var loaded = false
    /// True once the page was asked to load (it is not there when `dw` could not copy it).
    private var loading = false
    /// Calls made before the page had loaded.
    private var waiting: [String] = []
    /// Effects asked for so far: the page says how many it has started when it reports "nothing left".
    private var sent = 0

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
    }

    /// Build the window and load the page. Called once by the HUD at launch.
    func attach() {
        // Over the HUD's own surfaces too: an achievement may open beside the prompt card
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = hudCollectionBehavior
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "dw")
        if webView.responds(to: Selector(("_setDrawsBackground:"))) { webView.setValue(false, forKey: "drawsBackground") }
        panel.contentView = webView
        load()
    }

    /// Load the effects page, once it is there.
    private func load() {
        guard !loading, exists(effectsPagePath) else { return }
        loading = true
        webView.loadFileURL(URL(fileURLWithPath: effectsPagePath), allowingReadAccessTo: URL(fileURLWithPath: explainDir, isDirectory: true))
    }

    /// Draw an effect: `fx.<name>(payload)` in the page. Positions in the payload are in the layer's
    /// coordinates ({@link Effects.rect}, {@link Effects.point}) for `screen`.
    ///
    /// @param name - `banner`, `toast`, `burst` or `ring`.
    /// @param screen - The screen the effect is drawn on (the one the surface it is about is on).
    func play(_ name: String, _ payload: [String: Any], on screen: NSScreen) {
        guard settings.isOn("feedback.effects"), !hudHidden, exists(effectsPagePath),
              let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        load()
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: false) }
        sent += 1
        let call = "fx.\(name)(\(json)); fx.sent = \(sent);"
        panel.orderFrontRegardless()
        if loaded { webView.evaluateJavaScript(call) } else { waiting.append(call) }
    }

    /// Take the layer off the screen at once, with whatever it was drawing: the user hid the HUD.
    func hide() { panel.orderOut(nil) }

    /// A rectangle of the screen (Cocoa coordinates) as the page counts: points from the top-left corner of `screen`.
    func rect(_ frame: NSRect, on screen: NSScreen) -> [String: Any] {
        ["x": frame.minX - screen.frame.minX, "y": screen.frame.maxY - frame.maxY, "w": frame.width, "h": frame.height]
    }

    /// A point of the screen (Cocoa coordinates) as the page counts.
    func point(_ point: NSPoint, on screen: NSScreen) -> (x: CGFloat, y: CGFloat) {
        (point.x - screen.frame.minX, screen.frame.maxY - point.y)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        for call in waiting { webView.evaluateJavaScript(call) }
        waiting = []
    }

    /// The page reports that nothing is left to draw: the window goes, unless an effect asked for
    /// since then is still on its way to the page.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], body["type"] as? String == "fx-idle" else { return }
        let started = (body["sent"] as? NSNumber)?.intValue ?? 0
        if started >= sent { panel.orderOut(nil) }
    }
}
