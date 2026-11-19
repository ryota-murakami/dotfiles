// Shared controls of the HUD: bar buttons, the rows the settings card is built from, and the stop shortcut.
import AppKit
import Carbon.HIToolbox

/// Borderless SF Symbol button used on the bar and in the mirror header.
///
/// Why it exists: the old controls were emoji-titled push buttons of mixed sizes; this gives every
/// icon the same hit area, hover feedback and an accessibility label.
final class IconButton: NSButton {
    /// Tinted "on" look, e.g. the mirror button while the mirror is shown.
    var isActive = false { didSet { if oldValue != isActive { updateLook() } } }
    /// Set by the tracking area, or by the bar's pointer polling: the bar ignores mouse events until
    /// the pointer rests on a control, so a tracking area alone would miss the first hover.
    var isHovered = false { didSet { if oldValue != isHovered { updateLook() } } }
    /// Background while `isActive`: the accent colour for a lasting state, something quieter for "open".
    var activeColor = accent.withAlphaComponent(0.9) { didSet { updateLook() } }
    private var trackingArea: NSTrackingArea?

    /// One click must act even when the window is not the key window (the HUD rarely is).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// - Parameters:
    ///   - symbol: SF Symbol name.
    ///   - label: Tooltip and accessibility label (the button shows no text).
    init(symbol: String, label: String, pointSize: CGFloat = 15, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold))
        contentTintColor = .white
        toolTip = label
        setAccessibilityLabel(label)
        wantsLayer = true
        layer?.cornerRadius = 8
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        updateLook()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    private func updateLook() {
        let color: NSColor = isActive ? activeColor
            : NSColor.white.withAlphaComponent(isHovered ? 0.22 : 0.10)
        layer?.backgroundColor = color.cgColor
    }
}

/// The one-click stop control at the trailing end of the bar.
///
/// Why it exists: stopping the agent must not need a menu. It is red, labelled and set apart from the
/// other buttons so it is easy to hit and hard to hit by accident. Built and owned by {@link HUD}.
final class StopButton: NSButton {
    var isHovered = false { didSet { if oldValue != isHovered { updateLook() } } }
    private var stopped = false

    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageLeading
        imageHugsTitle = true
        wantsLayer = true
        layer?.cornerRadius = 10
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        setStopped(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Switch between "stop" (red) and "clear the stop" (outlined) looks.
    func setStopped(_ value: Bool) {
        stopped = value
        let text = value ? "解除" : "停止"
        let symbol = value ? "arrow.uturn.backward" : "stop.fill"
        let label = value ? "停止を解除" : "エージェントを停止"
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .bold))
        contentTintColor = .white
        attributedTitle = NSAttributedString(string: " " + text, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: NSColor.white,
        ])
        toolTip = value ? "停止を解除します（メッセージを送っても解除されます）" : "エージェントの処理を今すぐ止めます（⌃⌥⌘. でも止められます）"
        // The visible title is just "停止": give assistive tools the full meaning
        setAccessibilityTitle(label)
        setAccessibilityLabel(label)
        updateLook()
    }

    private func updateLook() {
        if stopped {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(isHovered ? 0.30 : 0.16).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
            layer?.borderWidth = 1
        } else {
            layer?.backgroundColor = (isHovered ? NSColor(calibratedRed: 1.0, green: 0.30, blue: 0.27, alpha: 1)
                                                : NSColor(calibratedRed: 0.90, green: 0.20, blue: 0.18, alpha: 1)).cgColor
            layer?.borderWidth = 0
        }
    }
}

/// On/off switch that shows its state in colour even when its window is not the key window.
///
/// Why it exists: the HUD's panels never become key, and AppKit draws NSSwitch grey there, so on and
/// off look alike. Used by {@link SettingRow} for every toggle setting.
final class HUDSwitch: NSControl {
    var isOn = false { didSet { if oldValue != isOn { needsDisplay = true } } }

    override var intrinsicContentSize: NSSize { NSSize(width: 36, height: 20) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        (isOn ? accent : NSColor.white.withAlphaComponent(0.24)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let knob = bounds.height - 4
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: isOn ? bounds.maxX - knob - 2 : 2, y: 2, width: knob, height: knob)).fill()
    }

    // Swallow the press so a click on the switch never starts dragging the window
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        flip()
    }

    private func flip() {
        isOn.toggle()
        sendAction(action, to: target)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    override func accessibilityValue() -> Any? { isOn ? 1 : 0 }
    override func accessibilityPerformPress() -> Bool { flip(); return true }
}

/// Text of a percentage value, e.g. "95%".
func percentText(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

/// Small secondary heading used above a group of rows.
func sectionHeading(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    label.textColor = NSColor.white.withAlphaComponent(0.55)
    return label
}

/// A labelled control bound to one setting: switch, slider or button, chosen by the setting's kind.
///
/// Why it exists: every setting is shown the same way, whatever its kind; the settings card only
/// places the list. Created by {@link SettingsList}.
final class SettingRow: NSView {
    let setting: Setting
    private let store: SettingsStore
    private var toggle: HUDSwitch?
    private var slider: NSSlider?
    private var valueLabel: NSTextField?

    /// - Parameters:
    ///   - compact: Stack a slider under its title, for narrow columns.
    ///   - useShortTitle: Use the setting's short label (for places without section headings).
    init(_ setting: Setting, store: SettingsStore, compact: Bool, useShortTitle: Bool = false) {
        self.setting = setting
        self.store = store
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: setting.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        icon.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let title = NSTextField(labelWithString: useShortTitle ? (setting.short ?? setting.title) : setting.title)
        title.font = NSFont.systemFont(ofSize: 13)
        title.textColor = .white
        title.lineBreakMode = .byTruncatingTail
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let line = NSStackView(views: [icon, title])
        line.orientation = .horizontal
        // .fill lets the title take the spare width, so controls line up at the trailing edge
        line.distribution = .fill
        line.spacing = 6
        line.alignment = .centerY
        var body: NSView = line

        switch setting.kind {
        case .toggle:
            let control = HUDSwitch()
            control.target = self
            control.action = #selector(switchChanged(_:))
            control.setAccessibilityLabel(setting.title)
            control.setContentHuggingPriority(.required, for: .horizontal)
            line.addArrangedSubview(control)
            toggle = control
        case let .slider(min, max, _):
            let control = NSSlider(value: store.value(setting.id), minValue: min, maxValue: max, target: self, action: #selector(sliderChanged(_:)))
            control.controlSize = .small
            control.isContinuous = true
            control.setAccessibilityLabel(setting.title)
            let value = NSTextField(labelWithString: "")
            value.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            value.textColor = NSColor.white.withAlphaComponent(0.75)
            value.alignment = .right
            value.widthAnchor.constraint(equalToConstant: 40).isActive = true
            slider = control
            valueLabel = value
            if compact {
                // Narrow column: the value sits on the title line and the slider gets the full width
                line.addArrangedSubview(value)
                let column = NSStackView(views: [line, control])
                column.orientation = .vertical
                column.alignment = .leading
                column.spacing = 3
                line.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
                control.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
                body = column
            } else {
                control.widthAnchor.constraint(equalToConstant: 128).isActive = true
                line.addArrangedSubview(control)
                line.addArrangedSubview(value)
            }
        case let .action(button, destructive):
            let control = NSButton(title: button, target: self, action: #selector(actionPressed(_:)))
            control.bezelStyle = .rounded
            control.controlSize = .small
            control.hasDestructiveAction = destructive
            // Several rows share the verb ("リセット"): name each button by what it acts on
            control.setAccessibilityTitle("\(setting.title)を\(button)")
            control.setAccessibilityLabel("\(setting.title)を\(button)")
            control.setContentHuggingPriority(.required, for: .horizontal)
            line.addArrangedSubview(control)
        }

        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: leadingAnchor),
            body.trailingAnchor.constraint(equalTo: trailingAnchor),
            body.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        sync()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Show the stored value; called after any setting changed (from here or elsewhere).
    func sync() {
        toggle?.isOn = store.isOn(setting.id)
        if let slider, abs(slider.doubleValue - store.value(setting.id)) > 0.0001 { slider.doubleValue = store.value(setting.id) }
        valueLabel?.stringValue = percentText(store.value(setting.id))
    }

    @objc private func switchChanged(_ sender: HUDSwitch) { store.set(setting.id, sender.isOn ? 1 : 0) }
    @objc private func sliderChanged(_ sender: NSSlider) { store.set(setting.id, sender.doubleValue) }
    @objc private func actionPressed(_ sender: NSButton) { store.perform(setting.id) }
}

/// Vertical list of settings under section headings, generated from the registry.
///
/// Why it exists: the settings UI is this list in a container; a different container (a panel with
/// panes, say) can reuse it. It keeps its rows in step with the store on its own.
final class SettingsList: NSStackView {
    private var rows: [SettingRow] = []
    private var observer: NSObjectProtocol?

    /// - Parameters:
    ///   - sections: Sections to show, in order (default: all).
    ///   - compact: Narrow-column layout for sliders.
    ///   - showHeadings: False when the caller already shows the section title (a pane).
    ///   - include: Filter for settings that make no sense in a given place.
    init(store: SettingsStore, sections: [SettingSection] = SettingsStore.sections, compact: Bool = false,
         showHeadings: Bool = true, include: (Setting) -> Bool = { _ in true }) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 2
        translatesAutoresizingMaskIntoConstraints = false
        // The HUD is dark whatever the system theme is, so its native controls must be too
        appearance = NSAppearance(named: .darkAqua)
        for section in sections {
            let items = SettingsStore.registry.filter { $0.section == section.id && include($0) }
            guard !items.isEmpty else { continue }
            if showHeadings {
                let heading = sectionHeading(section.title)
                if let last = arrangedSubviews.last { setCustomSpacing(12, after: last) }
                addArrangedSubview(heading)
                setCustomSpacing(4, after: heading)
            }
            for item in items {
                let row = SettingRow(item, store: store, compact: compact)
                rows.append(row)
                addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
            }
        }
        observer = NotificationCenter.default.addObserver(forName: SettingsStore.changed, object: store, queue: .main) { [weak self] _ in
            self?.rows.forEach { $0.sync() }
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

/// Close a floating surface when the user clicks anywhere outside it.
///
/// Why it exists: the HUD never becomes the active app, so AppKit's own "transient" dismissal does not
/// see clicks in other apps. A global monitor (mouse events need no extra permission) does.
final class OutsideClickWatcher {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// - Parameters:
    ///   - isInside: True for screen points that belong to the surface or its button.
    ///   - onOutside: Called on the main thread for a click elsewhere.
    func start(isInside: @escaping (NSPoint) -> Bool, onOutside: @escaping () -> Void) {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            if !isInside(NSEvent.mouseLocation) { onOutside() }
        }
        // Clicks on the HUD's own other windows (the mirror, the bar) arrive locally instead
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            if !isInside(NSEvent.mouseLocation) { onOutside() }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}

/// A view whose content starts at the top, for use as a scroll view's document.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Wrap a settings list (or any tall view) so it scrolls when its container is shorter than it.
///
/// - Parameter inset: Padding around the content inside the scroll view.
/// - Returns: A transparent scroll view; pin it wherever the list should appear.
func makeScrollable(_ content: NSView, inset: CGFloat) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    scroll.translatesAutoresizingMaskIntoConstraints = false
    let document = FlippedView()
    document.translatesAutoresizingMaskIntoConstraints = false
    document.addSubview(content)
    scroll.documentView = document
    NSLayoutConstraint.activate([
        document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
        document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: inset),
        content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -inset),
        content.topAnchor.constraint(equalTo: document.topAnchor, constant: inset),
        content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -inset),
    ])
    return scroll
}

/// Collection behaviour shared by every floating HUD window: on all desktops, over full-screen apps.
let hudCollectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

/// Global keyboard shortcut that stops the agent: Control-Option-Command-Period.
///
/// Why it exists: while the agent moves the pointer, aiming at a button is hard; a key works wherever
/// the pointer is. Carbon hot keys reach an app that is not frontmost and need no Accessibility
/// permission. Owned by {@link HUD}, switched by the "stop.hotkey" setting.
final class StopHotKey {
    /// Called on the main thread when the shortcut is pressed.
    static var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func setEnabled(_ enabled: Bool) {
        if enabled { register() } else { unregister() }
    }

    private func register() {
        guard hotKey == nil else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            // A C callback cannot capture context, hence the static closure
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                StopHotKey.onPress?()
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x4457_5354), id: 1)   // 'DWST'
        RegisterEventHotKey(UInt32(kVK_ANSI_Period), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}
