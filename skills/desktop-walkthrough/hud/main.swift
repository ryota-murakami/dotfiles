// Launches the status HUD.
//
// Usage: StatusHUD <state-dir>   (env: DW_CLAUDE_WINDOW = CGWindowID of the chat terminal, DW_OWNER_PID)
// Sources: HUD.swift (bar, mirror, approval prompt), Settings.swift (the options), Controls.swift
// (shared controls, stop shortcut), SettingsCard.swift (the settings UI). Built by `scripts/dw`.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
installEditMenu()
startActivationObserver()
let hud = HUD()
app.run()
