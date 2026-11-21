// Shared controls of the HUD: bar buttons, the rows the settings card is built from, and the stop shortcut.
import AppKit
import Carbon.HIToolbox

/// Borderless SF Symbol button used on the bar and in the headers of the panels.
///
/// Why it exists: the old controls were emoji-titled push buttons of mixed sizes; this gives every
/// icon the same hit area, hover and press feedback and an accessibility label.
final class IconButton: NSButton {
    /// "On" look, e.g. the mirror button while the mirror is shown.
    var isActive = false { didSet { if oldValue != isActive { updateLook() } } }
    /// Set by the tracking area, or by the bar's pointer polling: the bar ignores mouse events until
    /// the pointer rests on a control, so a tracking area alone would miss the first hover.
    var isHovered = false { didSet { if oldValue != isHovered { updateLook() } } }
    /// Symbol shown while `isActive` (the filled variant) and its colour: the colour of the surface
    /// the button stands for, so the fill behind it can stay quiet.
    var activeSymbol: String? { didSet { updateLook() } }
    var activeTint: NSColor? { didSet { updateLook() } }
    /// Background while `isActive`.
    var activeFill = NSColor.white.withAlphaComponent(0.18) { didSet { updateLook() } }
    private let symbol: String
    private let help: String
    private let pointSize: CGFloat
    /// True while the mouse button is held on it.
    private var isPressed = false { didSet { if oldValue != isPressed { updateLook() } } }
    private var trackingArea: NSTrackingArea?

    /// One click must act even when the window is not the key window (the HUD rarely is).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// - Parameters:
    ///   - symbol: SF Symbol name.
    ///   - label: Tooltip and accessibility label (the button shows no text).
    init(symbol: String, label: String, pointSize: CGFloat = 15, target: AnyObject?, action: Selector) {
        self.symbol = symbol
        self.help = label
        self.pointSize = pointSize
        super.init(frame: .zero)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
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

    override var isEnabled: Bool { didSet { updateLook() } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    /// The press shows for as long as the button is held: a custom button owes the user that.
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }

    // The contrast setting changes the app's appearance: outlines and fills follow
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLook()
    }

    private func updateLook() {
        let contrast = DisplayOptions.increaseContrast
        let white = NSColor.white
        let fill: NSColor = isPressed ? white.withAlphaComponent(0.30)
            : isActive ? activeFill
            : white.withAlphaComponent(isHovered ? 0.14 : (contrast ? 0.20 : 0.06))
        layer?.backgroundColor = fill.hudCG
        // "Increase contrast": the button's outline shows, not only its faint fill
        layer?.borderWidth = contrast ? 1 : 0
        layer?.borderColor = white.withAlphaComponent(0.6).cgColor
        image = NSImage(systemSymbolName: isActive ? (activeSymbol ?? symbol) : symbol, accessibilityDescription: help)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold))
        contentTintColor = !isEnabled ? .tertiaryLabelColor : (isActive ? (activeTint ?? .labelColor) : .labelColor)
    }
}

/// A capsule push button drawn by its layer: the main answer of a question (filled with the
/// system's colour for the primary control) or one of the other buttons (a quiet plate).
///
/// Why it exists: a system push button's bezel turns grey in a panel that is never the key window,
/// and it is not as tall as a button drawn by hand. Every button of the prompt card is this one
/// control instead: the same size, told apart by style, with the hover and press states a custom
/// button owes the user. Created by {@link HUD} for the two answers and the feedback buttons.
final class CapsuleButton: NSButton {
    enum Style {
        /// The main answer.
        case primary
        /// The other answer, and buttons that do not answer.
        case secondary
    }

    /// Height of every capsule button: the system's size for a control on the Mac.
    static let height: CGFloat = 28

    private let style: Style
    private var isHovered = false { didSet { if oldValue != isHovered { updateLook() } } }
    private var isPressed = false { didSet { if oldValue != isPressed { updateLook() } } }
    private var trackingArea: NSTrackingArea?

    /// A light that swells and fades around the button: the next move is here. Set by the prompt card
    /// while the page in front is read to its end ({@link HUD.updateAskBreathing}).
    var isBreathing = false {
        didSet {
            guard oldValue != isBreathing else { return }
            layer?.removeAnimation(forKey: "breathe")
            guard isBreathing else {
                shadow = nil
                return
            }
            // Through the view's own shadow: AppKit owns the layer of a view and drops a shadow set on the layer itself
            let glow = NSShadow()
            glow.shadowColor = primaryFill
            glow.shadowBlurRadius = 10
            glow.shadowOffset = .zero
            shadow = glow
            // "Reduce motion": the light stays, steady
            guard !DisplayOptions.reduceMotion, let layer else { return }
            let pulse = CABasicAnimation(keyPath: "shadowOpacity")
            pulse.fromValue = 0.2
            pulse.toValue = 1
            pulse.duration = 0.75
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(pulse, forKey: "breathe")
        }
    }

    /// The words on the button. Set this, not `title`: it carries the style's font and colour.
    var label: String {
        get { title }
        set {
            attributedTitle = NSAttributedString(string: newValue, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: style == .primary ? .semibold : .medium),
                .foregroundColor: style == .primary ? NSColor.white : NSColor.labelColor,
            ])
            invalidateIntrinsicContentSize()
        }
    }

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        updateLook()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isEnabled: Bool { didSet { updateLook() } }

    /// As wide as its words plus the capsule's rounded ends.
    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(attributedTitle.size().width) + 28, height: Self.height)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    /// The press shows for as long as the button is held.
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLook()
    }

    private func updateLook() {
        let contrast = DisplayOptions.increaseContrast
        switch style {
        case .primary:
            let fill = isPressed ? primaryFill.withSystemEffect(.pressed) : (isHovered ? primaryFill.withSystemEffect(.rollover) : primaryFill)
            layer?.backgroundColor = fill.hudCG
            layer?.borderWidth = 0
        case .secondary:
            layer?.backgroundColor = NSColor.white.withAlphaComponent(isPressed ? 0.30 : (isHovered ? 0.22 : 0.14)).cgColor
            layer?.borderWidth = contrast ? 1 : 0
            layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        }
        // A card parked at the screen edge cannot be answered, and a feedback button rests after a press
        alphaValue = isEnabled ? 1 : 0.45
    }
}

/// The one-click stop control at the trailing end of the bar.
///
/// Why it exists: stopping the agent must not need a menu. It is red, labelled and set apart from the
/// other buttons so it is easy to hit and hard to hit by accident. Built and owned by {@link HUD}.
final class StopButton: NSButton {
    var isHovered = false { didSet { if oldValue != isHovered { updateLook() } } }
    /// True while the mouse button is held on it.
    private var isPressed = false { didSet { if oldValue != isPressed { updateLook() } } }
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

    /// The press shows for as long as the button is held.
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLook()
    }

    private func updateLook() {
        if stopped {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(isPressed ? 0.38 : (isHovered ? 0.30 : 0.16)).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
            layer?.borderWidth = 1
        } else {
            // The system's red for a destructive control, with its own hover and press variants
            let red = NSColor.systemRed
            layer?.backgroundColor = (isPressed ? red.withSystemEffect(.pressed) : (isHovered ? red.withSystemEffect(.rollover) : red)).hudCG
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
        (isOn ? primaryFill : NSColor.white.withAlphaComponent(0.24)).setFill()
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
    label.textColor = .secondaryLabelColor
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
        icon.contentTintColor = .secondaryLabelColor
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let title = NSTextField(labelWithString: useShortTitle ? (setting.short ?? setting.title) : setting.title)
        title.font = NSFont.systemFont(ofSize: 13)
        title.textColor = .labelColor
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
            value.textColor = .secondaryLabelColor
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
        // "Reduce transparency" makes every surface opaque: the see-through sliders then do nothing
        slider?.isEnabled = !(DisplayOptions.reduceTransparency && setting.id.hasSuffix(".opacity"))
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

    /// Show every row's stored value and whether it can be changed right now.
    func syncRows() { rows.forEach { $0.sync() } }

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

/// Let this process set the pointer's shape while another app is active.
///
/// Why it exists: the window server takes `NSCursor.set()` only from the active app, and the HUD is
/// active only while the user types in the mirror. The handles asked for their cursor and the arrow
/// stayed. The connection property `SetsCursorInBackground` lifts that for this process. It is a
/// private window-server call, so it is looked up at run time: on a system without it the HUD runs
/// as before and only the cursor shapes are missing. Called once at launch.
func allowCursorInBackground() {
    typealias MainConnection = @convention(c) () -> Int32
    typealias SetConnectionProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    guard let image = dlopen(nil, RTLD_LAZY),
          let mainConnection = dlsym(image, "CGSMainConnectionID"),
          let setProperty = dlsym(image, "CGSSetConnectionProperty") else { return }
    let connection = unsafeBitCast(mainConnection, to: MainConnection.self)()
    _ = unsafeBitCast(setProperty, to: SetConnectionProperty.self)(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
}

/// View that changes the pointer's shape while the pointer is over it.
///
/// Why it exists: cursor rects (`resetCursorRects`) only work in the key window of the active app,
/// and the HUD's panels are never that, because they must not take focus from the app being
/// demonstrated. So an edge could be dragged, but nothing showed it. A tracking area that is always
/// active sets the cursor directly instead, which the window server accepts from the HUD after
/// {@link allowCursorInBackground}. Subclassed by every resize handle and drag handle of the HUD.
class HoverCursorView: NSView {
    /// The shape to show over this view. Subclasses override it.
    var hoverCursor: NSCursor { .arrow }
    private var cursorArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorArea { removeTrackingArea(cursorArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        cursorArea = area
    }

    override func mouseEntered(with event: NSEvent) { hoverCursor.set() }
    override func mouseMoved(with event: NSEvent) { hoverCursor.set() }
    override func mouseExited(with event: NSEvent) {
        // During a drag the pointer may run ahead of the edge: the shape stays until the button is released
        if NSEvent.pressedMouseButtons & 1 == 0 { NSCursor.arrow.set() }
    }
    override func mouseUp(with event: NSEvent) {
        // Released away from the handle (the frame hit its limit): back to the arrow
        if !bounds.contains(convert(event.locationInWindow, from: nil)) { NSCursor.arrow.set() }
    }
}

/// The resize cursor a window shows on one of its edges or corners (the system's own shapes).
///
/// @param edges - The sides the handle moves; two adjacent sides make a corner.
/// @returns The frame-resize cursor for that edge or corner.
func frameResizeCursor(for edges: EdgeResizeHandle.Edges) -> NSCursor {
    var position: NSCursor.FrameResizePosition = .right
    switch (edges.contains(.left), edges.contains(.right), edges.contains(.top), edges.contains(.bottom)) {
    case (true, _, true, _): position = .topLeft
    case (true, _, _, true): position = .bottomLeft
    case (_, true, true, _): position = .topRight
    case (_, true, _, true): position = .bottomRight
    case (true, _, _, _): position = .left
    case (_, true, _, _): position = .right
    case (_, _, true, _): position = .top
    default: position = .bottom
    }
    return NSCursor.frameResize(position: position, directions: .all)
}

/// A side of an anchor rectangle on which a popup can sit.
enum PopupSide { case above, below, right, left }

/// Frame for a popup beside `anchor`, placed the way a tooltip is: on the first of `sides` where it
/// fits whole on the screen; when it fits on none, above or below (whichever has more room), shrunk
/// to that room; and never off the screen.
///
/// Why it exists: the settings card always opened above the bar, so with the bar at the top of the
/// screen it opened outside it. Used by the settings card and the note popup.
///
/// @param size - The size the popup wants.
/// @param anchor - What it belongs to, in screen coordinates (bottom-left origin).
/// @param visible - The screen area it must stay inside (`NSScreen.visibleFrame`).
/// @param sides - Sides to try, in order of preference.
/// @param gap - Distance between anchor and popup.
/// @param alignEnd - false: the popup's left edge (above/below) or top edge (right/left) lines up with the anchor's; true: the right or bottom edges do.
/// @param minHeight - The least height it is shrunk to when no side has room for all of it.
/// @returns The popup's frame.
///
/// @example
/// popupFrame(size: card, anchor: bar.frame, visible: screen.visibleFrame, sides: [.above, .below])
func popupFrame(size: NSSize, anchor: NSRect, visible: NSRect, sides: [PopupSide], gap: CGFloat = 10,
                alignEnd: Bool = false, minHeight: CGFloat = 120) -> NSRect {
    let area = visible.insetBy(dx: 8, dy: 8)
    func room(_ side: PopupSide) -> CGFloat {
        switch side {
        case .above: return area.maxY - anchor.maxY - gap
        case .below: return anchor.minY - area.minY - gap
        case .right: return area.maxX - anchor.maxX - gap
        case .left: return anchor.minX - area.minX - gap
        }
    }
    func frame(_ side: PopupSide, _ s: NSSize) -> NSRect {
        var r = NSRect(origin: .zero, size: s)
        switch side {
        case .above, .below:
            r.origin.x = alignEnd ? anchor.maxX - s.width : anchor.minX
            r.origin.y = side == .above ? anchor.maxY + gap : anchor.minY - gap - s.height
        case .right, .left:
            r.origin.x = side == .right ? anchor.maxX + gap : anchor.minX - gap - s.width
            r.origin.y = alignEnd ? anchor.minY : anchor.maxY - s.height
        }
        // Slide along the anchor until all of it is on screen
        r.origin.x = min(max(r.origin.x, area.minX), max(area.minX, area.maxX - s.width))
        r.origin.y = min(max(r.origin.y, area.minY), max(area.minY, area.maxY - s.height))
        return r
    }
    for side in sides {
        let vertical = side == .above || side == .below
        let fits = vertical ? room(side) >= size.height && size.width <= area.width
                            : room(side) >= size.width && size.height <= area.height
        if fits { return frame(side, size) }
    }
    // It fits nowhere whole: the roomier of above and below, as tall as that room allows
    let side: PopupSide = room(.above) >= room(.below) ? .above : .below
    return frame(side, NSSize(width: min(size.width, area.width), height: min(size.height, max(minHeight, room(side)))))
}

/// What the session is doing, as the bar shows it at its trailing end.
enum Activity: String {
    /// The walkthrough itself is acting (narrating, clicking, typing, selecting): the stop button shows.
    case performing
    /// The user pressed stop.
    case stopped
    /// The turn has ended, or the agent waits for the user or for something it started.
    case waiting
    /// The agent is changing this skill (the HUD, `dw`, the hooks, the documents).
    case skill
    /// The agent is working on something else (reading, checking, preparing).
    case other
}

/// A label, not a button: the state of the session, shown where the stop button sits while there is
/// nothing on screen to stop.
///
/// Why it exists: a red stop button that is always there says "something is being done on your
/// screen" even while the agent waits for an answer or edits its own skill. The button shows only
/// while the walkthrough acts; the rest of the time this badge names the state. Owned by {@link HUD},
/// switched by {@link HUD.applyActivity}.
final class StateBadge: NSView {
    private let icon = NSImageView()
    private let text = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        translatesAutoresizingMaskIntoConstraints = false
        text.font = .systemFont(ofSize: 13, weight: .semibold)
        text.textColor = .labelColor
        text.lineBreakMode = .byClipping
        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        show(.waiting)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Width the bar gives the badge: the longest label fits.
    static let width: CGFloat = 132

    private var shown: Activity = .waiting

    /// Name a state. `.performing` and `.stopped` belong to the stop button; the badge is hidden then.
    ///
    /// The plate has no colour of its own: on the bar, colour is kept for the stop button and the
    /// screen border ("the agent is operating the Mac"), and the surfaces' own colours mean those
    /// surfaces. The symbol and the words tell the states apart.
    func show(_ activity: Activity) {
        shown = activity
        let look: (label: String, symbol: String, tint: NSColor)
        switch activity {
        case .skill: look = ("スキル更新中", "hammer.fill", .systemPurple)
        case .other: look = ("その他作業中", "gearshape.fill", .secondaryLabelColor)
        default: look = ("待機中", "pause.circle.fill", .secondaryLabelColor)
        }
        icon.image = NSImage(systemSymbolName: look.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        icon.contentTintColor = look.tint
        text.stringValue = look.label
        let contrast = DisplayOptions.increaseContrast
        layer?.backgroundColor = NSColor.white.withAlphaComponent(contrast ? 0.20 : 0.10).cgColor
        layer?.borderWidth = contrast ? 1 : 0
        layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        toolTip = "セッションの状態：\(look.label)（⌃⌥⌘. でいつでも止められます）"
        setAccessibilityLabel("状態：\(look.label)")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        show(shown)
    }
}

/// Collection behaviour of the status bar and the screen border: on every desktop (Space), over
/// full-screen apps. They say whose turn the Mac is, which the user needs wherever they are.
let hudCollectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

/// Collection behaviour of every other surface (explainer, note, prompt, mirror, settings card): on
/// the one desktop where it was shown. While the agent works on something else the user moves to
/// another desktop to read mail, and the walkthrough's pages must not follow them there.
/// `.transient` is spelled out for the explainer, the one surface at the ordinary window level: a
/// managed window ordered out and in again returns to the desktop it was on, a transient one comes
/// to the active desktop, which {@link NSWindow.orderFrontOnActiveSpace} relies on.
let stageCollectionBehavior: NSWindow.CollectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]

extension NSWindow {
    /// True while the window is open on a desktop other than the one the user is looking at.
    var isOnAnotherSpace: Bool { isVisible && !isOnActiveSpace }

    /// Put the window in front on the desktop the user is looking at, without taking focus.
    ///
    /// Why it exists: a window with {@link stageCollectionBehavior} stays on the desktop where it was
    /// ordered in, and ordering it front again leaves it there. Called when `dw` shows something new
    /// and when the user presses the surface's own button on the bar: both mean "here, now".
    func orderFrontOnActiveSpace() {
        // Taken off its old desktop first: an ordered-out window comes back on the active one
        if isOnAnotherSpace { orderOut(nil) }
        orderFrontRegardless()
    }

    /// Make the window invisible and click-through, or bring it back, without closing it.
    ///
    /// Why it exists: a surface steps aside for a moment (`dw click-xy` clicks under it, the real chat
    /// window is in front of the mirror). Ordering it out and in again would move it to whichever
    /// desktop is active when it returns; a concealed window keeps its desktop. Called on every
    /// refresh tick by the surfaces that step aside.
    func setConcealed(_ concealed: Bool) {
        guard (alphaValue == 0) != concealed else { return }
        alphaValue = concealed ? 0 : 1
        ignoresMouseEvents = concealed
    }
}

/// What each registered hot key does, by its id: one Carbon handler serves them all.
private var hotKeyActions: [UInt32: () -> Void] = [:]
private var hotKeyHandler: EventHandlerRef?

/// A keyboard shortcut that reaches the HUD while another app is frontmost.
///
/// Why it exists: the HUD is never the active app, so its windows get no key events. Carbon hot keys
/// reach an app that is not frontmost and need no Accessibility permission. A registered hot key is
/// taken from every other app, so it is registered only while it means something here. Owned by
/// {@link HUD}: the stop shortcut (the "stop.hotkey" setting) and Command-C over a reading surface
/// ({@link HUD.updateCopyHotKey}).
final class HotKey {
    /// Called on the main thread when the shortcut is pressed.
    var onPress: (() -> Void)?
    private let id: UInt32
    private let keyCode: Int
    private let modifiers: Int
    private var ref: EventHotKeyRef?

    /// - Parameters:
    ///   - id: Tells the hot keys apart in the shared handler: unique per instance.
    ///   - keyCode: Virtual key code (`kVK_…`).
    ///   - modifiers: Carbon modifier flags (`cmdKey | optionKey …`).
    init(id: UInt32, keyCode: Int, modifiers: Int) {
        self.id = id
        self.keyCode = keyCode
        self.modifiers = modifiers
        hotKeyActions[id] = { [weak self] in self?.onPress?() }
    }

    /// True while the shortcut is registered, that is, taken from the other apps.
    var isEnabled: Bool { ref != nil }

    func setEnabled(_ enabled: Bool) {
        if enabled { register() } else { unregister() }
    }

    private func register() {
        guard ref == nil else { return }
        if hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            // A C callback cannot capture context, hence the table of actions outside the class
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var pressed = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                               nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                guard status == noErr, let action = hotKeyActions[pressed.id] else { return OSStatus(eventNotHandledErr) }
                action()
                return noErr
            }, 1, &spec, nil, &hotKeyHandler)
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4457_5354), id: id)   // 'DWST'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
