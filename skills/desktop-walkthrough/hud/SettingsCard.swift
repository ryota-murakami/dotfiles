// The settings card: the bar's settings button opens a floating card of switches and sliders.
import AppKit

/// Settings as a floating card anchored above the settings button.
///
/// Why it exists: switches and sliders apply at once and show their state without reopening
/// anything, which a menu cannot do. It scrolls when the list outgrows the screen.
/// Created and owned by {@link HUD}; opened by the bar's settings button.
final class SettingsCard: NSObject {
    static let width: CGFloat = 348
    private weak var hud: HUD?
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let watcher = OutsideClickWatcher()
    private var list: SettingsList!
    var isOpen: Bool { panel.isVisible }

    /// Build the card. Called once, after the HUD built its bar.
    func attach(to hud: HUD) {
        self.hud = hud
        panel.level = .statusBar
        panel.collectionBehavior = hudCollectionBehavior
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true

        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 14
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 0.97).cgColor
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        root.layer?.borderWidth = 1

        let title = NSTextField(labelWithString: "設定")
        title.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        title.textColor = .white
        let close = IconButton(symbol: "xmark", label: "設定を閉じる", pointSize: 10, target: self, action: #selector(closePressed))
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
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            close.widthAnchor.constraint(equalToConstant: 22),
            close.heightAnchor.constraint(equalToConstant: 22),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
        panel.contentView = root
    }

    func toggle() { isOpen ? close() : open() }

    /// Keep the card attached to the bar while it is open (the bar can be dragged). Called on every HUD refresh.
    func follow() {
        if isOpen { place() }
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

    /// Above the settings button, right-aligned to it, as tall as its content or the space allows.
    private func place() {
        guard let hud, let screen = hud.panel.screen ?? NSScreen.main else { return }
        let button = hud.screenRect(of: hud.settingsButton)
        let bar = hud.panel.frame
        let wanted = list.fittingSize.height + 12 + 22 + 6 + 14
        let room = screen.visibleFrame.maxY - bar.maxY - 20
        let height = min(wanted, max(160, room))
        var x = button.maxX - Self.width
        x = max(screen.visibleFrame.minX + 8, min(x, screen.visibleFrame.maxX - Self.width - 8))
        let frame = NSRect(x: x, y: bar.maxY + 10, width: Self.width, height: height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
}
