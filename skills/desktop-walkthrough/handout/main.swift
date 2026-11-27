// HandoutRenderer — the host of `dw handout`: renders a Record's pages in WebKit for the builder and
// publishes the Handout it assembles.
//
// Why it exists: WebKit lays out only web views in a window that is on screen (it has no headless
// mode), and mermaid needs layout to draw and the builder to measure. This host keeps an ordered-in
// window that nobody sees (alpha 0, click-through, like the HUD's hidden surfaces) and three web
// views in it. Called by `dw handout`, which builds it from this file when the file is newer.
//
// Usage: HandoutRenderer <input.json> <dist folder>
//   input.json   written by dw (packages/handout/src/contract.ts, handoutInputSchema)
//   dist folder  packages/handout/dist: builder.html (the builder) and purify.js (DOMPurify)
// Prints one JSON line (contract HostResult) and exits 0 when a Handout was published, 1 otherwise.
//
// Flow (eng review, final diagram):
//
//   builder view: dist/builder.html ── dwHandout.build(input) ──▶ BuildOutcome
//     │  postMessage "host" with reply (only this view can ask):
//     ├─ render N ─▶ page view: explain/pages/NNN.html (DOMPurify injected, report channel "dw")
//     │               wait for report {page: N}, run the probe ──▶ reply rendered
//     ├─ read path ─▶ the file's bytes ──▶ reply file | unreadable
//     └─ verify html ─▶ verify view (plain, like the colleague's browser): open, run the probe ──▶ reply verified
//   limits: pageMs per page, runMs per run; a web content process that ends, a failed load or a
//   builder exception ends the run at once ──▶ HANDOUT_RENDERER
//   publish: no file there ─▶ exclusive create; a file there ─▶ RENAME_SWAP, check the swapped-out
//            file for the Handout marker, swap back if it has none ──▶ HANDOUT_OUT_EXISTS
import AppKit
import Darwin
import WebKit

/// What makes a file a Handout, looked for in its first `markerScanBytes` bytes before it is replaced.
/// The same literal as HANDOUT_MARKER_ATTRIBUTE in packages/handout/src/contract.ts (scripts/check compares them).
let handoutMarkerAttribute = "name=\"dw-handout\""
/// MARKER_SCAN_BYTES in packages/handout/src/constants.ts.
let markerScanBytes = 4096
/// HANDOUT_PROTOCOL_VERSION in packages/handout/src/constants.ts.
let protocolVersion = 1

/// Print the result line for dw and exit.
func finish(_ result: [String: Any], code: Int32) -> Never {
    var line = "{\"v\":\(protocolVersion),\"ok\":false,\"diagnostics\":[{\"code\":\"HANDOUT_RENDERER\",\"message\":\"the result could not be written\"}],\"log\":\"(none)\"}"
    if let data = try? JSONSerialization.data(withJSONObject: result), let text = String(data: data, encoding: .utf8) {
        line = text
    }
    print(line)
    fflush(stdout)
    exit(code)
}

/// A failure result with one diagnostic.
func failure(code: String, message: String, page: Int? = nil, log: String) -> [String: Any] {
    var diagnostic: [String: Any] = ["code": code, "message": message]
    if let page { diagnostic["page"] = page }
    return ["v": protocolVersion, "ok": false, "diagnostics": [diagnostic], "log": log]
}

/// The message of a JavaScript exception, else the error's own description, on one line.
func describe(_ error: Error) -> String {
    let nsError = error as NSError
    let text = (nsError.userInfo["WKJavaScriptExceptionMessage"] as? String) ?? nsError.localizedDescription
    return text.replacingOccurrences(of: "\n", with: " ")
}

/// How publishing ended.
enum Publication {
    case published
    case isFolder
    case notAHandout
    case failed(String)
}

/// Whether the file at a path carries the Handout marker near its top.
func isHandout(atPath path: String) -> Bool {
    guard let handle = FileHandle(forReadingAtPath: path) else { return false }
    defer { try? handle.close() }
    let head = handle.readData(ofLength: markerScanBytes)
    return String(decoding: head, as: UTF8.self).contains(handoutMarkerAttribute)
}

/// The text of the current errno.
func errnoText() -> String { String(cString: strerror(errno)) }

/// Publish the Handout at `target` without ever destroying a file that is not a Handout (eng D7).
///
/// A missing target is created exclusively (RENAME_EXCL). An existing one is swapped with the new
/// file in one step (RENAME_SWAP); the file swapped out is then checked for the marker and, when it
/// has none, swapped back, so no moment exists in which another program's file is gone.
func publish(_ data: Data, to target: String) -> Publication {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory), isDirectory.boolValue {
        return .isFolder
    }
    let folder = (target as NSString).deletingLastPathComponent
    let temporary = (folder as NSString).appendingPathComponent(".handout-\(getpid())-\(UUID().uuidString).tmp")
    do {
        try data.write(to: URL(fileURLWithPath: temporary), options: .withoutOverwriting)
    } catch {
        return .failed("could not write in \(folder): \(describe(error))")
    }
    // Nothing there yet: create it, failing if something appeared in the meantime
    if renamex_np(temporary, target, UInt32(RENAME_EXCL)) == 0 { return .published }
    guard errno == EEXIST else {
        let reason = errnoText()
        unlink(temporary)
        return .failed("could not create \(target): \(reason)")
    }
    // Something is there: swap, then look at what was swapped out
    guard renamex_np(temporary, target, UInt32(RENAME_SWAP)) == 0 else {
        let reason = errnoText()
        unlink(temporary)
        return .failed("could not replace \(target): \(reason)")
    }
    if isHandout(atPath: temporary) {
        unlink(temporary)
        return .published
    }
    // Not a Handout: put it back where it was; the temporary path then holds the new file again
    guard renamex_np(temporary, target, UInt32(RENAME_SWAP)) == 0 else {
        return .failed("could not put the earlier file back at \(target) (\(errnoText())): it is at \(temporary)")
    }
    unlink(temporary)
    return .notAHandout
}

/// A render the builder is waiting for.
struct PendingRender {
    let page: Int
    let probe: String
    let reply: (Any?, String?) -> Void
    let timer: DispatchWorkItem
}

/// A verification the builder is waiting for.
struct PendingVerify {
    let probe: String
    let reply: (Any?, String?) -> Void
    let timer: DispatchWorkItem
}

final class Renderer: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    let input: [String: Any]
    let explainDir: URL
    let distDir: URL
    let out: String
    let logPath: String
    let pageLimitMs: Int
    let runLimitMs: Int
    /// Page number → built page, relative to explainDir.
    let builtPages: [Int: String]
    let window: NSWindow
    let builderView: WKWebView
    let pageView: WKWebView
    var verifyView: WKWebView?
    var builderStarted = false
    var pendingRender: PendingRender?
    var pendingVerify: PendingVerify?
    var logHandle: FileHandle?

    init(input: [String: Any], explainDir: URL, distDir: URL, out: String, logPath: String,
         pageLimitMs: Int, runLimitMs: Int, builtPages: [Int: String]) {
        self.input = input
        self.explainDir = explainDir
        self.distDir = distDir
        self.out = out
        self.logPath = logPath
        self.pageLimitMs = pageLimitMs
        self.runLimitMs = runLimitMs
        self.builtPages = builtPages
        FileManager.default.createFile(atPath: logPath, contents: nil)
        logHandle = FileHandle(forWritingAtPath: logPath)
        // Ordered in, so WebKit lays out; invisible and click-through, so nobody sees or hits it
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 1000),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        // The builder's channel: its view alone may ask for files (eng C2a)
        let builderConfiguration = WKWebViewConfiguration()
        builderView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: builderConfiguration)
        // The page view: the render report's channel, and DOMPurify before any page script (eng D6)
        let pageConfiguration = WKWebViewConfiguration()
        pageView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1000), configuration: pageConfiguration)
        super.init()
        builderConfiguration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "host")
        pageConfiguration.userContentController.add(self, name: "dw")
        if let purify = try? String(contentsOf: distDir.appendingPathComponent("purify.js"), encoding: .utf8) {
            pageConfiguration.userContentController.addUserScript(
                WKUserScript(source: purify, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        } else {
            log("purify.js is missing from \(distDir.path): pages render without DOMPurify and the builder reports it")
        }
        builderView.navigationDelegate = self
        pageView.navigationDelegate = self
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        content.addSubview(builderView)
        content.addSubview(pageView)
        window.contentView = content
        window.orderFrontRegardless()
    }

    func log(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        logHandle?.write(Data("\(stamp) \(line)\n".utf8))
    }

    func schedule(after milliseconds: Int, _ action: @escaping () -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: item)
        return item
    }

    /// End the run: the host could not finish (a limit, a crash, a broken builder).
    func failRenderer(_ message: String, page: Int? = nil) -> Never {
        log("HANDOUT_RENDERER: \(message)")
        finish(failure(code: "HANDOUT_RENDERER", message: message, page: page, log: logPath), code: 1)
    }

    func start() {
        log("start: \(builtPages.count) page(s), limits \(pageLimitMs) ms per page, \(runLimitMs) ms per run")
        _ = schedule(after: runLimitMs) {
            self.failRenderer("the export took longer than \(self.runLimitMs / 1000) s", page: self.pendingRender?.page)
        }
        builderView.loadFileURL(distDir.appendingPathComponent("builder.html"), allowingReadAccessTo: distDir)
    }

    func runBuilder() {
        log("builder loaded: build")
        // The builder is a module script, which WebKit may run after it reports the load finished
        let script = """
        for (let waited = 0; !window.dwHandout && waited < 5000; waited += 20) await new Promise((resolve) => setTimeout(resolve, 20));
        if (!window.dwHandout) throw new Error('the builder page did not define dwHandout within 5 s');
        return await window.dwHandout.build(input);
        """
        builderView.callAsyncJavaScript(script, arguments: ["input": input], in: nil, in: .page) { result in
            switch result {
            case .failure(let error):
                self.failRenderer("the builder stopped: \(describe(error))", page: self.pendingRender?.page)
            case .success(let value):
                self.handleOutcome(value)
            }
        }
    }

    func handleOutcome(_ value: Any) {
        guard let outcome = value as? [String: Any], let ok = outcome["ok"] as? Bool else {
            failRenderer("the builder returned no outcome")
        }
        guard ok else {
            log("build stopped: \(outcome["diagnostics"] ?? "")")
            finish(["v": protocolVersion, "ok": false, "diagnostics": outcome["diagnostics"] ?? [], "log": logPath], code: 1)
        }
        guard let html = outcome["html"] as? String else { failRenderer("the builder returned no Handout") }
        switch publish(Data(html.utf8), to: out) {
        case .published:
            log("published: \(out)")
            finish(["v": protocolVersion, "ok": true, "path": out, "pages": outcome["pages"] ?? 0,
                    "diagrams": outcome["diagrams"] ?? 0, "warnings": outcome["warnings"] ?? []], code: 0)
        case .isFolder:
            finish(failure(code: "HANDOUT_OUT_EXISTS", message: "\(out) is a folder: name a file", log: logPath), code: 1)
        case .notAHandout:
            finish(failure(code: "HANDOUT_OUT_EXISTS",
                           message: "\(out) holds a file that is not a Handout: it was left as it was; choose another --out",
                           log: logPath), code: 1)
        case .failed(let reason):
            finish(failure(code: "HANDOUT_OUT_EXISTS", message: "\(reason); choose another --out", log: logPath), code: 1)
        }
    }

    // MARK: the builder's requests

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.webView === builderView, let request = message.body as? [String: Any],
              let type = request["type"] as? String else {
            replyHandler(nil, "not a host request")
            return
        }
        switch type {
        case "render":
            guard let page = request["page"] as? Int, let probe = request["probe"] as? String else {
                return replyHandler(nil, "a render request needs page and probe")
            }
            render(page: page, probe: probe, reply: replyHandler)
        case "read":
            guard let path = request["path"] as? String else { return replyHandler(nil, "a read request needs path") }
            read(path: path, reply: replyHandler)
        case "verify":
            guard let html = request["html"] as? String, let probe = request["probe"] as? String else {
                return replyHandler(nil, "a verify request needs html and probe")
            }
            verify(html: html, probe: probe, reply: replyHandler)
        default:
            replyHandler(nil, "unknown host request \(type)")
        }
    }

    func render(page: Int, probe: String, reply: @escaping (Any?, String?) -> Void) {
        guard pendingRender == nil else { return reply(nil, "a page is already being rendered") }
        guard let built = builtPages[page] else { return reply(nil, "page \(page) is not in input.json") }
        let timer = schedule(after: pageLimitMs) {
            self.failRenderer("page \(page) did not finish rendering within \(self.pageLimitMs / 1000) s", page: page)
        }
        pendingRender = PendingRender(page: page, probe: probe, reply: reply, timer: timer)
        log("render page \(page): \(built)")
        pageView.loadFileURL(explainDir.appendingPathComponent(built), allowingReadAccessTo: explainDir)
    }

    func read(path: String, reply: @escaping (Any?, String?) -> Void) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            reply(["type": "file", "base64": data.base64EncodedString()], nil)
        } catch {
            let code = (error as NSError).code
            let reason = code == NSFileReadNoSuchFileError ? "no such file"
                : code == NSFileReadNoPermissionError ? "permission denied" : describe(error)
            log("read failed: \(reason)")
            reply(["type": "unreadable", "message": reason], nil)
        }
    }

    func verify(html: String, probe: String, reply: @escaping (Any?, String?) -> Void) {
        guard pendingVerify == nil else { return reply(nil, "a verification is already running") }
        let file = explainDir.appendingPathComponent("handout-verify.html")
        do {
            try Data(html.utf8).write(to: file)
        } catch {
            failRenderer("the finished Handout could not be written for verification: \(describe(error))")
        }
        // A plain view, as the colleague's browser: no channel, nothing injected
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 1000), configuration: WKWebViewConfiguration())
        view.navigationDelegate = self
        window.contentView?.addSubview(view)
        verifyView = view
        let timer = schedule(after: pageLimitMs) {
            self.failRenderer("the finished Handout did not open within \(self.pageLimitMs / 1000) s")
        }
        pendingVerify = PendingVerify(probe: probe, reply: reply, timer: timer)
        log("verify: opening the finished Handout (\(html.utf8.count) bytes)")
        view.loadFileURL(file, allowingReadAccessTo: explainDir)
    }

    // MARK: the page's render report

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === pageView, let report = message.body as? [String: Any],
              report["type"] as? String == "rendered", let pending = pendingRender,
              report["page"] as? Int == pending.page else { return }
        log("page \(pending.page) reported: \(report["diagrams"] ?? 0) diagram(s), \((report["errors"] as? [Any])?.count ?? 0) error(s)")
        pageView.callAsyncJavaScript(pending.probe, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .failure(let error):
                self.failRenderer("measuring page \(pending.page) failed: \(describe(error))", page: pending.page)
            case .success(let probe):
                pending.timer.cancel()
                self.pendingRender = nil
                pending.reply(["type": "rendered", "report": report, "probe": probe], nil)
            }
        }
    }

    // MARK: navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === builderView, !builderStarted {
            builderStarted = true
            runBuilder()
        } else if webView === verifyView, let pending = pendingVerify {
            webView.callAsyncJavaScript(pending.probe, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .failure(let error):
                    self.failRenderer("checking the finished Handout failed: \(describe(error))")
                case .success(let probe):
                    pending.timer.cancel()
                    self.pendingVerify = nil
                    self.log("verify: checked")
                    pending.reply(["type": "verified", "probe": probe], nil)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed(webView, error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed(webView, error)
    }

    func loadFailed(_ webView: WKWebView, _ error: Error) {
        failRenderer("\(name(of: webView)) could not be loaded: \(describe(error))", page: pendingRender?.page)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        failRenderer("the web content process of \(name(of: webView)) ended", page: pendingRender?.page)
    }

    func name(of webView: WKWebView) -> String {
        if webView === builderView { return "the builder" }
        if webView === pageView { return pendingRender.map { "page \($0.page)" } ?? "the page view" }
        return "the finished Handout"
    }
}

// MARK: HUD mode (the HUD golden of scripts/check)

/// Renders built explainer pages the way the HUD's explainer panel does (no DOMPurify, the `dw`
/// channel only) and prints, per page, its render report, its `#content` and its number of reading
/// blocks: scripts/check compares the baseline pages with fresh builds (eng D5).
final class HUDRenderer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let explainDir: URL
    var pages: [String]
    let window: NSWindow
    let pageView: WKWebView
    var timer: DispatchWorkItem?
    var current = ""

    init(explainDir: URL, pages: [String]) {
        self.explainDir = explainDir
        self.pages = pages
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1000),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        let configuration = WKWebViewConfiguration()
        pageView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1000), configuration: configuration)
        super.init()
        configuration.userContentController.add(self, name: "dw")
        pageView.navigationDelegate = self
        window.contentView = pageView
        window.orderFrontRegardless()
    }

    func next() {
        guard !pages.isEmpty else { exit(0) }
        current = pages.removeFirst()
        let page = current
        let item = DispatchWorkItem {
            FileHandle.standardError.write(Data("\(page) did not report within 30 s\n".utf8))
            exit(1)
        }
        timer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: item)
        pageView.loadFileURL(explainDir.appendingPathComponent(page), allowingReadAccessTo: explainDir)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let report = message.body as? [String: Any], report["type"] as? String == "rendered" else { return }
        // Which block is read or ahead is reading state, set by timers that may run before or after the
        // report: it is left out, so the comparison sees the page's structure only
        let probe = """
        const content = document.getElementById('content').cloneNode(true);
        for (const block of content.querySelectorAll('.rd-ahead, .rd-read')) block.classList.remove('rd-ahead', 'rd-read');
        return { content: content.innerHTML, blocks: document.querySelectorAll('.rd-block').length };
        """
        pageView.callAsyncJavaScript(probe, arguments: [:], in: nil, in: .page) { result in
            self.timer?.cancel()
            guard case .success(let value) = result, let dom = value as? [String: Any] else {
                FileHandle.standardError.write(Data("\(self.current): the page could not be read\n".utf8))
                exit(1)
            }
            let line: [String: Any] = ["page": self.current, "report": report, "content": dom["content"] ?? "", "blocks": dom["blocks"] ?? 0]
            if let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
                fflush(stdout)
            }
            self.next()
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        FileHandle.standardError.write(Data("\(current): the web content process ended\n".utf8))
        exit(1)
    }
}

// MARK: main

let arguments = CommandLine.arguments
// HandoutRenderer --hud <explain dir> <page.html relative to it>…
if arguments.count >= 4, arguments[1] == "--hud" {
    let hudApp = NSApplication.shared
    hudApp.setActivationPolicy(.accessory)
    let hud = HUDRenderer(explainDir: URL(fileURLWithPath: arguments[2], isDirectory: true), pages: Array(arguments[3...]))
    hud.next()
    withExtendedLifetime(hud) { hudApp.run() }
}
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: HandoutRenderer <input.json> <dist folder> | HandoutRenderer --hud <explain dir> <page.html>…\n".utf8))
    exit(2)
}
guard let inputData = FileManager.default.contents(atPath: arguments[1]),
      let input = (try? JSONSerialization.jsonObject(with: inputData)) as? [String: Any],
      input["v"] as? Int == protocolVersion,
      let explainPath = input["explainDir"] as? String, let out = input["out"] as? String,
      let logPath = input["log"] as? String, let limits = input["limits"] as? [String: Any],
      let pageLimitMs = limits["pageMs"] as? Int, let runLimitMs = limits["runMs"] as? Int,
      let pages = input["pages"] as? [[String: Any]] else {
    finish(failure(code: "HANDOUT_RENDERER", message: "\(arguments[1]) is not an input.json of this version", log: "(none)"), code: 1)
}
var builtPages: [Int: String] = [:]
for page in pages {
    if let number = page["n"] as? Int, let built = page["built"] as? String { builtPages[number] = built }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let renderer = Renderer(input: input, explainDir: URL(fileURLWithPath: explainPath, isDirectory: true),
                        distDir: URL(fileURLWithPath: arguments[2], isDirectory: true), out: out, logPath: logPath,
                        pageLimitMs: pageLimitMs, runLimitMs: runLimitMs, builtPages: builtPages)
renderer.start()
withExtendedLifetime(renderer) { app.run() }
