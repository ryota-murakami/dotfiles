// The settings card: the bar's settings button opens a floating card of switches and sliders.
import AppKit

/// Settings as a floating card anchored to the settings button, on the side of the bar that has room.
///
/// Why it exists: switches and sliders apply at once and show their state without reopening
/// anything, which a menu cannot do. It scrolls when the list outgrows the screen.
/// Created and owned by {@link HUD}; opened by the bar's settings button.
final class SettingsCard: NSObject {
    static let width: CGFloat = 348
    private weak var hud: HUD?
    /// Keyable for the shortcut recorder alone: with `becomesKeyOnlyIfNeeded` no other control takes the keyboard
    private let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var recordingObserver: NSObjectProtocol?
    private let watcher = OutsideClickWatcher()
    private var list: SettingsList!
    private let root = NSView()
    var isOpen: Bool { panel.isVisible }

    /// Build the card. Called once, after the HUD built its bar.
    func attach(to hud: HUD) {
        self.hud = hud
        panel.level = .statusBar
        panel.collectionBehavior = stageCollectionBehavior
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true

        root.wantsLayer = true
        root.layer?.cornerRadius = surfaceCornerRadius
        applyLook()

        let title = NSTextField(labelWithString: "設定")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        let close = IconButton(symbol: "xmark", label: "設定を閉じる", pointSize: 12, target: self, action: #selector(closePressed))
        list = SettingsList(store: settings)
        let scroll = makeScrollable(list, inset: 0)
        for v in [title, close, scroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
        panel.contentView = root
        recordingObserver = NotificationCenter.default.addObserver(forName: ShortcutRecorder.recordingChanged, object: nil, queue: .main) { [weak self] note in
            if (note.userInfo?["recording"] as? Bool) == false { self?.releaseKeyboard() }
        }
    }

    /// Give the keyboard back to the app in front once a shortcut was recorded: the card took it for
    /// that moment only, and the user's typing must not end in it. A panel stops being key when it is
    /// ordered out; it comes straight back without the keyboard.
    private func releaseKeyboard() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// Close the card, whoever asks (the HUD being hidden).
    func dismiss() { if isOpen { close() } }

    /// Background and outline of the card, and which sliders can be used: opaque while "Reduce
    /// transparency" is on (the see-through sliders then do nothing), a full outline with
    /// "Increase contrast". Called at launch and when a display setting changes.
    func applyLook() {
        let contrast = DisplayOptions.increaseContrast
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: surfaceAlpha(0.97)).cgColor
        root.layer?.borderColor = NSColor.white.withAlphaComponent(contrast ? 0.8 : 0.16).cgColor
        root.layer?.borderWidth = surfaceBorderWidth
        list?.syncRows()
    }

    func toggle() { isOpen ? close() : open() }

    /// Keep the card attached to the bar while it is open (the bar can be dragged), and close it when
    /// the user moves to another desktop: the bar goes along, its card does not. Called on every HUD refresh.
    func follow() {
        guard isOpen else { return }
        if panel.isOnAnotherSpace { close() } else { place() }
    }

    private func open() {
        guard let hud else { return }
        place()
        panel.orderFrontRegardless()
        watcher.start(isInside: { [weak self, weak hud] point in
            guard let self, let hud else { return true }
            return self.panel.frame.contains(point) || hud.screenRect(of: hud.settingsButton).insetBy(dx: -6, dy: -6).contains(point)
        }, onOutside: { [weak self] in self?.close() })
    }

    private func close() {
        panel.orderOut(nil)
        watcher.stop()
        hud?.settingsButton.isActive = false
    }

    @objc private func closePressed() { close() }

    /// Beside the bar at the settings button, right-aligned to it, like a tooltip: above the bar when
    /// there is room, below it otherwise (a bar at the top of the screen), as tall as its content or
    /// that room allows.
    private func place() {
        guard let hud, let screen = hud.panel.screen ?? NSScreen.main else { return }
        let button = hud.screenRect(of: hud.settingsButton)
        let bar = hud.panel.frame
        let wanted = list.fittingSize.height + 12 + 22 + 6 + 14
        // The bar's height over the button's span: the card clears the whole bar and lines up with the button
        let anchor = NSRect(x: button.minX, y: bar.minY, width: button.width, height: bar.height)
        let frame = popupFrame(size: NSSize(width: Self.width, height: wanted), anchor: anchor, visible: screen.visibleFrame,
                               sides: [.above, .below], gap: 10, alignEnd: true, minHeight: 160)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
}
