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
//            ─▶ exclusive create; a Handout there ─▶ RENAME_SWAP from a folder of the run's own
//            beside it, check the swapped-out file by descriptor, swap back if it is no Handout
//            ──▶ HANDOUT_OUT_EXISTS. The new file stays 0600
//            until it takes the replaced one's permissions, group and ACL (else the earlier Handout goes
//            back); dw's process is looked at before each rename; another program's save is never
//            deleted. A volume without exclusive renames publishes a new file only
import AppKit
import CryptoKit
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
/// How long the run's watchdogs wait for a rename already under way before they stop the run anyway
/// (a volume that stopped answering), and how often they look again meanwhile.
let commitGraceMs = 60_000
let commitRecheckMs = 1_000
/// How long a watchdog that stopped the run waits for the worker writing the Handout to notice (it
/// removes its partly written file, then reports) before it ends the run itself.
let workerStopWaitMs = 5_000
/// How much of the Handout is written at a time: between two writes the worker looks whether it should stop.
let publishChunkBytes = 1 << 20
/// The largest earlier Handout whose content is read to tell a save from a change of metadata alone; a
/// larger one whose change time moved counts as saved (it is kept beside the new one).
let digestLimitBytes = 512 << 20
/// How long the run's end waits for the log lines already queued before it prints the result anyway.
let logFlushWaitMs = 1_000

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

/// Publication's agreement with the run's watchdogs (the run's timer, the look at dw's process), which
/// keep running on the main queue while a worker publishes: a rename starts only while no watchdog has
/// stopped the run, and once one has started, the watchdogs leave the outcome to the worker for up to
/// `commitGraceMs`, so a completed worker never publishes after a stop and a stop never cuts a
/// replace in half (unless the volume stops answering in the middle of it).
final class PublicationGate {
    /// What a watchdog's stop does: end the run now; wait for the worker writing the file (it notices,
    /// removes what it wrote and reports; `path` is the folder it writes in, or the target itself when
    /// `inPlace`); wait for a rename under way; or end the run in the middle of a rename that outlasted
    /// its grace.
    enum Stop {
        case now
        case afterWorker(path: String, written: Int?, total: Int, inPlace: Bool)
        case afterCommit
        case interrupted
    }

    private let lock = NSLock()
    private var stopped = false
    private var writing: String?
    private var inPlace = false
    private var total = 0
    private var written: Int?
    private var committingSince: Date?

    /// Said on the main queue before the worker starts: the folder of the run's own it writes the
    /// Handout in first, beside the target (`Staging`), and how many bytes the Handout will hold.
    func beginWrite(in folder: String, total bytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        writing = folder
        total = bytes
    }

    /// Said by the worker when it writes the Handout at the target itself (a volume without exclusive
    /// renames): the exclusive rename it asked for did not happen, so this is a write again, not a commit.
    func writeInPlace(at path: String) {
        lock.lock()
        defer { lock.unlock() }
        writing = path
        inPlace = true
        written = nil
        committingSince = nil
    }

    /// Asked by the worker while it reads before writing: whether a watchdog has stopped the run.
    func isStopped() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    /// Asked by the worker before each write and once after the last, with the bytes written so far:
    /// whether to go on. False once a watchdog has stopped the run, or when `stillWanted` says dw is
    /// gone or the run's time is up.
    func mayContinue(written bytes: Int, _ stillWanted: () -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        written = bytes
        return !stopped && stillWanted()
    }

    /// Asked by the worker before each rename, and before the last steps of a Handout written in place
    /// (its permissions, the last look at its path): whether it may go on now. False once a watchdog
    /// has stopped the run, or when `stillWanted` says dw is gone or the run's time is up.
    func allowCommit(_ stillWanted: () -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, stillWanted() else {
            stopped = true
            return false
        }
        if committingSince == nil { committingSince = Date() }
        return true
    }

    /// Said by the worker when the exclusive rename it was allowed did not happen (the target exists):
    /// that rename's grace ends, so the looks that follow are no rename, and the swap after them asks
    /// for a grace of its own (`allowCommit`), which lasts through any swap back.
    func endCommit() {
        lock.lock()
        defer { lock.unlock() }
        committingSince = nil
    }

    /// Asked by a watchdog that would stop the run: see `Stop`. Once it returns anything but
    /// `afterCommit`, no rename starts any more.
    func stop() -> Stop {
        lock.lock()
        defer { lock.unlock() }
        if let since = committingSince {
            guard Date().timeIntervalSince(since) * 1000 >= Double(commitGraceMs) else { return .afterCommit }
            stopped = true
            return .interrupted
        }
        stopped = true
        if let writing { return .afterWorker(path: writing, written: written, total: total, inPlace: inPlace) }
        return .now
    }
}

/// How publishing ended.
enum Publication {
    /// Published; the warnings say what was kept beside it (a save another program made meanwhile).
    case published(warnings: [String])
    case isFolder
    case notAHandout
    /// dw's process ended before the file was published: nothing was.
    case cancelled
    /// Stopped while the file was written in place (a volume without exclusive renames): nothing was
    /// published, and what was left is said (the path is never removed there).
    case cancelledLeaving(String)
    case failed(String)
}

/// Whether the file at a path is a Handout: a regular file that starts with `handoutHead`. Opened
/// without following a link and without waiting (a pipe would wait for a writer forever), then judged
/// by what is open, so a file swapped in after a look at the path cannot slip past. The marker's text
/// elsewhere near the top (a page about Handouts, a form field, a source file) is not enough.
func isHandout(atPath path: String) -> Bool {
    let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { return false }
    defer { close(descriptor) }
    return startsAsHandout(descriptor)
}

/// Whether an open file is a regular file whose first bytes are `handoutHead`.
func startsAsHandout(_ descriptor: Int32) -> Bool {
    var info = stat()
    guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return false }
    let expected = Array(handoutHead.utf8)
    var head = [UInt8](repeating: 0, count: expected.count)
    return pread(descriptor, &head, expected.count, 0) == expected.count && head == expected
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

/// The usual permissions of a new file: 0666 without the umask.
func newFileMode() -> mode_t {
    let mask = umask(0)
    umask(mask)
    return 0o666 & ~mask
}

/// The SHA-256 of what the file open at `descriptor` holds, read from its start; nil when it cannot be
/// read. Used to tell a save from a change of metadata alone (an extended attribute, a chmod), which
/// changes a file's change time too.
func contentDigest(_ descriptor: Int32, keepGoing: () -> Bool = { true }) -> SHA256.Digest? {
    var hasher = SHA256()
    var buffer = [UInt8](repeating: 0, count: publishChunkBytes)
    var offset: off_t = 0
    while true {
        // A stop meanwhile ends the read: no digest, which the caller treats as unknown content
        guard keepGoing() else { return nil }
        let count = buffer.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, publishChunkBytes, offset) }
        if count < 0 { return nil }
        if count == 0 { return hasher.finalize() }
        hasher.update(data: buffer[0..<count])
        offset += off_t(count)
    }
}

/// The digest of the file at `path` (`contentDigest`), opened without following a symlink.
func contentDigest(atPath path: String, keepGoing: () -> Bool = { true }) -> SHA256.Digest? {
    let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { return nil }
    defer { close(descriptor) }
    return contentDigest(descriptor, keepGoing: keepGoing)
}

/// The digest of the file at `path` (`contentDigest`) only while it is the file `expected` describes,
/// with the same stamps and change time before and after the read: anything else (a save made since,
/// one made during the read) leaves the content unknown (nil).
func stableDigest(atPath path: String, expected: stat, keepGoing: () -> Bool) -> SHA256.Digest? {
    let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { return nil }
    defer { close(descriptor) }
    func stillExpected() -> Bool {
        var now = stat()
        return fstat(descriptor, &now) == 0 && sameFile(now, expected) && sameContentStamp(now, expected)
            && sameChangeTime(now, expected)
    }
    guard stillExpected(), let digest = contentDigest(descriptor, keepGoing: keepGoing), stillExpected() else { return nil }
    return digest
}

/// Whether the file open at `descriptor` holds exactly the `size` bytes whose SHA-256 is `expected`:
/// read through the descriptor, so it is this run's own file that is read, wherever its name went. A
/// save another program made into that file in place keeps its identity (`isAtPath`) and changes this.
func holds(_ descriptor: Int32, size: Int, digest expected: SHA256.Digest) -> Bool {
    var now = stat()
    guard fstat(descriptor, &now) == 0, now.st_size == off_t(size) else { return false }
    return contentDigest(descriptor) == expected
}

/// What a message says before it names a file at the target for removal, where the Handout is written
/// at the target itself (a volume without exclusive renames): another program may have saved its own
/// file there since, and the run cannot tell once it has stopped.
let confirmBeforeRemoving = "before removing it, check that the file there is that one, not one another program saved since"

/// Remove the ACL a new file or folder inherited from its folder, by descriptor, before a byte is written.
/// Returns nil once it has none (or the volume has no ACLs), else why it could not be removed: errno
/// is read right after the call that failed.
func clearInheritedAcl(_ descriptor: Int32) -> String? {
    guard let emptyAcl = acl_init(0) else { return errnoText() }
    defer { acl_free(UnsafeMutableRawPointer(emptyAcl)) }
    guard acl_set_fd(descriptor, emptyAcl) != 0 else { return nil }
    let failure = errno
    return failure == ENOTSUP || failure == EOPNOTSUPP ? nil : String(cString: strerror(failure))
}

/// Make a folder for this run alone at `path`: created there exclusively, and changed by its owner only
/// (0700, without the ACL its parent hands down, whose entries could let others add or remove files in
/// it). A file this run removes there is never one another account put at a name it knew. Used by
/// `publish` for the earlier Handout it swaps out, and by `writeVerificationCopy`. Returns nil once the
/// folder is made, else why not (nothing is left then).
func makeOwnedFolder(_ path: String) -> String? {
    guard mkdir(path, 0o700) == 0 else { return errnoText() }
    let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else {
        let reason = errnoText()
        rmdir(path)
        return reason
    }
    defer { close(descriptor) }
    if let reason = clearInheritedAcl(descriptor) {
        rmdir(path)
        return "its inherited ACL could not be removed (\(reason))"
    }
    return nil
}

/// Whether two looks saw the same file: the same device and inode.
func sameFile(_ first: stat, _ second: stat) -> Bool {
    first.st_dev == second.st_dev && first.st_ino == second.st_ino
}

/// Whether two looks at one file saw the same change time (ctime): a write, a chmod or a utimes changes
/// it and nobody can set it back, but a rename changes it too.
func sameChangeTime(_ first: stat, _ second: stat) -> Bool {
    first.st_ctimespec.tv_sec == second.st_ctimespec.tv_sec && first.st_ctimespec.tv_nsec == second.st_ctimespec.tv_nsec
}

/// Whether two looks at one file saw the same content: the same size and modification time.
func sameContentStamp(_ first: stat, _ second: stat) -> Bool {
    first.st_size == second.st_size && first.st_mtimespec.tv_sec == second.st_mtimespec.tv_sec
        && first.st_mtimespec.tv_nsec == second.st_mtimespec.tv_nsec
}

/// Whether the path names the file `written` describes (the same device and inode), not following a symlink.
func isAtPath(_ path: String, _ written: stat) -> Bool {
    var now = stat()
    return lstat(path, &now) == 0 && sameFile(now, written)
}

/// Whether the file at `path` is still the one written (same device and inode) holding exactly `data`.
/// Only then may cleanup remove it: anything else is a save another program made into it, and stays.
func isUntouched(_ path: String, written: stat, data: Data) -> Bool {
    var now = stat()
    guard lstat(path, &now) == 0, now.st_dev == written.st_dev, now.st_ino == written.st_ino,
          now.st_size == off_t(data.count) else { return false }
    return FileManager.default.contents(atPath: path) == data
}

/// Publish the Handout at `target` without ever destroying a file that is not a Handout (eng D7).
///
/// A file there that is not a Handout is left before anything is written. The new file is written in
/// a folder of the run's own beside the target (`Staging`, `makeOwnedFolder`), readable by its owner
/// alone, and stays so until its final permissions are known: what the run publishes, swaps back or
/// removes there is always the file it wrote, never one another account put at a name it knew. A
/// missing target is created exclusively (RENAME_EXCL), then given what any new file there gets: the
/// ACL its folder hands down (`aclForNewFile`) and the usual permissions. An existing Handout is
/// swapped with the new file in one step (RENAME_SWAP), so the earlier Handout lands in that folder;
/// it is judged by descriptor and, when it does not start as a Handout (one that appeared meanwhile),
/// swapped back. A replaced Handout's group, ACL and permissions are read from that file itself and
/// set on the new one by descriptor (`carryPermissions`): who could not read it cannot read the new
/// one, and when they cannot be carried the earlier Handout goes back. The file is written a chunk at
/// a time, and before each and after the last `mayContinue` (given the bytes written so far) says
/// whether to go on; before the exclusive create and again right before the swap, `mayPublish` says
/// whether dw still waits and the run's time is not up, and starts that rename's grace; `commitEnded`
/// ends the exclusive create's when the target turns out to exist. The new file swapped back out is removed only
/// when it holds exactly the bytes written, and a save made into the replaced Handout since it was
/// first looked at is kept: another program's save is never deleted. After the rename that publishes
/// and the looks that follow it, the target is looked at last (`takenOver`): a file another program put
/// there meanwhile, or a save it made into the new file, stays and is never reported as the Handout
/// (the file must still hold the bytes that were checked). On a volume without exclusive
/// renames (exFAT, some network shares) only a new file can be published, created exclusively.
func publish(_ data: Data, to target: String, staging: Staging, writePauseMs: Int = 0,
             digestLimit: Int = digestLimitBytes, keepGoing: () -> Bool = { true },
             mayContinue: (Int) -> Bool, mayPublish: () -> Bool, commitEnded: () -> Void,
             writingInPlace: (String) -> Void) -> Publication {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory), isDirectory.boolValue {
        return .isFolder
    }
    var present = stat()
    let hadTarget = lstat(target, &present) == 0
    if hadTarget, !isHandout(atPath: target) { return .notAHandout }
    // What the earlier Handout held when first looked at, read while it stays that file with those
    // stamps (else unknown): the file swapped out is removed only when it holds exactly this
    let firstDigest = hadTarget && present.st_size <= off_t(digestLimit)
        ? stableDigest(atPath: target, expected: present, keepGoing: keepGoing) : nil
    let folder = (target as NSString).deletingLastPathComponent
    let staged = staging.staged
    if let reason = makeOwnedFolder(staging.folder) {
        return .failed("could not prepare the Handout in \(folder): \(reason)")
    }
    // Its folder hands down no ACL, and 0600 stays until the final permissions are known
    let descriptor = open(staged, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
        let reason = errnoText()
        rmdir(staging.folder)
        return .failed("could not write in \(folder): \(reason)")
    }
    // The descriptor stays open across the renames: permissions are set on this file, wherever it is
    defer { close(descriptor) }
    var written = stat()
    guard fstat(descriptor, &written) == 0 else {
        let reason = errnoText()
        unlink(staged)
        rmdir(staging.folder)
        return .failed("could not write in \(folder): \(reason)")
    }
    /// This run's file and its folder go: the file only while its name still holds it.
    func discard() {
        if isAtPath(staged, written) { unlink(staged) }
        rmdir(staging.folder)
    }
    // A chunk at a time: between two, a stop (the run's time, dw gone) ends the write and removes it
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
    var offset = 0
    while offset < data.count {
        guard mayContinue(offset) else {
            discard()
            return .cancelled
        }
        let end = min(offset + publishChunkBytes, data.count)
        do {
            try handle.write(contentsOf: data.subdata(in: offset..<end))
        } catch {
            discard()
            return .failed("could not write in \(folder): \(describe(error))")
        }
        offset = end
        // Test only (input.json limits.writePauseMs): a pause standing in for a slow volume
        if writePauseMs > 0 { Thread.sleep(forTimeInterval: Double(writePauseMs) / 1000) }
    }
    // Once more after the last write: a stop meanwhile still removes the file
    guard mayContinue(offset) else {
        discard()
        return .cancelled
    }
    guard fstat(descriptor, &written) == 0 else {
        let reason = errnoText()
        discard()
        return .failed("could not write in \(folder): \(reason)")
    }
    /// Renames publish by name: what is published is this run's file, never one put in its place.
    func replacedMeanwhile() -> Publication {
        .failed("another program replaced the Handout being written at \(staged): what it put there stays, and nothing was published")
    }
    // What was checked before it was written: the published file must still hold exactly this
    let writtenDigest = SHA256.hash(data: data)
    /// The failure of a publication whose target no longer holds what this run wrote; nil while it
    /// does: the path still names this run's file, and that file, read through its descriptor, holds
    /// the bytes that were checked (a save made into it in place keeps the file and changes them).
    /// Asked last, after the looks that follow a rename (the digest of a large earlier Handout takes a
    /// while): what another program put or saved there meanwhile stays, and is never called the
    /// Handout. The content is read first and the name looked at last: a file put at the path while
    /// the content was read (this run's file, still open, would read as before) is seen.
    /// `kept` is where the file that was there before still lies, when it does.
    func takenOver(earlierKeptAt kept: String? = nil) -> Publication? {
        let earlier = kept.map { ", and the Handout that was there before is kept at \($0)" } ?? ""
        let whole = holds(descriptor, size: data.count, digest: writtenDigest)
        guard isAtPath(target, written) else {
            return .failed("another program replaced or removed \(target) right after the Handout was put there: what is there now stays (it is not the Handout of this export)\(earlier)")
        }
        guard whole else {
            return .failed("another program saved into \(target) right after the Handout was put there: that save stays (it is not the Handout that was checked)\(earlier)")
        }
        return nil
    }
    /// Test only (input.json limits.writePauseMs): a pause after a rename, and again before the
    /// earlier Handout goes, standing in for a volume that is slow to answer the looks made there.
    func pauseAfterRename() {
        if writePauseMs > 0 { Thread.sleep(forTimeInterval: Double(writePauseMs) / 1000) }
    }
    guard isAtPath(staged, written) else { return replacedMeanwhile() }
    // dw may have ended, or the run's time may be up, while the file was written or looked at (a slow
    // volume): asked last, right before the rename
    guard mayPublish() else {
        discard()
        return .cancelled
    }
    // Nothing there yet: create it, failing if something appeared in the meantime
    if renamex_np(staged, target, UInt32(RENAME_EXCL)) == 0 {
        rmdir(staging.folder)
        pauseAfterRename()
        // What any new file there gets: the ACL its folder hands down, then the usual permissions. An
        // ACL that cannot be read or given may have denied someone: the file then stays its owner's alone
        var aclProblem: String?
        switch aclForNewFile(in: folder) {
        case .none:
            break
        case .entries(let acl):
            if acl_set_fd(descriptor, acl) != 0 {
                aclProblem = "the ACL \(folder) gives its files could not be given to the Handout (\(errnoText()))"
            }
            acl_free(UnsafeMutableRawPointer(acl))
        case .unreadable(let reason):
            aclProblem = "the ACL of \(folder) could not be read (\(reason))"
        }
        // Restrictive (0600) without it: never wider than intended. Published only while the target
        // still names this file: asked last, after the looks above
        guard let aclProblem else {
            fchmod(descriptor, newFileMode())
            return takenOver() ?? .published(warnings: [])
        }
        return takenOver() ?? .published(warnings: ["\(aclProblem): only you can read it"])
    }
    let exclusiveError = errno
    if exclusiveError == ENOTSUP || exclusiveError == ENOSYS {
        discard()
        return publishWithoutRenames(data, to: target, writePauseMs: writePauseMs, writingInPlace: writingInPlace,
                                     mayContinue: mayContinue, mayPublish: mayPublish)
    }
    guard exclusiveError == EEXIST else {
        discard()
        return .failed("could not create \(target): \(String(cString: strerror(exclusiveError)))")
    }
    // That rename did not happen: its grace ends here, and the swap below asks for one of its own
    commitEnded()
    // A Handout is there. Looked at once more right before the swap: a save into the earlier Handout
    // while this one was written changed its change time, which nothing else here touches until the
    // swap renames it
    var beforeSwap = stat()
    let lookedAgain = lstat(target, &beforeSwap) == 0
    guard isAtPath(staged, written) else { return replacedMeanwhile() }
    // dw may have ended, or the run's time may be up, while those looks waited on the volume: asked
    // last, right before the swap
    guard mayPublish() else {
        discard()
        return .cancelled
    }
    // Swap, then look at what was swapped out: it lands in the run's own folder
    guard renamex_np(staged, target, UInt32(RENAME_SWAP)) == 0 else {
        let reason = errnoText()
        discard()
        return .failed("could not replace \(target): \(reason)")
    }
    pauseAfterRename()
    let theirs = open(staged, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    var replaced = stat()
    if theirs >= 0, fstat(theirs, &replaced) == 0, startsAsHandout(theirs) {
        defer { close(theirs) }
        if carryPermissions(from: theirs, to: descriptor) {
            // A save another program made into the earlier Handout meanwhile stays where it is: the file
            // swapped out must be the one looked at before anything was written (`present`), unchanged
            // since, and unchanged while its permissions were read
            // A Handout that appeared there while this one was written (another export) stays too
            // Each result below is asked last whether the target still names this run's file
            // (`takenOver`): another program may have saved over it during these looks
            guard hadTarget else {
                return takenOver(earlierKeptAt: staged)
                    ?? .published(warnings: ["a Handout appeared at \(target) while this one was written: it is kept at \(staged)"])
            }
            var now = stat()
            // The same file with the same size and modification time from the first look to the look
            // before the swap and to the file swapped out (the swap changes the change time)
            let stampsKept = lookedAgain && sameFile(present, beforeSwap) && sameContentStamp(present, beforeSwap)
                && sameFile(beforeSwap, replaced) && sameContentStamp(beforeSwap, replaced)
            // The content decides: the file swapped out must hold what the first look read (a save that
            // kept size and modification time changes it, a metadata change does not), and nothing may
            // change it after that read (its change time would move: no rename follows the swap)
            guard firstDigest != nil else {
                return takenOver(earlierKeptAt: staged)
                    ?? .published(warnings: ["the earlier Handout could not be checked for a save made while it was replaced: it is kept at \(staged)"])
            }
            let displacedDigest = stampsKept ? contentDigest(theirs) : nil
            let unchanged = displacedDigest != nil && displacedDigest == firstDigest
                && fstat(theirs, &now) == 0 && sameContentStamp(now, replaced) && sameChangeTime(now, replaced)
            // Removed only while its name still holds it: a save swapped in there since (a program that
            // followed the file into the folder) stays too
            if !unchanged || !isAtPath(staged, replaced) {
                return takenOver(earlierKeptAt: staged)
                    ?? .published(warnings: ["the earlier Handout was saved while it was replaced: that save is kept at \(staged)"])
            }
            // Asked before the earlier Handout goes: when another program put its file at the target
            // while the looks above read the earlier one, both stay
            // The new Handout's stamps from before that check reads it: a save made into it after the
            // read moves them (nothing of this run's touches the file from here)
            var checked = stat()
            let stamped = fstat(descriptor, &checked) == 0
            if let conflict = takenOver(earlierKeptAt: staged) { return conflict }
            pauseAfterRename()
            // Both looked at once more right before it goes: that check read the whole new Handout, and
            // a save made into the earlier one meanwhile (through a descriptor opened before the swap)
            // moved its change time. Such a save stays, where it is; and while the target no longer
            // names this run's file, or that file was saved into since it was read, the earlier Handout
            // stays too (said by `takenOver`)
            var newest = stat()
            guard fstat(theirs, &now) == 0, sameContentStamp(now, replaced), sameChangeTime(now, replaced),
                  isAtPath(staged, replaced), isAtPath(target, written),
                  stamped, fstat(descriptor, &newest) == 0, sameContentStamp(newest, checked),
                  sameChangeTime(newest, checked) else {
                return takenOver(earlierKeptAt: staged)
                    ?? .published(warnings: ["the earlier Handout was saved while it was replaced: that save is kept at \(staged)"])
            }
            // The earlier Handout goes, as the export was asked to replace it: a copy kept beside would
            // keep what a new export may have been made to remove (a page taken out). A write through a
            // descriptor opened before and landing after the look right above is lost, as with any
            // file replaced by a rename
            unlink(staged)
            rmdir(staging.folder)
            return takenOver() ?? .published(warnings: [])
        }
        // Who may read it could not be kept: the earlier Handout goes back, the new file goes. Only
        // over this run's own file: one another program put at the target meanwhile stays
        guard isAtPath(target, written) else {
            return .failed("the permissions of the earlier Handout could not be carried over, and another program replaced \(target) meanwhile: that file stays, and the earlier Handout is at \(staged)")
        }
        guard renamex_np(staged, target, UInt32(RENAME_SWAP)) == 0 else {
            return .failed("the permissions of the earlier Handout could not be kept, and it could not be put back at \(target): it is at \(staged)")
        }
        guard isUntouched(staged, written: written, data: data) else {
            return .failed("the permissions of the earlier Handout could not be carried over: it is back at \(target), and a newer save made there meanwhile is kept at \(staged)")
        }
        unlink(staged)
        rmdir(staging.folder)
        return .failed("the permissions of the earlier Handout at \(target) could not be carried over (it may belong to another account, or they kept changing while they were read): it was left as it was")
    }
    if theirs >= 0 { close(theirs) }
    // Not a Handout: put it back where it was; the staged path then holds the new file again. Only over
    // this run's own file: one another program put at the target meanwhile stays
    guard isAtPath(target, written) else {
        return .failed("another program replaced \(target) while the earlier file was being put back: that file stays, and the earlier file is at \(staged)")
    }
    guard renamex_np(staged, target, UInt32(RENAME_SWAP)) == 0 else {
        return .failed("could not put the earlier file back at \(target) (\(errnoText())): it is at \(staged)")
    }
    guard isUntouched(staged, written: written, data: data) else {
        return .failed("\(target) was saved again while the earlier file was put back: it holds the earlier file, and the newer save is kept at \(staged)")
    }
    unlink(staged)
    rmdir(staging.folder)
    return .notAHandout
}

/// Where the Handout for a target is written before it is published: `folder`, beside the target,
/// hidden, named after it (one an interrupted run leaves there says what it belongs to) and unique to
/// this run, made by `publish` (`makeOwnedFolder`); and `staged`, the file in it, named like the target.
struct Staging {
    let folder: String
    let staged: String

    init(for target: String) {
        let parent = (target as NSString).deletingLastPathComponent
        let name = (target as NSString).lastPathComponent
        folder = (parent as NSString).appendingPathComponent(".\(name).dw-handout-\(getpid())-\(UUID().uuidString)")
        staged = (folder as NSString).appendingPathComponent(name)
    }
}

/// What the ACL of a folder hands down to a new file in it (`aclForNewFile`).
enum InheritedAcl {
    /// Nothing: no entry that files inherit, no ACL, or a volume without ACLs.
    case none
    /// The entries a new file gets, owned by the caller (acl_free).
    case entries(acl_t)
    /// The folder's ACL could not be read.
    case unreadable(String)
}

/// The ACL a new file in `folder` gets from it, as the system gives one to a file created there: each
/// entry that files inherit (file_inherit), marked inherited, without the flags that pass it further
/// down. The Handout is written in a folder of the run's own, which hands down nothing: `publish` gives
/// a new Handout this once it is published, like any new file beside it.
func aclForNewFile(in folder: String) -> InheritedAcl {
    guard let folderAcl = acl_get_file(folder, ACL_TYPE_EXTENDED) else {
        let failure = errno
        // No ACL there, or none on this volume
        return failure == ENOENT || failure == ENOTSUP || failure == EOPNOTSUPP
            ? .none : .unreadable(String(cString: strerror(failure)))
    }
    defer { acl_free(UnsafeMutableRawPointer(folderAcl)) }
    // Grown by acl_create_entry, which may move it: always the latest
    var given: acl_t? = acl_init(0)
    guard given != nil else { return .unreadable(errnoText()) }
    /// Why the entries could not be made: errno read right after the call that failed.
    func giveUp() -> InheritedAcl {
        let reason = errnoText()
        if let given { acl_free(UnsafeMutableRawPointer(given)) }
        return .unreadable(reason)
    }
    var count = 0
    var entry: acl_entry_t?
    var entryId = ACL_FIRST_ENTRY.rawValue
    while acl_get_entry(folderAcl, entryId, &entry) == 0, let source = entry {
        entryId = ACL_NEXT_ENTRY.rawValue
        var sourceFlags: acl_flagset_t?
        guard acl_get_flagset_np(UnsafeMutableRawPointer(source), &sourceFlags) == 0, let flags = sourceFlags else {
            return giveUp()
        }
        // An entry for subfolders only is not a file's
        guard acl_get_flag_np(flags, ACL_ENTRY_FILE_INHERIT) == 1 else { continue }
        var copy: acl_entry_t?
        var copyFlags: acl_flagset_t?
        guard acl_create_entry(&given, &copy) == 0, let target = copy, acl_copy_entry(target, source) == 0,
              acl_get_flagset_np(UnsafeMutableRawPointer(target), &copyFlags) == 0, let targetFlags = copyFlags else {
            return giveUp()
        }
        // A file passes nothing down, and an entry for the folder's contents only applies to it
        for flag in [ACL_ENTRY_FILE_INHERIT, ACL_ENTRY_DIRECTORY_INHERIT, ACL_ENTRY_LIMIT_INHERIT, ACL_ENTRY_ONLY_INHERIT] {
            acl_delete_flag_np(targetFlags, flag)
        }
        acl_add_flag_np(targetFlags, ACL_ENTRY_INHERITED)
        guard acl_set_flagset_np(UnsafeMutableRawPointer(target), targetFlags) == 0 else { return giveUp() }
        count += 1
    }
    guard count > 0, let entries = given else {
        if let given { acl_free(UnsafeMutableRawPointer(given)) }
        return .none
    }
    return .entries(entries)
}

/// How many times `carryPermissions` reads the earlier Handout's permissions again when they change
/// while they are set on the new file.
let carryAttempts = 3

/// Give the file open at `descriptor` who may read the file open at `source`: its group, its ACL, then
/// its permissions, read from `source` itself and set by descriptor. Read again when they change while
/// they are set, the file its owner's alone again first, so a narrowing made meanwhile (0644 to 0600)
/// is never kept. Called by `publish` for the Handout it replaces, which it has swapped out into the
/// run's own folder by then: nobody reaches it by its name, so only a program that already had it open
/// can change its permissions meanwhile, and the new file shows the earlier ones only until that is
/// seen. Nothing serializes a permission change with this copy; only never carrying them (every
/// Handout its owner's alone) would leave no such moment. Returns false, the file its owner's alone,
/// when they cannot be carried: `source` belongs to another account (what its group and mode allow
/// would then differ), its group cannot be given, its ACL cannot be copied, or they keep changing.
func carryPermissions(from source: Int32, to descriptor: Int32) -> Bool {
    for _ in 0..<carryAttempts {
        var before = stat()
        // A volume without ACLs has none to carry
        let carried = fstat(source, &before) == 0 && before.st_uid == geteuid()
            && fchown(descriptor, uid_t.max, before.st_gid) == 0
            && carryAcl(from: source, to: descriptor)
            && fchmod(descriptor, before.st_mode & 0o7777) == 0
        guard carried else { break }
        var after = stat()
        // Nothing changed it while its permissions were read and set: its change time would have moved
        if fstat(source, &after) == 0, sameChangeTime(before, after) { return true }
        // Changed meanwhile: its owner's alone again, then read once more
        keepPrivate(descriptor)
    }
    keepPrivate(descriptor)
    return false
}

/// Give the file open at `descriptor` exactly the ACL of the file open at `source`: every entry, the
/// ones it inherited from its folder included (a copy by `fcopyfile` leaves those out, and a denial
/// among them would be lost: someone the earlier Handout kept out could read the new one). A source
/// without an ACL, or a volume without ACLs, leaves the new file without one. Called by
/// `carryPermissions` before it gives the mode. Returns false when the ACL cannot be read or given.
func carryAcl(from source: Int32, to descriptor: Int32) -> Bool {
    if let acl = acl_get_fd(source) {
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        return acl_set_fd(descriptor, acl) == 0
    }
    let failure = errno
    // None to carry: the new file must have none either. Any other failure to read it is one
    guard failure == ENOENT || failure == ENOTSUP || failure == EOPNOTSUPP else { return false }
    return clearInheritedAcl(descriptor) == nil
}

/// Make the file open at `descriptor` its owner's alone again: mode 0600 and no ACL.
func keepPrivate(_ descriptor: Int32) {
    fchmod(descriptor, 0o600)
    _ = clearInheritedAcl(descriptor)
}

/// Publish on a volume without exclusive renames (exFAT, some network shares): a new file only,
/// created exclusively and written in place; an existing one is never replaced there. The write is the
/// publication: the file is readable by its owner alone, without the ACL its folder hands down, until
/// it is whole. A stop between two chunks (`mayContinue`) or a failed write leaves what was written,
/// and the run says what may remain there, to be looked at before it is removed: this volume cannot
/// remove only this run's own file, and nothing in it is erased either (another program may write
/// into it, or put its own file there, meanwhile). Once whole, the path must still name this file and
/// the file must hold exactly what was written (`holds`), or nothing is reported as published. After
/// that read `mayPublish` is asked, as before a rename: a stop made meanwhile leaves the file its
/// owner's alone and unpublished, and otherwise the watchdogs leave the last steps (its permissions,
/// a last read of the file and look at its path) to this worker, so a stopped run never reports a
/// Handout.
func publishWithoutRenames(_ data: Data, to target: String, writePauseMs: Int, writingInPlace: (String) -> Void,
                           mayContinue: (Int) -> Bool, mayPublish: () -> Bool) -> Publication {
    var present = stat()
    guard lstat(target, &present) != 0 else {
        return .failed("the volume of \(target) cannot replace a file safely (it has no atomic rename): remove the earlier Handout first, or choose an --out on another volume")
    }
    writingInPlace(target)
    // dw may have ended, or the run's time may be up, while the exclusive rename was tried
    guard mayContinue(0) else { return .cancelled }
    // Read again through this descriptor once written (`holds`)
    let created = open(target, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    guard created >= 0 else { return .failed("could not create \(target): \(errnoText())") }
    defer { close(created) }
    // What the folder hands down, given back once the file is whole. None to give back without an ACL
    // (or on a volume without ACLs); any other failure to read it keeps the file its owner's alone
    let inherited = acl_get_fd(created)
    let readFailure = errno
    let inheritedUnread = inherited == nil && readFailure != ENOENT && readFailure != ENOTSUP && readFailure != EOPNOTSUPP
    defer { if let inherited { acl_free(UnsafeMutableRawPointer(inherited)) } }
    // What a stop or a failed write leaves: the file as written so far, its owner's alone. Neither its
    // path nor its content is removed, and the run says what may be there. The path is named for
    // removal only as something to look at first: another program may put its own file there, now
    // (said as such) or after this look
    func endWithout(stopped: Bool, whole: Bool = false, _ what: String) -> Publication {
        var ours = stat()
        let replaced = fstat(created, &ours) == 0 && !isAtPath(target, ours)
        let remains = whole ? "the Handout written at \(target) was not published: it remains, readable by you alone"
                            : "a partly written Handout may remain at \(target)"
        let left = replaced
            ? "another program replaced or removed \(target) meanwhile: what is there now stays"
            : "\(remains) (this volume cannot remove it safely): \(confirmBeforeRemoving)"
        return stopped ? .cancelledLeaving(left) : .failed("\(what); \(left)")
    }
    // An ACL the folder hands down would let others read the file while it is written: it goes before a
    // byte is written, as in publish (a volume without ACLs has none to remove)
    if let reason = clearInheritedAcl(created) {
        return endWithout(stopped: false, "could not prepare \(target): its inherited ACL could not be removed (\(reason))")
    }
    let handle = FileHandle(fileDescriptor: created, closeOnDealloc: false)
    var offset = 0
    while offset < data.count {
        guard mayContinue(offset) else { return endWithout(stopped: true, "the export stopped while \(target) was written") }
        let end = min(offset + publishChunkBytes, data.count)
        do {
            try handle.write(contentsOf: data.subdata(in: offset..<end))
        } catch {
            return endWithout(stopped: false, "could not write \(target): \(describe(error))")
        }
        offset = end
        // Test only (input.json limits.writePauseMs): a pause standing in for a slow volume
        if writePauseMs > 0 { Thread.sleep(forTimeInterval: Double(writePauseMs) / 1000) }
    }
    guard mayContinue(offset) else { return endWithout(stopped: true, "the export stopped while \(target) was written") }
    // Written by descriptor: the path must still name this file, or another program's file would be
    // reported as the Handout. One put in its place stays as it is
    var ours = stat()
    guard fstat(created, &ours) == 0 else {
        return endWithout(stopped: false, "could not look at \(target) once written: \(errnoText())")
    }
    guard isAtPath(target, ours) else {
        return .failed("another program replaced \(target) while the Handout was written there: that file stays, and nothing was published")
    }
    // The file lay at the target all the while: it must still hold exactly what was written, or a save
    // another program made into it would be reported as the Handout. Such a save stays as it is
    guard holds(created, size: data.count, digest: SHA256.hash(data: data)) else {
        return .failed("another program saved into \(target) while the Handout was written there: that save stays, and nothing was published")
    }
    // Test only (input.json limits.writePauseMs): a pause standing in for a volume slow to answer that read
    if writePauseMs > 0 { Thread.sleep(forTimeInterval: Double(writePauseMs) / 1000) }
    // The run may have been stopped during that read (its time, dw gone): asked last, as before a
    // rename. A stopped run widens no permissions and reports no Handout
    guard mayPublish() else {
        return endWithout(stopped: true, whole: true, "the export stopped once \(target) was written")
    }
    // Whole: what any new file there gets, the ACL its folder hands down and the usual permissions
    let aclRestored = !inheritedUnread && (inherited.map { acl_set_fd(created, $0) == 0 } ?? true)
    if aclRestored { fchmod(created, newFileMode()) }
    // Read once more, then the name looked at last: a save made into the file, or a file put there,
    // during the steps above is not the Handout that was checked. Either stays as it is
    guard holds(created, size: data.count, digest: SHA256.hash(data: data)) else {
        return .failed("another program saved into \(target) while the Handout was written there: that save stays, and nothing was published")
    }
    guard isAtPath(target, ours) else {
        return .failed("another program replaced \(target) while the Handout was written there: that file stays, and nothing was published")
    }
    return .published(warnings: aclRestored ? [] : ["the ACL its folder gives its files could not be given to \(target): only you can read it"])
}

/// Where the verification copy was written, or why it could not be.
enum VerificationCopy {
    case written(URL)
    case failed(String)
}

/// Write the finished Handout where the verify view opens it: `handout.html`, created exclusively in a
/// folder made for this check alone inside `explainDir` (`makeOwnedFolder`). A file of any name already
/// in the explain folder is never written over, and the view may read that folder alone, as the
/// colleague's browser has the one file. Called by `Renderer.verify` off the main queue; the folder
/// goes once the check is done, or with dw's scratch folder, which holds `explainDir`, when the run
/// ends before.
func writeVerificationCopy(_ data: Data, in explainDir: URL) -> VerificationCopy {
    let folder = explainDir.appendingPathComponent("handout-verify-\(UUID().uuidString)")
    if let reason = makeOwnedFolder(folder.path) { return .failed("could not create \(folder.path): \(reason)") }
    let copy = folder.appendingPathComponent("handout.html")
    let descriptor = open(copy.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
        let reason = errnoText()
        rmdir(folder.path)
        return .failed("could not write \(copy.path): \(reason)")
    }
    defer { close(descriptor) }
    do {
        try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).write(contentsOf: data)
    } catch {
        unlink(copy.path)
        rmdir(folder.path)
        return .failed("could not write \(copy.path): \(describe(error))")
    }
    return .written(copy)
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
    /// Test only (input.json limits.writePauseMs): a pause after each chunk of the Handout is written,
    /// and after the rename that publishes it.
    let writePauseMs: Int
    /// Test only (input.json limits.digestLimitBytes): the largest earlier Handout whose content is read.
    let digestLimit: Int
    /// Page number → built page, relative to explainDir.
    let builtPages: [Int: String]
    let window: NSWindow
    let builderView: WKWebView
    let pageView: WKWebView
    var verifyView: WKWebView?
    /// The copy the verify view opened (`writeVerificationCopy`): removed with its folder once checked.
    var verifyCopy: URL?
    var builderStarted = false
    var pendingRender: PendingRender?
    var pendingVerify: PendingVerify?
    /// The log, opened and written on `logQueue` alone.
    var logHandle: FileHandle?
    /// Log lines are written in order on a queue of their own: a log on a volume that stops answering
    /// never holds up the run's watchdogs on the main queue.
    let logQueue = DispatchQueue(label: "dw.handout.log")
    /// Shared with the worker that publishes (see `PublicationGate`).
    let publicationGate = PublicationGate()
    /// Whether a stop already waits for the worker writing the Handout (`stopRun`).
    var workerStopScheduled = false
    /// Whether the Handout was handed to the worker that publishes: WebKit is no longer needed then.
    var publicationStarted = false
    /// Why a watchdog stopped the run while the worker wrote: what the run says once the worker
    /// reports that it stopped (`report`), however the clock reads by then.
    var stopReason: String?
    /// When the run started: publication looks at the run's time itself (`pastDeadline`).
    let startedAt = Date()

    init(input: [String: Any], explainDir: URL, distDir: URL, out: String, logPath: String,
         pageLimitMs: Int, runLimitMs: Int, parentCheckMs: Int, writePauseMs: Int = 0,
         digestLimit: Int = digestLimitBytes, builtPages: [Int: String]) {
        self.input = input
        self.explainDir = explainDir
        self.distDir = distDir
        self.out = out
        self.logPath = logPath
        self.pageLimitMs = pageLimitMs
        self.runLimitMs = runLimitMs
        self.parentCheckMs = parentCheckMs
        self.writePauseMs = writePauseMs
        self.digestLimit = digestLimit
        self.builtPages = builtPages
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
        // Opened on the log's own queue, before any line is queued there
        logQueue.async {
            FileManager.default.createFile(atPath: self.logPath, contents: nil)
            self.logHandle = FileHandle(forWritingAtPath: self.logPath)
        }
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
        let entry = Data("\(ISO8601DateFormatter().string(from: Date())) \(line)\n".utf8)
        // A log that cannot be written (a full volume) never keeps the result from dw
        logQueue.async { try? self.logHandle?.write(contentsOf: entry) }
    }

    /// Print the result line for dw and exit (`finish`), after the log lines already queued are
    /// written, or logFlushWaitMs, whichever comes first: a log that stalls never keeps the result from
    /// dw. Every end of the run comes through here.
    func end(_ result: [String: Any], code: Int32) -> Never {
        let flushed = DispatchSemaphore(value: 0)
        logQueue.async { flushed.signal() }
        _ = flushed.wait(timeout: .now() + .milliseconds(logFlushWaitMs))
        finish(result, code: code)
    }

    func schedule(after milliseconds: Int, _ action: @escaping () -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: item)
        return item
    }

    /// End the run: the host could not finish (a limit, a crash, a broken builder).
    func failRenderer(_ message: String, page: Int? = nil) -> Never {
        log("HANDOUT_RENDERER: \(message)")
        end(failure(code: "HANDOUT_RENDERER", message: message, page: page, log: logPath), code: 1)
    }

    func start() {
        log("start: \(builtPages.count) page(s), limits \(pageLimitMs) ms per page, \(runLimitMs) ms per run")
        _ = schedule(after: runLimitMs) { self.enforceRunLimit() }
        watchParent()
        builderView.loadFileURL(distDir.appendingPathComponent("builder.html"), allowingReadAccessTo: distDir)
    }

    /// Stop without publishing once dw's process (input.json parentPid) is gone: dw was killed or its
    /// terminal closed, nobody waits for this export, and it must not write a file minutes later.
    /// Runs on the main queue while a worker publishes; a rename under way is left to finish
    /// (`PublicationGate`), so a stop never cuts a replace in half.
    func watchParent() {
        guard input["parentPid"] is Int else { return }
        // Looked at once now (dw may be gone already), then every parentCheckMs; publish looks once more
        stopIfParentGone()
        _ = schedule(after: parentCheckMs) { self.watchParent() }
    }

    /// End the run without publishing when dw's process (input.json parentPid) is gone. Called by
    /// watchParent, and by handleOutcome right before publishing: dw may end after the last look. A
    /// rename under way is left to finish (watchParent looks again).
    func stopIfParentGone() {
        guard !parentIsAlive(), let parent = input["parentPid"] as? Int else { return }
        stopRun("dw (process \(parent)) ended before the export finished: nothing was published")
    }

    /// End the run once its time (runMs) is up. Called by the run's timer; a rename under way is left
    /// to finish, looked at again every commitRecheckMs.
    func enforceRunLimit() {
        guard stopRun("the export took longer than \(runLimitMs / 1000) s") else {
            _ = schedule(after: commitRecheckMs) { self.enforceRunLimit() }
            return
        }
    }

    /// Stop the run, saying MESSAGE, as far as publication allows (`PublicationGate.Stop`): at once
    /// when nothing is being published; through the worker while it writes (it removes its partly
    /// written file, then reports), or after workerStopWaitMs when the volume keeps it from answering;
    /// not while a rename is under way within its grace. Returns false when the stop has to wait for a
    /// rename (the caller looks again).
    @discardableResult
    func stopRun(_ message: String) -> Bool {
        switch publicationGate.stop() {
        case .now:
            failRenderer(message, page: pendingRender?.page)
        case .afterWorker(let path, let written, let total, let inPlace):
            guard !workerStopScheduled else { return true }
            workerStopScheduled = true
            let reason = message.hasSuffix("nothing was published") ? message : "\(message): nothing was published"
            stopReason = reason
            // What may be left, by how far the write had come when the volume stopped answering: the
            // Handout written at the target itself (a volume without exclusive renames), else in the
            // run's own folder beside it
            let left: String
            if inPlace {
                // Nothing here can look at the path any more: it is named for removal only as
                // something to look at first, as another program may have saved its own file there
                if written == nil {
                    left = "the volume did not answer before \(path) was written: an empty file may remain there; \(confirmBeforeRemoving)"
                } else if (written ?? 0) < total {
                    left = "the volume did not answer, so a partly written Handout may remain at \(path): \(confirmBeforeRemoving)"
                } else {
                    left = "the volume did not answer, so the Handout written at \(path) was not published: it may remain, readable by you alone; \(confirmBeforeRemoving)"
                }
            } else if written == nil {
                left = "the volume did not answer before the Handout was written: the folder \(path) may remain, empty; remove it if it is there"
            } else if (written ?? 0) < total {
                left = "the volume did not answer, so a partly written Handout may remain in \(path): remove that folder"
            } else {
                left = "the volume did not answer, so the Handout, written but not published, may remain in \(path): remove that folder"
            }
            _ = schedule(after: workerStopWaitMs) { self.failRenderer("\(reason); \(left)") }
            return true
        case .afterCommit:
            return false
        case .interrupted:
            failRenderer(stalledMessage())
        }
    }

    /// What a run the worker stopped says: the watchdog's reason when one stopped it, else the clock's.
    func cancelledMessage() -> String {
        stopReason ?? (pastDeadline() ? "the export took longer than \(runLimitMs / 1000) s: nothing was published"
                                      : "dw ended before the export finished: nothing was published")
    }

    /// What a stop that cut into a rename says: where the files may be.
    func stalledMessage() -> String {
        "the volume of \(out) stopped answering while the Handout was being published: look at \(out) and the hidden .dw-handout folder beside it"
    }

    /// Whether the run's time (runMs) is up: the worker that publishes looks at the clock itself before
    /// each rename, as the run's timer may fire while it writes.
    func pastDeadline() -> Bool {
        Date().timeIntervalSince(startedAt) * 1000 > Double(runLimitMs)
    }

    /// Whether dw's process (input.json parentPid) is still there; true when there is none to watch.
    func parentIsAlive() -> Bool {
        guard let parent = input["parentPid"] as? Int, parent > 1 else { return true }
        return !(kill(pid_t(parent), 0) != 0 && errno == ESRCH)
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
            end(["v": protocolVersion, "ok": false, "diagnostics": outcome["diagnostics"] ?? [], "log": logPath], code: 1)
        }
        guard let html = outcome["html"] as? String else { failRenderer("the builder returned no Handout") }
        // dw may have ended since the last look: nobody waits for this file any more
        stopIfParentGone()
        // Published on a queue of its own: a volume that stalls a write leaves the run's timer and the
        // look at dw's process running here. Each rename asks the gate first
        let data = Data(html.utf8)
        let target = out
        let staging = Staging(for: target)
        let pause = writePauseMs
        let limit = digestLimit
        publicationGate.beginWrite(in: staging.folder, total: data.count)
        publicationStarted = true
        DispatchQueue.global(qos: .userInitiated).async {
            let stillWanted = { self.parentIsAlive() && !self.pastDeadline() }
            let publication = publish(data, to: target, staging: staging, writePauseMs: pause, digestLimit: limit,
                                      keepGoing: { !self.publicationGate.isStopped() && stillWanted() },
                                      mayContinue: { self.publicationGate.mayContinue(written: $0, stillWanted) },
                                      mayPublish: { self.publicationGate.allowCommit(stillWanted) },
                                      commitEnded: { self.publicationGate.endCommit() },
                                      writingInPlace: { self.publicationGate.writeInPlace(at: $0) })
            DispatchQueue.main.async { self.report(publication, outcome: outcome) }
        }
    }

    /// Say how the publication ended, as dw reads it. Called on the main queue by the worker that
    /// published.
    func report(_ publication: Publication, outcome: [String: Any]) -> Never {
        switch publication {
        case .published(let kept):
            log("published: \(out)")
            let warnings = (outcome["warnings"] as? [[String: Any]] ?? []) + kept.map { ["message": $0] }
            end(["v": protocolVersion, "ok": true, "path": out, "pages": outcome["pages"] ?? 0,
                    "diagrams": outcome["diagrams"] ?? 0, "warnings": warnings], code: 0)
        case .cancelled:
            // The watchdog's reason when one stopped the run; else the worker stopped by itself
            failRenderer(cancelledMessage())
        case .cancelledLeaving(let left):
            failRenderer("\(cancelledMessage()); \(left)")
        case .isFolder:
            end(failure(code: "HANDOUT_OUT_EXISTS", message: "\(out) is a folder: name a file", log: logPath), code: 1)
        case .notAHandout:
            end(failure(code: "HANDOUT_OUT_EXISTS",
                        message: "\(out) holds a file that is not a Handout: it was left as it was; choose another --out",
                        log: logPath), code: 1)
        case .failed(let reason):
            end(failure(code: "HANDOUT_OUT_EXISTS", message: "\(reason); choose another --out", log: logPath), code: 1)
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
        // The time limit runs from the request, and the copy is written off the main queue, where the
        // limits run: a write that stalls is caught by them
        let timer = schedule(after: pageLimitMs) {
            self.failRenderer("the finished Handout did not open within \(self.pageLimitMs / 1000) s")
        }
        pendingVerify = PendingVerify(probe: probe, reply: reply, timer: timer)
        log("verify: writing the finished Handout (\(html.utf8.count) bytes)")
        let data = Data(html.utf8)
        let explainDir = self.explainDir
        DispatchQueue.global(qos: .userInitiated).async {
            let written = writeVerificationCopy(data, in: explainDir)
            DispatchQueue.main.async {
                let file: URL
                switch written {
                case .failed(let reason):
                    self.failRenderer("the finished Handout could not be written for verification: \(reason)")
                case .written(let copy):
                    file = copy
                }
                self.verifyCopy = file
                // A plain view, as the colleague's browser: no channel, nothing injected
                let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 1000), configuration: WKWebViewConfiguration())
                view.navigationDelegate = self
                self.window.contentView?.addSubview(view)
                self.verifyView = view
                self.log("verify: opening the finished Handout")
                view.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
            }
        }
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
                    // The copy opened for the check is of no further use: only the published file stays.
                    // Removed off the main queue, like every other file operation of the run, and before
                    // the builder hears back, so it is gone before the run can end. Its folder is the
                    // check's own: nothing else is in it
                    let copy = self.verifyCopy
                    self.verifyCopy = nil
                    DispatchQueue.global(qos: .utility).async {
                        if let copy {
                            unlink(copy.path)
                            rmdir(copy.deletingLastPathComponent().path)
                        }
                        DispatchQueue.main.async { pending.reply(["type": "verified", "probe": probe], nil) }
                    }
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
        // Once the Handout is being published WebKit has done its part: the worker finishes or rolls back
        guard !publicationStarted else { return log("\(name(of: webView)) could not be loaded (ignored: publishing)") }
        failRenderer("\(name(of: webView)) could not be loaded: \(describe(error))", page: pendingRender?.page)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !publicationStarted else { return log("the web content process of \(name(of: webView)) ended (ignored: publishing)") }
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
                        parentCheckMs: (limits["parentMs"] as? Int) ?? defaultParentCheckMs,
                        writePauseMs: (limits["writePauseMs"] as? Int) ?? 0,
                        digestLimit: (limits["digestLimitBytes"] as? Int) ?? digestLimitBytes, builtPages: builtPages)
renderer.start()
withExtendedLifetime(renderer) { app.run() }
