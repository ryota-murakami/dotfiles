// Screen border of the HUD: a thin green line around the screen while the walkthrough itself is
// acting, the way screen recorders mark a screen that is being captured. It says "the agent is
// driving this Mac now: using it yourself would collide". Methods of the HUD class.
import AppKit

extension HUD {
    // MARK: screen border

    /// Show the border around every screen while the walkthrough acts, hide it otherwise.
    ///
    /// Why it exists: the user switched to another app in the middle of a performed step, the agent's
    /// keys were refused or went nowhere and the step fell apart; while the agent only waits, edits
    /// its skill or checks something, the user is free to use the Mac. The stop button says the same
    /// at one end of the bar; the border says it wherever the user is looking.
    /// Called by {@link HUD.applyActivity} whenever the state changes, and on every refresh tick so
    /// that a display that was connected or rearranged is followed.
    ///
    /// @param visible - True while the state is `.performing`.
    func updatePerformingBorder(visible: Bool) {
        guard visible, !hudHidden, settings.isOn("border.performing") else {
            for window in performingBorders where window.isVisible { window.orderOut(nil) }
            return
        }
        let screens = NSScreen.screens
        // One click-through window per screen, created when a screen appears
        while performingBorders.count < screens.count { performingBorders.append(makeBorderWindow()) }
        for (index, window) in performingBorders.enumerated() {
            guard index < screens.count else {
                if window.isVisible { window.orderOut(nil) }
                continue
            }
            let screen = screens[index]
            if window.frame != screen.frame { window.setFrame(screen.frame, display: true) }
            // One physical pixel, whatever the display's scale; a line of two points with "Increase contrast"
            window.contentView?.layer?.borderWidth = DisplayOptions.increaseContrast ? 2 : 1 / max(1, screen.backingScaleFactor)
            window.contentView?.layer?.borderColor = performingBorderColor.hudCG
            if !window.isVisible { window.orderFrontRegardless() }
        }
    }

    /// A transparent window that only draws its outline and lets every click through.
    private func makeBorderWindow() -> NSPanel {
        let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above the menu bar and the Dock, like the bar; not screen-saver level (that blocks Space switching)
        window.level = .statusBar
        window.collectionBehavior = hudCollectionBehavior
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        let outline = NSView()
        outline.wantsLayer = true
        outline.layer?.borderColor = performingBorderColor.hudCG
        outline.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = outline
        return window
    }
}
