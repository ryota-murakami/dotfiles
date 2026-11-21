// The Mirror's page: the web view that draws the Session's conversation the way Claude Code's
// terminal draws it. The drawing itself is `packages/mirror` (one HTML file); this file hosts it,
// hands it what the Bridge wrote and takes what the user did in it. The documents and the page's
// messages are described in `packages/protocol`.
import AppKit
import WebKit

/// Folder of the Mirror's page; `dw` copies the skill's `packages/mirror/dist/index.html` into it
/// before the HUD starts, so the HUD and its page are of one version.
let mirrorPageDir = "\(stateDir)/mirror"
let mirrorPagePath = "\(mirrorPageDir)/index.html"
/// The Transcript (the conversation as Rows), by the Bridge. Absent with a Bridge that does not
/// write it yet: the Mirror then shows the older feed.
let mirrorTranscriptPath = "\(bridgeDir)/mirror-transcript.json"
/// What changes while a turn runs (spinner, figures, hint), by the Bridge.
let mirrorLivePath = "\(bridgeDir)/mirror-live.json"

/// Web view of the Mirror: its first click acts even when the Mirror is not the key window.
final class MirrorWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The Mirror's page and its two doors.
///
/// Why it exists: the conversation is drawn by a web page so that its look lives in one place (the
/// workspace's TypeScript, checked in CI) and text input gets what WebKit gives for free: input
/// methods, dictation, selection. A page in a web view may not read files, so this class reads what
/// the Bridge wrote and calls `window.dwMirror` with it, and listens to what the page posts back.
/// Created and owned by {@link HUD}; {@link HUD.reloadFeed} calls {@link MirrorPage.refresh}.
final class MirrorPage: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: MirrorWebView
    /// True once the page was asked to load.
    private var isLoading = false
    /// True once the page said it takes documents.
    private var isReady = false
    /// Modification times of the documents last handed over: each goes to the page only when it changed.
    private var transcriptStamp: Date?
    private var liveStamp: Date?
    /// The zoom last given to the page.
    private var zoomSent: CGFloat = 0
    /// True while the page's Input box has the keyboard, and while it holds a draft.
    private(set) var isFocused = false
    private(set) var hasDraft = false

    /// The user sent a Prompt from the Input box.
    var onSubmit: ((String) -> Void)?
    /// The user asked to stop the running turn.
    var onInterrupt: (() -> Void)?
    /// The user asked to give the keyboard back to the app they came from.
    var onRelease: (() -> Void)?
    /// The Input box took or lost the keyboard.
    var onFocus: ((Bool) -> Void)?

    private static let externalSchemes: Set<String> = ["http", "https", "phpstorm", "jetbrains", "vscode", "cursor"]

    override init() {
        let config = WKWebViewConfiguration()
        // The page is local and self-contained: nothing is kept between launches
        config.websiteDataStore = .nonPersistent()
        webView = MirrorWebView(frame: .zero, configuration: config)
        super.init()
    }

    /// True when the page and a Transcript are both there: the Mirror then shows the page, not the feed.
    var isAvailable: Bool { exists(mirrorPagePath) && exists(mirrorTranscriptPath) }

    /// Wire the web view. Called once by the HUD while it builds the Mirror.
    func attach() {
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "dw")
        // The panel draws the background: the page stays see-through over it
        if webView.responds(to: Selector(("_setDrawsBackground:"))) { webView.setValue(false, forKey: "drawsBackground") }
    }

    /// Load the page, once it is there.
    private func load() {
        guard !isLoading, exists(mirrorPagePath) else { return }
        isLoading = true
        webView.loadFileURL(URL(fileURLWithPath: mirrorPagePath), allowingReadAccessTo: URL(fileURLWithPath: mirrorPageDir, isDirectory: true))
    }

    /// Hand the page what changed since the last call: the zoom, the Transcript, the live state.
    ///
    /// @param zoom - The Mirror's text size, as a factor of the page's base size.
    func refresh(zoom: CGFloat) {
        guard isAvailable else { return }
        load()
        guard isReady else { return }
        if zoom != zoomSent {
            zoomSent = zoom
            // The page's text size is one variable; 13 px is its size at zoom 1, the Mirror's base
            webView.evaluateJavaScript("document.documentElement.style.setProperty('--mirror-font-size', '\(13 * zoom)px')")
        }
        hand(mirrorTranscriptPath, to: "receiveTranscript", stamp: &transcriptStamp)
        hand(mirrorLivePath, to: "receiveLive", stamp: &liveStamp)
    }

    /// Give one document to the page when its file changed. The file is JSON, which is a JavaScript
    /// expression as it stands; a file caught half-written parses to nothing and is tried again.
    private func hand(_ path: String, to receiver: String, stamp: inout Date?) {
        let modified = mtime(path)
        guard modified != stamp, let data = FileManager.default.contents(atPath: path),
              (try? JSONSerialization.jsonObject(with: data)) != nil, let json = String(data: data, encoding: .utf8) else { return }
        stamp = modified
        webView.evaluateJavaScript("window.dwMirror && window.dwMirror.\(receiver)(\(json))")
    }

    /// Put the keyboard in the page's Input box (the user clicked the Mirror's chat button, or pressed stop).
    func focusInput() {
        guard isReady else { return }
        webView.window?.makeFirstResponder(webView)
        webView.evaluateJavaScript("window.dwMirror && window.dwMirror.focusInput && window.dwMirror.focusInput()")
    }

    /// The page is a local file; a clicked link to anything else opens in the app that handles it.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "about" || (url.isFileURL && url.path.hasPrefix(mirrorPageDir)) { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated, let scheme = url.scheme, Self.externalSchemes.contains(scheme) {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    /// The page crashed or was reloaded: it gets everything again once it says it is ready.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        transcriptStamp = nil
        liveStamp = nil
        zoomSent = 0
    }

    /// What the page posts: that it is ready, a Prompt, an interrupt, a release of the keyboard, the
    /// Input box's focus and draft (`PageMessage` in packages/protocol).
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            transcriptStamp = nil
            liveStamp = nil
            zoomSent = 0
        case "submit":
            if let text = body["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { onSubmit?(text) }
        case "interrupt": onInterrupt?()
        case "release": onRelease?()
        case "focus":
            isFocused = body["isFocused"] as? Bool ?? false
            onFocus?(isFocused)
        case "draft": hasDraft = body["hasDraft"] as? Bool ?? false
        default: break
        }
    }
}
