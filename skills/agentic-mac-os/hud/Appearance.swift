// Look shared by every surface of the HUD: its dark appearance, the colours each surface is known
// by, the materials behind translucent surfaces, and the user's accessibility display settings.
import AppKit

/// The user's display settings under System Settings → Accessibility → Display.
///
/// Why it exists: the HUD is on screen all day, over every app, so it follows these settings the way
/// a part of the system would. Read wherever a surface decides how to draw; {@link HUD.applyDisplayOptions}
/// redraws the surfaces when one of them changes.
enum DisplayOptions {
    /// "Reduce motion": no slides, sweeps or repeating animations.
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// "Reduce transparency": every surface is opaque.
    static var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    /// "Increase contrast": stronger outlines and separators.
    static var increaseContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
}

/// Appearance of the whole HUD: dark whatever the system theme is (it lies over other apps like a
/// heads-up display), in its high-contrast variant while "Increase contrast" is on. Set on the app,
/// so native controls, menus and system colours follow it.
var hudAppearance: NSAppearance {
    NSAppearance(named: DisplayOptions.increaseContrast ? .accessibilityHighContrastDarkAqua : .darkAqua) ?? NSAppearance.currentDrawing()
}

extension NSColor {
    /// The colour as a layer needs it, resolved in the HUD's appearance. A system colour read outside
    /// of drawing can resolve for the light theme; layers keep whatever value they were given.
    var hudCG: CGColor {
        var resolved = cgColor
        hudAppearance.performAsCurrentDrawingAppearance { resolved = self.cgColor }
        return resolved
    }
}

// MARK: colours

/// Colour of the mirror and of what belongs to the conversation (its border, the agent's name).
let accent = NSColor.systemBlue
/// Fill of the main answer and of a switch that is on: the system's colour for the primary control.
let primaryFill = NSColor.controlAccentColor
/// Border and highlight colour of the explainer, so it is not mistaken for the mirror.
var explainAccent: NSColor {
    DisplayOptions.increaseContrast
        ? NSColor(calibratedRed: 0.53, green: 0.92, blue: 0.77, alpha: 1)
        : NSColor(calibratedRed: 0.36, green: 0.80, blue: 0.62, alpha: 1)
}
/// Border and heading colour of the note, so it is not mistaken for the explainer or the mirror.
let noteAccent = NSColor.systemYellow
/// Colour of the border around the screen while the walkthrough acts: the green of a recording indicator.
let performingBorderColor = NSColor.systemGreen
/// Corner radius of every floating surface (explainer, note, mirror, prompt card, settings card).
let surfaceCornerRadius: CGFloat = 14
/// Width of the outline of every surface (bar, explainer, note, mirror, prompt card, settings card):
/// one point, two while "Increase contrast" is on. The colour says which surface it is; the line
/// itself stays as thin as a window's edge.
var surfaceBorderWidth: CGFloat { DisplayOptions.increaseContrast ? 2 : 1 }

/// Opacity of a surface's background: the wanted value, or opaque while "Reduce transparency" is on.
func surfaceAlpha(_ wanted: CGFloat) -> CGFloat { DisplayOptions.reduceTransparency ? 1 : wanted }

// MARK: materials

/// A stretchable mask with rounded corners, for a material that must not show outside its surface.
func roundedMask(radius: CGFloat) -> NSImage {
    let side = radius * 2 + 1
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
}

/// The material behind a translucent surface: it blurs what is under the surface, so text on it
/// stays readable over any app (a menu bar, a page of text).
///
/// Why it exists: a plain half-transparent colour let the words underneath show through the status
/// line and the conversation. The HUD's windows are never active, and a material follows its
/// window's state by default, so the state is pinned to active. Used by the bar and the mirror,
/// with the surface's own colour over it as a tint.
func makeHUDMaterial(cornerRadius: CGFloat) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .hudWindow
    view.blendingMode = .behindWindow
    view.state = .active
    view.maskImage = roundedMask(radius: cornerRadius)
    view.autoresizingMask = [.width, .height]
    return view
}
