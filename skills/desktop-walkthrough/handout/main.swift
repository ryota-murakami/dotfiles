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
//     ├─ read path ─▶ a regular file up to imageLimitBytes, read off the main queue ──▶ reply file | unreadable
//     └─ verify html ─▶ verify view (plain, like the colleague's browser): open, run the probe ──▶ reply verified
//   limits: pageMs per page, runMs per run; a web content process that ends, a failed load, a
//   builder exception or dw's process gone (input.json parentPid, looked at every parentMs and once
//   more right before publishing) ends the run at once ──▶ HANDOUT_RENDERER
//   publish: a file there that is not a Handout ─▶ HANDOUT_OUT_EXISTS, nothing written; no file there
//            ─▶ exclusive create; a Handout there ─▶ RENAME_SWAP, check that the swapped-out file
//            starts as a Handout, swap back if not ──▶ HANDOUT_OUT_EXISTS. The new file keeps the
//            replaced one's permissions and ACL, or is not published
import AppKit
import Darwin
import WebKit

/// The first bytes of every Handout: a file is replaced only when it starts with exactly these.
/// The same literal as HANDOUT_HEAD in packages/handout/src/contract.ts and scripts/dw (scripts/check compares them).
let handoutHead = "<!doctype html>\n<html lang=\"ja\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"dw-handout\" content=\"1\">"
/// HANDOUT_PROTOCOL_VERSION in packages/handout/src/constants.ts.
let protocolVersion = 1
/// The largest file the builder may read (an image to embed), in bytes: more would fill memory as base64.
let imageLimitBytes = 20 * 1024 * 1024
/// How often the renderer looks whether dw's process is still there, unless input.json's limits say (parentMs).
let defaultParentCheckMs = 1000

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

/// Whether the file at a path is a Handout: a regular file that starts with `handoutHead`. A link, a
/// pipe or a device never is (a pipe would wait for a writer forever); the marker's text elsewhere
/// near the top (a page about Handouts, a form field, a source file) is not enough.
func isHandout(atPath path: String) -> Bool {
    var info = stat()
    guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
          let handle = FileHandle(forReadingAtPath: path) else { return false }
    defer { try? handle.close() }
    let expected = Data(handoutHead.utf8)
    return handle.readData(ofLength: expected.count) == expected
}

/// A file the builder asked for, as the reply it gets: its bytes, or why not. Called off the main queue
/// by the read request. Only a regular file of at most `imageLimitBytes` is read: a pipe would wait
/// forever and a huge file would fill memory. The checks look at the file as opened, not at its path,
/// and the read stops one byte past the limit: a file swapped or grown after a look cannot slip past.
func readForBuilder(atPath path: String) -> [String: Any] {
    // Opened without waiting: a pipe opened for reading would otherwise wait for a writer forever
    let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else {
        let reason = errno == ENOENT ? "no such file" : errno == EACCES ? "permission denied" : errnoText()
        return ["type": "unreadable", "message": reason]
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { return ["type": "unreadable", "message": errnoText()] }
    guard (info.st_mode & S_IFMT) == S_IFREG else { return ["type": "unreadable", "message": "not a regular file"] }
    let tooLarge: [String: Any] = ["type": "unreadable", "message": "larger than \(imageLimitBytes / 1024 / 1024) MB, the most a Handout embeds"]
    guard info.st_size <= off_t(imageLimitBytes) else { return tooLarge }
    do {
        let data = try handle.read(upToCount: imageLimitBytes + 1) ?? Data()
        // Grown since it was opened: refused, never read whole
        guard data.count <= imageLimitBytes else { return tooLarge }
        return ["type": "file", "base64": data.base64EncodedString()]
    } catch {
        return ["type": "unreadable", "message": describe(error)]
    }
}

/// The text of the current errno.
func errnoText() -> String { String(cString: strerror(errno)) }

/// Give `temporary` the permissions and ACL of the regular file at `target`, else the usual ones of a new
/// file (the umask). Returns nil when done, else why not: a Handout that cannot keep who may read it is
/// not published.
func carryPermissions(from target: String, to temporary: String) -> String? {
    var existing = stat()
    if lstat(target, &existing) == 0, (existing.st_mode & S_IFMT) == S_IFREG {
        guard chmod(temporary, existing.st_mode & 0o7777) == 0 else { return "its permissions could not be set (\(errnoText()))" }
        guard copyfile(target, temporary, nil, copyfile_flags_t(COPYFILE_ACL)) == 0 else {
            return "the ACL of \(target) could not be carried over (\(errnoText()))"
        }
        return nil
    }
    let mask = umask(0)
    umask(mask)
    guard chmod(temporary, 0o666 & ~mask) == 0 else { return "its permissions could not be set (\(errnoText()))" }
    return nil
}

/// Publish the Handout at `target` without ever destroying a file that is not a Handout (eng D7).
///
/// A file there that is not a Handout is left alone before anything is written. A missing target is
/// created exclusively (RENAME_EXCL). An existing Handout is swapped with the new file in one step
/// (RENAME_SWAP); the file swapped out is then checked and, when it does not start as a Handout (one
/// that appeared meanwhile), swapped back, so no moment exists in which another program's file is
/// gone. The new file takes the replaced one's permissions and ACL from the replaced file itself,
/// whatever was saved there meanwhile: who could not read it cannot read the new one. A file left at
/// the temporary path after a swap back is removed only when it holds exactly the bytes written: an
/// editor that saved into it in place keeps its save.
func publish(_ data: Data, to target: String) -> Publication {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory), isDirectory.boolValue {
        return .isFolder
    }
    var present = stat()
    if lstat(target, &present) == 0, !isHandout(atPath: target) { return .notAHandout }
    let folder = (target as NSString).deletingLastPathComponent
    let temporary = (folder as NSString).appendingPathComponent(".handout-\(getpid())-\(UUID().uuidString).tmp")
    // Created readable by its owner alone; its final permissions are set once it is complete
    let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard descriptor >= 0 else { return .failed("could not write in \(folder): \(errnoText())") }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do {
        try handle.write(contentsOf: data)
        try handle.close()
    } catch {
        unlink(temporary)
        return .failed("could not write in \(folder): \(describe(error))")
    }
    if let reason = carryPermissions(from: target, to: temporary) {
        unlink(temporary)
        return .failed("could not prepare the Handout in \(folder): \(reason)")
    }
    // The new file's identity: cleanup removes this file and never one another program saved meanwhile
    var written = stat()
    guard stat(temporary, &written) == 0 else {
        let reason = errnoText()
        unlink(temporary)
        return .failed("could not write in \(folder): \(reason)")
    }
    // Nothing there yet: create it, failing if something appeared in the meantime
    if renamex_np(temporary, target, UInt32(RENAME_EXCL)) == 0 { return .published }
    guard errno == EEXIST else {
        let reason = errnoText()
        unlink(temporary)
        return .failed("could not create \(target): \(reason)")
    }
    // Something appeared since the first look: its permissions now, before it is swapped out
    if let reason = carryPermissions(from: target, to: temporary) {
        unlink(temporary)
        return .failed("could not prepare the Handout in \(folder): \(reason)")
    }
    // The new file stays open across the swap, so its permissions can follow the file it replaced
    let ours = open(temporary, O_RDONLY | O_CLOEXEC)
    guard ours >= 0 else {
        let reason = errnoText()
        unlink(temporary)
        return .failed("could not prepare the Handout in \(folder): \(reason)")
    }
    defer { close(ours) }
    guard renamex_np(temporary, target, UInt32(RENAME_SWAP)) == 0 else {
        let reason = errnoText()
        unlink(temporary)
        return .failed("could not replace \(target): \(reason)")
    }
    if isHandout(atPath: temporary) {
        // The replaced Handout's own permissions and ACL, read from it, onto the published file
        let theirs = open(temporary, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        var replaced = stat()
        let carried = theirs >= 0 && fstat(theirs, &replaced) == 0 && fchmod(ours, replaced.st_mode & 0o7777) == 0
            && fcopyfile(theirs, ours, nil, copyfile_flags_t(COPYFILE_ACL)) == 0
        if theirs >= 0 { close(theirs) }
        if carried {
            unlink(temporary)
            return .published
        }
        // Who may read it could not be kept: the earlier Handout goes back, and the new file goes
        guard renamex_np(temporary, target, UInt32(RENAME_SWAP)) == 0 else {
            return .failed("the permissions of the earlier Handout could not be kept, and it could not be put back at \(target): it is at \(temporary)")
        }
        var back = stat()
        if lstat(temporary, &back) == 0, back.st_dev == written.st_dev, back.st_ino == written.st_ino { unlink(temporary) }
        return .failed("the permissions of the earlier Handout at \(target) could not be carried over: it was left as it was")
    }
    // Not a Handout: put it back where it was; the temporary path then holds the new file again
    guard renamex_np(temporary, target, UInt32(RENAME_SWAP)) == 0 else {
        return .failed("could not put the earlier file back at \(target) (\(errnoText())): it is at \(temporary)")
    }
    // Unless another program saved over the target in between, by a new file or into this one in
    // place: either save stays where it is, and only the untouched new file goes
    var displaced = stat()
    guard lstat(temporary, &displaced) == 0, displaced.st_dev == written.st_dev, displaced.st_ino == written.st_ino,
          displaced.st_size == off_t(data.count), FileManager.default.contents(atPath: temporary) == data else {
        return .failed("\(target) was saved again while the earlier file was put back: it holds the earlier file, and the newer save is kept at \(temporary)")
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
    let parentCheckMs: Int
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
         pageLimitMs: Int, runLimitMs: Int, parentCheckMs: Int, builtPages: [Int: String]) {
        self.input = input
        self.explainDir = explainDir
        self.distDir = distDir
        self.out = out
        self.logPath = logPath
        self.pageLimitMs = pageLimitMs
        self.runLimitMs = runLimitMs
        self.parentCheckMs = parentCheckMs
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
        watchParent()
        builderView.loadFileURL(distDir.appendingPathComponent("builder.html"), allowingReadAccessTo: distDir)
    }

    /// Stop without publishing once dw's process (input.json parentPid) is gone: dw was killed or its
    /// terminal closed, nobody waits for this export, and it must not write a file minutes later.
    /// Runs on the main queue like publishing, so it never stops a publication halfway.
    func watchParent() {
        guard input["parentPid"] is Int else { return }
        // Looked at once now (dw may be gone already), then every parentCheckMs; publish looks once more
        stopIfParentGone()
        _ = schedule(after: parentCheckMs) { self.watchParent() }
    }

    /// End the run without publishing when dw's process (input.json parentPid) is gone. Called by
    /// watchParent, and by handleOutcome right before publishing: dw may end after the last look.
    func stopIfParentGone() {
        guard let parent = input["parentPid"] as? Int, parent > 1 else { return }
        if kill(pid_t(parent), 0) != 0, errno == ESRCH {
            failRenderer("dw (process \(parent)) ended before the export finished: nothing was published")
        }
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
        // dw may have ended since the last look: nobody waits for this file any more
        stopIfParentGone()
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
        // Off the main queue, where the time limits run: a slow volume cannot stop them
        DispatchQueue.global(qos: .userInitiated).async {
            let answer = readForBuilder(atPath: path)
            DispatchQueue.main.async {
                if let message = answer["message"] as? String { self.log("read failed: \(message)") }
                reply(answer, nil)
            }
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
                        pageLimitMs: pageLimitMs, runLimitMs: runLimitMs,
                        parentCheckMs: (limits["parentMs"] as? Int) ?? defaultParentCheckMs, builtPages: builtPages)
renderer.start()
withExtendedLifetime(renderer) { app.run() }
