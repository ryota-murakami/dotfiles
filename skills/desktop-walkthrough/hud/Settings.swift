// Settings model of the HUD: one registry of options that the settings UI is generated from.
import AppKit

/// One user-adjustable option of the HUD.
///
/// Why it exists: the settings UI is generated from these
/// descriptions, so a new option is one entry in {@link SettingsStore.registry} instead of UI code.
/// Read by the settings card and by the shared row views in Controls.swift.
struct Setting {
    enum Kind {
        /// On/off, stored as 1 or 0.
        case toggle
        /// A continuous value shown as a percentage, snapped to `step`.
        case slider(min: Double, max: Double, step: Double)
        /// A one-shot command; `button` is the verb on its control.
        case action(button: String, destructive: Bool)
    }
    let id: String
    /// Id of the {@link SettingSection} it is listed under.
    let section: String
    let title: String
    /// SF Symbol name used wherever the option is shown with an icon.
    let symbol: String
    let kind: Kind
    var defaultValue: Double = 0
    /// Short label for tiles and other tight spots (falls back to `title`).
    var short: String? = nil
    /// True when the bar or the mirror header already carries a dedicated control for it.
    var hasDirectControl = false
}

/// A group of settings with a heading.
struct SettingSection {
    let id: String
    let title: String
    let symbol: String
}

/// Values of every setting, persisted as one JSON file in the state folder.
///
/// Why it exists: options used to be scattered flag files, each with its own read/write code.
/// Created once at launch; the HUD applies values when {@link SettingsStore.changed} fires, and
/// controls call `set`, `toggle` and `perform`.
final class SettingsStore {
    /// Posted after a value changed; `userInfo["id"]` is the setting id.
    static let changed = Notification.Name("dw.settings.changed")

    static let sections: [SettingSection] = [
        SettingSection(id: "explain", title: "解説パネル", symbol: "book"),
        SettingSection(id: "mirror", title: "ミラー", symbol: "bubble.left.and.text.bubble.right"),
        SettingSection(id: "bar", title: "ステータスバー", symbol: "rectangle.bottomthird.inset.filled"),
        SettingSection(id: "ask", title: "確認", symbol: "questionmark.bubble"),
        SettingSection(id: "general", title: "全般", symbol: "gearshape"),
    ]

    /// Every option, in display order. Adding a line here adds it to the settings card.
    static let registry: [Setting] = [
        Setting(id: "explain.visible", section: "explain", title: "解説を表示", symbol: "book",
                kind: .toggle, defaultValue: 1, short: "解説", hasDirectControl: true),
        Setting(id: "explain.zoom", section: "explain", title: "文字サイズ", symbol: "textformat.size",
                kind: .slider(min: 0.6, max: 2.5, step: 0.1), defaultValue: 1, hasDirectControl: true),
        Setting(id: "explain.reset", section: "explain", title: "位置とサイズ", symbol: "arrow.counterclockwise",
                kind: .action(button: "リセット", destructive: false), short: "解説を初期位置へ"),
        Setting(id: "mirror.visible", section: "mirror", title: "ミラーを表示", symbol: "bubble.left.and.text.bubble.right",
                kind: .toggle, defaultValue: 1, short: "ミラー", hasDirectControl: true),
        Setting(id: "mirror.fold", section: "mirror", title: "長いコマンドを折りたたむ", symbol: "list.bullet.indent",
                kind: .toggle, defaultValue: 1, short: "折りたたみ"),
        Setting(id: "mirror.zoom", section: "mirror", title: "文字サイズ", symbol: "textformat.size",
                kind: .slider(min: 0.6, max: 2.5, step: 0.1), defaultValue: 1, hasDirectControl: true),
        Setting(id: "mirror.opacity", section: "mirror", title: "背景の不透明度", symbol: "circle.lefthalf.filled",
                kind: .slider(min: 0.3, max: 1, step: 0.05), defaultValue: 0.95, short: "ミラーの不透明度"),
        Setting(id: "mirror.reset", section: "mirror", title: "位置とサイズ", symbol: "arrow.counterclockwise",
                kind: .action(button: "リセット", destructive: false), short: "ミラーを初期位置へ"),
        Setting(id: "bar.flash", section: "bar", title: "更新時のフラッシュ", symbol: "sparkles",
                kind: .toggle, defaultValue: 1, short: "フラッシュ"),
        Setting(id: "bar.opacity", section: "bar", title: "背景の不透明度", symbol: "circle.lefthalf.filled",
                kind: .slider(min: 0.2, max: 1, step: 0.05), defaultValue: 0.42, short: "バーの不透明度"),
        Setting(id: "bar.reset", section: "bar", title: "位置と幅", symbol: "arrow.counterclockwise",
                kind: .action(button: "リセット", destructive: false), short: "バーを初期位置へ"),
        Setting(id: "ask.sound", section: "ask", title: "確認時にサウンドを鳴らす", symbol: "speaker.wave.2",
                kind: .toggle, defaultValue: 1, short: "サウンド"),
        Setting(id: "ask.reset", section: "ask", title: "位置（ドラッグで移動できます）", symbol: "arrow.counterclockwise",
                kind: .action(button: "リセット", destructive: false), short: "確認を初期位置へ"),
        Setting(id: "stop.hotkey", section: "general", title: "停止のショートカット ⌃⌥⌘.", symbol: "keyboard",
                kind: .toggle, defaultValue: 1, short: "停止キー"),
        Setting(id: "hud.quit", section: "general", title: "HUD", symbol: "power",
                kind: .action(button: "終了", destructive: true), short: "HUDを終了"),
    ]

    static func setting(_ id: String) -> Setting? { registry.first { $0.id == id } }

    private let path: String
    private var values: [String: Double] = [:]
    /// Handlers of `.action` settings, registered by the HUD at launch.
    var actions: [String: () -> Void] = [:]

    /// - Parameter stateDir: Folder shared with `dw`; `settings.json` lives directly in it.
    init(stateDir: String) {
        path = "\(stateDir)/settings.json"
        if let data = FileManager.default.contents(atPath: path),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in object {
                if let number = value as? NSNumber { values[key] = number.doubleValue }
            }
        } else {
            // First launch with this format: carry over what the flag files said
            migrateLegacyFlags(in: stateDir)
        }
    }

    /// Current value, or the registry default when it was never changed.
    func value(_ id: String) -> Double { values[id] ?? (Self.setting(id)?.defaultValue ?? 0) }

    func isOn(_ id: String) -> Bool { value(id) >= 0.5 }

    /// Store a value (sliders are clamped and snapped to their step) and tell observers.
    func set(_ id: String, _ raw: Double) {
        var next = raw
        if let setting = Self.setting(id), case let .slider(min, max, step) = setting.kind {
            next = Swift.min(max, Swift.max(min, (raw / step).rounded() * step))
        }
        next = (next * 1000).rounded() / 1000
        guard abs(value(id) - next) > 0.0001 else { return }
        values[id] = next
        save()
        NotificationCenter.default.post(name: Self.changed, object: self, userInfo: ["id": id])
    }

    func toggle(_ id: String) { set(id, isOn(id) ? 0 : 1) }

    /// Run the command behind an `.action` setting.
    func perform(_ id: String) { actions[id]?() }

    /// Write the values as small, stable JSON (sorted keys, at most three decimals).
    private func save() {
        let lines = values.sorted { $0.key < $1.key }.map { key, value -> String in
            let text = value == value.rounded() ? String(Int(value)) : String(format: "%.3f", value).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            return "  \"\(key)\": \(text)"
        }
        let json = "{\n" + lines.joined(separator: ",\n") + "\n}\n"
        try? json.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// One-time import of the flag files earlier versions used, so nobody loses their choices.
    private func migrateLegacyFlags(in dir: String) {
        let fm = FileManager.default
        func number(_ name: String) -> Double? {
            (try? String(contentsOfFile: "\(dir)/\(name)", encoding: .utf8)).flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        if fm.fileExists(atPath: "\(dir)/mirror-off") { values["mirror.visible"] = 0 }
        if fm.fileExists(atPath: "\(dir)/mirror-fold-off") { values["mirror.fold"] = 0 }
        if fm.fileExists(atPath: "\(dir)/hud-flash-off") { values["bar.flash"] = 0 }
        if let opacity = number("mirror-opacity") { values["mirror.opacity"] = opacity }
        if let zoom = number("mirror-zoom") { values["mirror.zoom"] = zoom }
        if !values.isEmpty { save() }
        // The flag files are superseded by settings.json
        for name in ["mirror-off", "mirror-fold-off", "hud-flash-off", "mirror-opacity", "mirror-zoom"] {
            try? fm.removeItem(atPath: "\(dir)/\(name)")
        }
    }
}
