// Launches the status HUD.
//
// Usage: StatusHUD <state-dir>   (env: DW_CLAUDE_WINDOW = CGWindowID of the chat terminal, DW_OWNER_PID)
// Sources: HUD.swift (shared paths, the HUD class, lifecycle), Bar.swift, Mirror.swift and
// AskPrompt.swift (one surface each), Settings.swift (the options), SettingsCard.swift (the settings
// UI), Controls.swift (shared controls, stop shortcut). Built by `scripts/dw`.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
allowCursorInBackground()
installEditMenu()
startActivationObserver()
let hud = HUD()
app.run()
