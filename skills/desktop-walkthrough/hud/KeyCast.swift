// Key display of the HUD: the keys the walkthrough sends, drawn large at the bottom-left corner of
// the screen, the way a screencast shows keystrokes (KeyCastr). The HUD is told each key by `dw`:
// it never reads the keyboard, so the user's own typing is never shown.
import AppKit

/// `dw press` and `dw keycast` add one line per key combination here: "<unix seconds>\t<combo>",
/// the combo as agent-desktop takes it ("cmd+shift+p"). The HUD draws each new line and never
/// writes the file; `dw start` removes it.
let keyCastPath = "\(stateDir)/keycast"

/// The key display.
///
/// Why it exists: a key the agent sends leaves no trace on screen. The page changes and the user
/// cannot tell whether a shortcut, a click or a script did it, which is the whole point when the
/// thing being taught is a shortcut (pasting an image with Command-V). Each combination is a line of
/// glyphs on a dark bezel; a new line appears at the bottom and pushes the earlier ones up, a line
/// goes after a few seconds, and a combination repeated in a row counts up on its line.
/// Created and owned by {@link HUD}, which calls {@link KeyCast.poll} from its fast timer and
/// {@link KeyCast.hide} when the user hides the HUD. The "keycast.show" setting switches it off.
final class KeyCast {
    /// One combination on screen.
    private final class Line {
        let glyphs: String
        var count = 1
        var expires: Date
        var fading = false
        let bezel = NSView()
        let label = NSTextField(labelWithString: "")
        init(glyphs: String, expires: Date) {
            self.glyphs = glyphs
            self.expires = expires
        }
    }

    /// Seconds a line stays before it fades.
    static let linger: TimeInterval = 2.5
    /// Seconds of the fade ("Reduce motion": {@link KeyCast.fadeSeconds}).
    static let fade: TimeInterval = 0.4
    /// A line written longer ago than this is not shown: the HUD was hidden or busy when it was sent.
    static let staleAfter: TimeInterval = 5
    static let maxLines = 5
    static let fontSize: CGFloat = 44
    static let margin: CGFloat = 16
    static let gap: CGFloat = 10
    static let padding = NSSize(width: 16, height: 6)

    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let root = NSView()
    /// Lines on screen, the oldest first (drawn at the top).
    private var lines: [Line] = []
    /// How far {@link keyCastPath} has been read, in bytes.
    private var offset: UInt64
    /// The status bar's frame at the last poll: the lines start above a bar that lies in their corner.
    private var barFrame: NSRect?

    init() {
        // Keys sent before this HUD started are history, not news
        offset = KeyCast.fileSize() ?? 0
        // Above app windows and the Dock; not screen-saver level (that blocks switching desktops)
        panel.level = .statusBar
        // On the desktop that is active when the key is sent, like every surface but the bar and the border
        panel.collectionBehavior = stageCollectionBehavior
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = root
    }

    private static func fileSize() -> UInt64? {
        ((try? FileManager.default.attributesOfItem(atPath: keyCastPath))?[.size] as? NSNumber)?.uint64Value
    }

    private var fadeSeconds: TimeInterval { DisplayOptions.reduceMotion ? 0.15 : KeyCast.fade }

    // MARK: reading what dw wrote

    /// Show the combinations `dw` wrote since the last call, and let the lines whose time is up fade.
    /// Called by the HUD's fast timer (every 30 ms), so a key shows as it is pressed.
    ///
    /// @param barFrame - Frame of the status bar while it is on screen: lines never cover it.
    func poll(avoiding barFrame: NSRect?) {
        self.barFrame = barFrame
        for combo in readNew() { show(combo) }
        expire()
    }

    /// The combinations added to the file since it was last read, without the stale ones.
    private func readNew() -> [String] {
        guard let size = KeyCast.fileSize() else {
            offset = 0
            return []
        }
        // Emptied or replaced: start from its beginning
        if size < offset { offset = 0 }
        guard size > offset, let handle = FileHandle(forReadingAtPath: keyCastPath) else { return [] }
        defer { handle.closeFile() }
        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()
        // Only whole lines: one still being written is read at the next poll
        guard let end = data.lastIndex(of: 0x0A) else { return [] }
        offset += UInt64(end + 1)
        let text = String(data: data.prefix(end + 1), encoding: .utf8) ?? ""
        let now = Date().timeIntervalSince1970
        return text.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { return String(line) }
            if let stamp = Double(fields[0]), now - stamp > KeyCast.staleAfter { return nil }
            return String(fields[1])
        }
    }

    // MARK: drawing

    /// Draw one combination: a new line at the bottom, or one more on the count of the newest line
    /// when it is the same combination again.
    private func show(_ combo: String) {
        guard settings.isOn("keycast.show"), !hudHidden else { return }
        let glyphs = KeyCast.glyphs(for: combo)
        guard !glyphs.isEmpty else { return }
        let expires = Date().addingTimeInterval(KeyCast.linger)
        if let last = lines.last, last.glyphs == glyphs, !last.fading {
            last.count += 1
            last.expires = expires
            last.label.attributedStringValue = KeyCast.text(glyphs, count: last.count)
            layout(animated: false)
        } else {
            let line = Line(glyphs: glyphs, expires: expires)
            build(line)
            lines.append(line)
            root.addSubview(line.bezel)
            // The corner holds a handful of lines: the oldest makes room
            while lines.count > KeyCast.maxLines { lines.removeFirst().bezel.removeFromSuperview() }
            layout(animated: true)
            line.bezel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                line.bezel.animator().alphaValue = 1
            }
        }
        panel.orderFrontOnActiveSpace()
    }

    /// Give a line its look: white glyphs on a dark rounded bezel, readable over a white page and a dark editor alike.
    private func build(_ line: Line) {
        line.bezel.wantsLayer = true
        line.bezel.layer?.cornerRadius = 12
        line.bezel.layer?.backgroundColor = NSColor.black.withAlphaComponent(surfaceAlpha(0.8)).cgColor
        if DisplayOptions.increaseContrast {
            line.bezel.layer?.borderWidth = surfaceBorderWidth
            line.bezel.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        }
        line.label.attributedStringValue = KeyCast.text(line.glyphs, count: 1)
        line.label.lineBreakMode = .byClipping
        line.bezel.addSubview(line.label)
    }

    /// The glyphs of a line as drawn: large and bold, with the count of repeats smaller after them.
    private static func text(_ glyphs: String, count: Int) -> NSAttributedString {
        let text = NSMutableAttributedString(string: glyphs, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white,
            .kern: 2,
        ])
        if count > 1 {
            text.append(NSAttributedString(string: " ×\(count)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize * 0.6, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ]))
        }
        return text
    }

    /// Size the panel to its lines and put each line in its place: the newest at the bottom, the
    /// earlier ones above it.
    ///
    /// @param animated - True when a new line pushes the others up (they slide, unless "Reduce motion" is on).
    private func layout(animated: Bool) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let sizes = lines.map { line -> NSSize in
            let size = line.label.fittingSize
            return NSSize(width: ceil(size.width) + KeyCast.padding.width * 2, height: ceil(size.height) + KeyCast.padding.height * 2)
        }
        let width = sizes.map(\.width).max() ?? 0
        let height = sizes.map(\.height).reduce(0, +) + KeyCast.gap * CGFloat(max(0, lines.count - 1))
        let visible = screen.visibleFrame
        var origin = NSPoint(x: visible.minX + KeyCast.margin, y: visible.minY + KeyCast.margin)
        // A status bar parked in this corner stays readable: the lines start above it
        if let bar = barFrame, bar.intersects(NSRect(x: origin.x, y: origin.y, width: width, height: height)) {
            origin.y = bar.maxY + KeyCast.gap
        }
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: true)
        var y: CGFloat = 0
        for (line, size) in zip(lines, sizes).reversed() {
            let frame = NSRect(x: 0, y: y, width: size.width, height: size.height)
            if animated, !DisplayOptions.reduceMotion, line.bezel.frame.width > 0 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    line.bezel.animator().frame = frame
                }
            } else {
                line.bezel.frame = frame
            }
            line.label.frame = NSRect(x: KeyCast.padding.width, y: KeyCast.padding.height,
                                      width: size.width - KeyCast.padding.width * 2, height: size.height - KeyCast.padding.height * 2)
            y += size.height + KeyCast.gap
        }
    }

    /// Fade the lines whose time is up; the panel goes with the last one.
    private func expire() {
        guard !lines.isEmpty else { return }
        let now = Date()
        for line in lines where !line.fading && now >= line.expires {
            line.fading = true
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = fadeSeconds
                line.bezel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self else { return }
                line.bezel.removeFromSuperview()
                self.lines.removeAll { $0 === line }
                if self.lines.isEmpty { self.panel.orderOut(nil) } else { self.layout(animated: false) }
            })
        }
    }

    /// Take every line off the screen at once: the user hid the HUD, or switched the display off.
    func hide() {
        for line in lines { line.bezel.removeFromSuperview() }
        lines = []
        panel.orderOut(nil)
    }

    // MARK: from a combination to its glyphs

    private static let modifierGlyphs: [(names: [String], glyph: String)] = [
        (["fn", "function", "globe"], "fn"),
        (["ctrl", "control"], "⌃"),
        (["alt", "option", "opt"], "⌥"),
        (["shift"], "⇧"),
        (["cmd", "command", "meta", "super", "win"], "⌘"),
    ]

    private static let keyGlyphs: [String: String] = [
        "tab": "⇥", "return": "↩", "enter": "↩", "escape": "⎋", "esc": "⎋",
        "backspace": "⌫", "delete": "⌫", "forwarddelete": "⌦", "del": "⌦", "space": "Space",
        "up": "↑", "down": "↓", "left": "←", "right": "→",
        "arrowup": "↑", "arrowdown": "↓", "arrowleft": "←", "arrowright": "→",
        "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟", "capslock": "⇪",
        "comma": ",", "period": ".", "slash": "/", "semicolon": ";", "quote": "'",
        "leftbracket": "[", "rightbracket": "]", "backslash": "\\", "minus": "-", "equal": "=",
        "grave": "`", "plus": "+",
    ]

    /// The glyphs of a combination: the modifiers in the order macOS writes them (⌃⌥⇧⌘), then the key.
    ///
    /// @param combo - A combination as agent-desktop takes it: names joined by "+", in any order and case.
    /// @returns The line to draw; empty for an empty combination.
    ///
    /// @example
    /// ```swift
    /// KeyCast.glyphs(for: "cmd+shift+p") // "⇧⌘P"
    /// KeyCast.glyphs(for: "shift+down")  // "⇧↓"
    /// KeyCast.glyphs(for: "cmd++")       // "⌘+"
    /// ```
    static func glyphs(for combo: String) -> String {
        var parts = combo.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "+")
        // "cmd++" and "+": the key is the plus sign itself
        if parts.count >= 2, parts.last == "" {
            parts.removeLast()
            if parts.last == "" { parts.removeLast() }
            parts.append("+")
        }
        parts = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var held = Set<Int>()
        var keys: [String] = []
        for part in parts {
            let name = part.lowercased().replacingOccurrences(of: "_", with: "")
            if let index = modifierGlyphs.firstIndex(where: { $0.names.contains(name) }) {
                held.insert(index)
            } else if let glyph = keyGlyphs[name] {
                keys.append(glyph)
            } else if name.count > 1, name.hasPrefix("f"), Int(name.dropFirst()) != nil {
                keys.append(name.uppercased())
            } else if part.count == 1 {
                keys.append(part.uppercased())
            } else {
                keys.append(part.prefix(1).uppercased() + part.dropFirst())
            }
        }
        return held.sorted().map { modifierGlyphs[$0].glyph }.joined() + keys.joined()
    }
}
