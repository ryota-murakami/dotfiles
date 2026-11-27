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
//            ─▶ exclusive create; a Handout there ─▶ RENAME_SWAP, check the swapped-out file by
//            descriptor, swap back if it is no Handout ──▶ HANDOUT_OUT_EXISTS. The new file stays 0600
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
    /// removes TEMPORARY and reports); wait for a rename under way; or end the run in the middle of a
    /// rename that outlasted its grace.
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

    /// Said on the main queue before the worker starts: the file it writes first, beside the target,
    /// and how many bytes it will hold.
    func beginWrite(_ temporary: String, total bytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        writing = temporary
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

    /// Asked by the worker before each rename: whether it may rename now. False once a watchdog has
    /// stopped the run, or when `stillWanted` says dw is gone or the run's time is up.
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

/// Remove the ACL a new file inherited from its folder, by descriptor, before a byte is written.
/// Returns nil once it has none (or the volume has no ACLs), else why it could not be removed: errno
/// is read right after the call that failed.
func clearInheritedAcl(_ descriptor: Int32) -> String? {
    guard let emptyAcl = acl_init(0) else { return errnoText() }
    defer { acl_free(UnsafeMutableRawPointer(emptyAcl)) }
    guard acl_set_fd(descriptor, emptyAcl) != 0 else { return nil }
    let failure = errno
    return failure == ENOTSUP || failure == EOPNOTSUPP ? nil : String(cString: strerror(failure))
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
/// A file there that is not a Handout is left before anything is written. The new file is written
/// beside the target, readable by its owner alone, and stays so until its final permissions are
/// known. A missing target is created exclusively (RENAME_EXCL), then given a new file's usual
/// permissions. An existing Handout is swapped with the new file in one step (RENAME_SWAP); the file
/// swapped out is judged by descriptor and, when it does not start as a Handout (one that appeared
/// meanwhile), swapped back. A replaced Handout's permissions, group and ACL are read from that file
/// itself and set on the new one by descriptor: who could not read it cannot read the new one, and
/// when they cannot be carried the earlier Handout goes back. The file is written without the ACL its
/// folder hands down, so nobody reads it half written; a new Handout gets that ACL back. It is written
/// at `temporary` (`temporaryPath`) a chunk at a time, and before each and after the last
/// `mayContinue` (given the bytes written so far) says whether to go on; before each rename `mayPublish` says whether dw still waits and the run's time is not up. A file left at the
/// temporary path is removed only when it holds exactly the bytes written, and a save made into the
/// replaced Handout since it was first looked at is kept: another program's save is never deleted. On a volume without exclusive renames (exFAT, some network shares) only a
/// new file can be published, created exclusively.
func publish(_ data: Data, to target: String, temporary: String, writePauseMs: Int = 0, keepGoing: () -> Bool = { true },
             mayContinue: (Int) -> Bool, mayPublish: () -> Bool, writingInPlace: (String) -> Void) -> Publication {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory), isDirectory.boolValue {
        return .isFolder
    }
    var present = stat()
    let hadTarget = lstat(target, &present) == 0
    if hadTarget, !isHandout(atPath: target) { return .notAHandout }
    // What the earlier Handout held when first looked at: a later change of its change time alone (an
    // extended attribute, a chmod) is no save when the content is still this
    let firstDigest = hadTarget && present.st_size <= off_t(digestLimitBytes)
        ? contentDigest(atPath: target, keepGoing: keepGoing) : nil
    let folder = (target as NSString).deletingLastPathComponent
    let descriptor = open(temporary, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { return .failed("could not write in \(folder): \(errnoText())") }
    // The descriptor stays open across the renames: permissions are set on this file, wherever it is
    defer { close(descriptor) }
    // An ACL the folder hands down would let others read the file while it is written: it is set aside
    // before a byte is written, and given back to a new Handout only (a replaced one takes the earlier
    // Handout's ACL). A volume without ACLs has none
    let inherited = acl_get_fd(descriptor)
    defer { if let inherited { acl_free(UnsafeMutableRawPointer(inherited)) } }
    if let reason = clearInheritedAcl(descriptor) {
        unlink(temporary)
        return .failed("could not prepare the Handout in \(folder): its inherited ACL could not be removed (\(reason))")
    }
    // A chunk at a time: between two, a stop (the run's time, dw gone) ends the write and removes it
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
    var offset = 0
    while offset < data.count {
        guard mayContinue(offset) else {
            unlink(temporary)
            return .cancelled
        }
        let end = min(offset + publishChunkBytes, data.count)
        do {
            try handle.write(contentsOf: data.subdata(in: offset..<end))
        } catch {
            unlink(temporary)
            return .failed("could not write in \(folder): \(describe(error))")
        }
        offset = end
        // Test only (input.json limits.writePauseMs): a pause standing in for a slow volume
        if writePauseMs > 0 { Thread.sleep(forTimeInterval: Double(writePauseMs) / 1000) }
    }
    // Once more after the last write: a stop meanwhile still removes the file
    guard mayContinue(offset) else {
        unlink(temporary)
        return .cancelled
    }
    var written = stat()
    guard fstat(descriptor, &written) == 0 else {
        let reason = errnoText()
        unlink(temporary)
        return .failed("could not write in \(folder): \(reason)")
    }
    // dw may have ended, or the run's time may be up, while the file was written (a slow volume)
    guard mayPublish() else {
        unlink(temporary)
        return .cancelled
    }
    // Nothing there yet: create it, failing if something appeared in the meantime
    if renamex_np(temporary, target, UInt32(RENAME_EXCL)) == 0 {
        // What any new file there gets: the ACL its folder hands down, then the usual permissions. An
        // ACL that cannot be given back may have denied someone: the file then stays its owner's alone
        let aclRestored = inherited.map { acl_set_fd(descriptor, $0) == 0 } ?? true
        // Restrictive (0600) if this fails: never wider than intended
        if aclRestored { fchmod(descriptor, newFileMode()) }
        return .published(warnings: aclRestored ? [] : ["the ACL \(folder) gives its files could not be given to the Handout: only you can read it"])
    }
    let exclusiveError = errno
    if exclusiveError == ENOTSUP || exclusiveError == ENOSYS {
        unlink(temporary)
        return publishWithoutRenames(data, to: target, writePauseMs: writePauseMs, writingInPlace: writingInPlace,
                                     mayContinue: mayContinue)
    }
    guard exclusiveError == EEXIST else {
        unlink(temporary)
        return .failed("could not create \(target): \(String(cString: strerror(exclusiveError)))")
    }
    guard mayPublish() else {
        unlink(temporary)
        return .cancelled
    }
    // Looked at once more right before the swap: a save into the earlier Handout while this one was
    // written changed its change time, which nothing else here touches until the swap renames it
    var beforeSwap = stat()
    let lookedAgain = lstat(target, &beforeSwap) == 0
    // A Handout is there: swap, then look at what was swapped out
    guard renamex_np(temporary, target, UInt32(RENAME_SWAP)) == 0 else {
        let reason = errnoText()
        unlink(temporary)
        return .failed("could not replace \(target): \(reason)")
    }
    let theirs = open(temporary, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    var replaced = stat()
    if theirs >= 0, fstat(theirs, &replaced) == 0, startsAsHandout(theirs) {
        defer { close(theirs) }
        // Its group, its ACL, then its permissions, set on the published file by descriptor: the file
        // stays readable by its owner alone until all three are right. A group this user cannot give
        // would move the earlier group's members to "others", who may read what that group could
        // not: the earlier Handout then goes back, as when its ACL cannot be carried
        var carried = fchown(descriptor, uid_t.max, replaced.st_gid) == 0
        // A volume without ACLs has none to carry
        if carried {
            carried = fcopyfile(theirs, descriptor, nil, copyfile_flags_t(COPYFILE_ACL)) == 0 || errno == ENOTSUP
        }
        if carried { carried = fchmod(descriptor, replaced.st_mode & 0o7777) == 0 }
        if carried {
            // A save another program made into the earlier Handout meanwhile stays where it is: the file
            // swapped out must be the one looked at before anything was written (`present`), unchanged
            // since, and unchanged while its permissions were read
            // A Handout that appeared there while this one was written (another export) stays too
            guard hadTarget else {
                return .published(warnings: ["a Handout appeared at \(target) while this one was written: it is kept at \(temporary)"])
            }
            var now = stat()
            // Unchanged while this one was written (its change time too: no rename yet), the same file
            // swapped out (the swap changed its change time), and unchanged since (change time too)
            let stampsKept = lookedAgain && sameFile(present, beforeSwap) && sameContentStamp(present, beforeSwap)
                && sameFile(beforeSwap, replaced) && sameContentStamp(beforeSwap, replaced)
                && fstat(theirs, &now) == 0 && sameContentStamp(now, replaced)
            // A change time that moved with size and modification time kept: its content decides (a
            // metadata change keeps it, a save that kept both stamps does not)
            let changeTimesKept = sameChangeTime(present, beforeSwap) && sameChangeTime(now, replaced)
            let unchanged = stampsKept && (changeTimesKept || (firstDigest != nil && contentDigest(theirs) == firstDigest))
            if !unchanged {
                return .published(warnings: ["the earlier Handout was saved while it was replaced: that save is kept at \(temporary)"])
            }
            // The earlier Handout goes, as the export was asked to replace it: a copy kept beside would
            // keep what a new export may have been made to remove (a page taken out). A write through a
            // descriptor opened before and landing after the look above is lost, as with any file
            // replaced by a rename
            unlink(temporary)
            return .published(warnings: [])
        }
        // Who may read it could not be kept: the earlier Handout goes back, the new file goes
        guard renamex_np(temporary, target, UInt32(RENAME_SWAP)) == 0 else {
            return .failed("the permissions of the earlier Handout could not be kept, and it could not be put back at \(target): it is at \(temporary)")
        }
        if isUntouched(temporary, written: written, data: data) { unlink(temporary) }
        return .failed("the permissions of the earlier Handout at \(target) could not be carried over: it was left as it was")
    }
    if theirs >= 0 { close(theirs) }
    // Not a Handout: put it back where it was; the temporary path then holds the new file again
    guard renamex_np(temporary, target, UInt32(RENAME_SWAP)) == 0 else {
        return .failed("could not put the earlier file back at \(target) (\(errnoText())): it is at \(temporary)")
    }
    guard isUntouched(temporary, written: written, data: data) else {
        return .failed("\(target) was saved again while the earlier file was put back: it holds the earlier file, and the newer save is kept at \(temporary)")
    }
    unlink(temporary)
    return .notAHandout
}

/// Where the Handout for TARGET is written first: beside it, named after it (a file an interrupted run
/// leaves there says what it belongs to), hidden, and unique to this run.
func temporaryPath(for target: String) -> String {
    let folder = (target as NSString).deletingLastPathComponent
    let name = (target as NSString).lastPathComponent
    return (folder as NSString).appendingPathComponent(".\(name).dw-handout-\(getpid())-\(UUID().uuidString).tmp")
}

/// Whether the file at `path` is still the one this run created (same device and inode) holding only
/// the start of `data`: what a write that failed part way leaves. Anything else (a save another program
/// made into it, a file put in its place) is not this run's to remove.
func isOwnPartialWrite(_ path: String, created: stat, data: Data) -> Bool {
    var now = stat()
    guard lstat(path, &now) == 0, now.st_dev == created.st_dev, now.st_ino == created.st_ino,
          now.st_size <= off_t(data.count), let content = FileManager.default.contents(atPath: path) else { return false }
    return data.prefix(content.count) == content
}

/// Publish on a volume without exclusive renames (exFAT, some network shares): a new file only,
/// created exclusively and written in place; an existing one is never replaced there. The write is the
/// publication: the file is readable by its owner alone, without the ACL its folder hands down, until
/// it is whole, and a stop between two chunks (`mayContinue`) removes what was written. Only the start
/// of `data` in this run's own file is ever removed: a save another program made into it stays.
func publishWithoutRenames(_ data: Data, to target: String, writePauseMs: Int, writingInPlace: (String) -> Void,
                           mayContinue: (Int) -> Bool) -> Publication {
    var present = stat()
    guard lstat(target, &present) != 0 else {
        return .failed("the volume of \(target) cannot replace a file safely (it has no atomic rename): remove the earlier Handout first, or choose an --out on another volume")
    }
    writingInPlace(target)
    // dw may have ended, or the run's time may be up, while the exclusive rename was tried
    guard mayContinue(0) else { return .cancelled }
    let created = open(target, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    guard created >= 0 else { return .failed("could not create \(target): \(errnoText())") }
    defer { close(created) }
    var mine = stat()
    fstat(created, &mine)
    let inherited = acl_get_fd(created)
    defer { if let inherited { acl_free(UnsafeMutableRawPointer(inherited)) } }
    // What a stop or a failed write leaves: nothing, unless another program changed the file meanwhile
    func endWithout(_ outcome: Publication, _ what: String) -> Publication {
        guard isOwnPartialWrite(target, created: mine, data: data), unlink(target) == 0 else {
            return .failed("\(what), and another program changed \(target) meanwhile: it was left as it is")
        }
        return outcome
    }
    // An ACL the folder hands down would let others read the file while it is written: it goes before a
    // byte is written, as in publish (a volume without ACLs has none to remove)
    if let reason = clearInheritedAcl(created) {
        return endWithout(.failed("could not prepare \(target): its inherited ACL could not be removed (\(reason))"),
                          "could not prepare \(target) (its inherited ACL could not be removed)")
    }
    let handle = FileHandle(fileDescriptor: created, closeOnDealloc: false)
    var offset = 0
    while offset < data.count {
        guard mayContinue(offset) else { return endWithout(.cancelled, "the export stopped while \(target) was written") }
        let end = min(offset + publishChunkBytes, data.count)
        do {
            try handle.write(contentsOf: data.subdata(in: offset..<end))
        } catch {
            return endWithout(.failed("could not write \(target): \(describe(error))"), "could not write \(target) (\(describe(error)))")
        }
        offset = end
        // Test only (input.json limits.writePauseMs): a pause standing in for a slow volume
        if writePauseMs > 0 { Thread.sleep(forTimeInterval: Double(writePauseMs) / 1000) }
    }
    guard mayContinue(offset) else { return endWithout(.cancelled, "the export stopped while \(target) was written") }
    // Whole: what any new file there gets, the ACL its folder hands down and the usual permissions
    let aclRestored = inherited.map { acl_set_fd(created, $0) == 0 } ?? true
    if aclRestored { fchmod(created, newFileMode()) }
    return .published(warnings: aclRestored ? [] : ["the ACL its folder gives its files could not be given to \(target): only you can read it"])
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
    /// Test only (input.json limits.writePauseMs): a pause after each chunk of the Handout is written.
    let writePauseMs: Int
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
         pageLimitMs: Int, runLimitMs: Int, parentCheckMs: Int, writePauseMs: Int = 0, builtPages: [Int: String]) {
        self.input = input
        self.explainDir = explainDir
        self.distDir = distDir
        self.out = out
        self.logPath = logPath
        self.pageLimitMs = pageLimitMs
        self.runLimitMs = runLimitMs
        self.parentCheckMs = parentCheckMs
        self.writePauseMs = writePauseMs
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
            // What may be beside the target, by how far the write had come when the volume stopped answering
            let left: String
            if written == nil {
                left = "the volume did not answer before the Handout was written: \(path) may remain, empty; remove it if it is there"
            } else if (written ?? 0) < total {
                left = "the volume did not answer, so a partly written \(path) may remain: remove it"
            } else if inPlace {
                left = "the volume did not answer, so \(path) is written but may be readable by you alone: check its permissions"
            } else {
                left = "the volume did not answer, so \(path), written but not published, may remain: remove it"
            }
            _ = schedule(after: workerStopWaitMs) { self.failRenderer("\(reason); \(left)") }
            return true
        case .afterCommit:
            return false
        case .interrupted:
            failRenderer(stalledMessage())
        }
    }

    /// What a stop that cut into a rename says: where the files may be.
    func stalledMessage() -> String {
        "the volume of \(out) stopped answering while the Handout was being published: look at \(out) and the hidden .dw-handout file beside it"
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
            finish(["v": protocolVersion, "ok": false, "diagnostics": outcome["diagnostics"] ?? [], "log": logPath], code: 1)
        }
        guard let html = outcome["html"] as? String else { failRenderer("the builder returned no Handout") }
        // dw may have ended since the last look: nobody waits for this file any more
        stopIfParentGone()
        // Published on a queue of its own: a volume that stalls a write leaves the run's timer and the
        // look at dw's process running here. Each rename asks the gate first
        let data = Data(html.utf8)
        let target = out
        let temporary = temporaryPath(for: target)
        let pause = writePauseMs
        publicationGate.beginWrite(temporary, total: data.count)
        publicationStarted = true
        DispatchQueue.global(qos: .userInitiated).async {
            let stillWanted = { self.parentIsAlive() && !self.pastDeadline() }
            let publication = publish(data, to: target, temporary: temporary, writePauseMs: pause,
                                      keepGoing: { !self.publicationGate.isStopped() && stillWanted() },
                                      mayContinue: { self.publicationGate.mayContinue(written: $0, stillWanted) },
                                      mayPublish: { self.publicationGate.allowCommit(stillWanted) },
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
            finish(["v": protocolVersion, "ok": true, "path": out, "pages": outcome["pages"] ?? 0,
                    "diagrams": outcome["diagrams"] ?? 0, "warnings": warnings], code: 0)
        case .cancelled:
            // The watchdog's reason when one stopped the run; else the worker stopped by itself
            failRenderer(stopReason ?? (pastDeadline() ? "the export took longer than \(runLimitMs / 1000) s: nothing was published"
                                                       : "dw ended before the export finished: nothing was published"))
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
        // The time limit runs from the request, and the copy is written off the main queue, where the
        // limits run: a write that stalls is caught by them
        let timer = schedule(after: pageLimitMs) {
            self.failRenderer("the finished Handout did not open within \(self.pageLimitMs / 1000) s")
        }
        pendingVerify = PendingVerify(probe: probe, reply: reply, timer: timer)
        log("verify: writing the finished Handout (\(html.utf8.count) bytes)")
        let data = Data(html.utf8)
        DispatchQueue.global(qos: .userInitiated).async {
            let written = Result { try data.write(to: file) }
            DispatchQueue.main.async {
                if case .failure(let error) = written {
                    self.failRenderer("the finished Handout could not be written for verification: \(describe(error))")
                }
                // A plain view, as the colleague's browser: no channel, nothing injected
                let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 1000), configuration: WKWebViewConfiguration())
                view.navigationDelegate = self
                self.window.contentView?.addSubview(view)
                self.verifyView = view
                self.log("verify: opening the finished Handout")
                view.loadFileURL(file, allowingReadAccessTo: self.explainDir)
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
                    // the builder hears back, so it is gone before the run can end
                    let copy = self.explainDir.appendingPathComponent("handout-verify.html")
                    DispatchQueue.global(qos: .utility).async {
                        try? FileManager.default.removeItem(at: copy)
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
                        writePauseMs: (limits["writePauseMs"] as? Int) ?? 0, builtPages: builtPages)
renderer.start()
withExtendedLifetime(renderer) { app.run() }
