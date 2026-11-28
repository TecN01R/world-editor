import SwiftUI
import UIKit
import DesignTokens

/// The look's colours as the app draws them (docs/design.md, Colour): grey and white only, dark
/// only. Their numbers are `Tone`'s, where their contrast is tested. `ink` and `ink2` take their
/// brighter values while Increase Contrast is on. The surfaces and `faint` are iOS's own dynamic
/// colours, at the elevated level the app sets (`WorldEditorApp.applyLook`). SwiftUI takes them
/// as styles: `.foregroundStyle(.ink2)`.
enum Ink {
    /// His words, and the companion's replies: a soft white that doesn't glare over a long read.
    static let ink = adaptive(.ink, increasedContrast: .increasedContrast.ink)
    /// The app's small text: labels, notes, previews, dates, headings.
    static let ink2 = adaptive(.ink2, increasedContrast: .increasedContrast.ink2)
    /// iOS's secondary colour: symbols, placeholders, disabled controls, large text only. Too dim
    /// for small text.
    static let faint = UIColor.secondaryLabel
    /// Controls, Send, the dot on what's new.
    static let emphasis = UIColor(Tone.emphasis)
    /// Lines and borders.
    static let rule = UIColor(Tone.rule)
    /// A line or border that has to show more.
    static let ruleStrong = UIColor(Tone.ruleStrong)

    /// Behind everything on a screen.
    static let surface = UIColor.systemBackground
    /// A raised surface: his message's bubble, a card.
    static let raised = UIColor.secondarySystemBackground
    /// What sits on a raised surface and has to stand out from it.
    static let raised2 = UIColor.tertiarySystemBackground

    /// `tone`, or `increasedContrast` while Increase Contrast is on in iOS's Accessibility settings.
    private static func adaptive(_ tone: Tone, increasedContrast: Tone) -> UIColor {
        UIColor { UIColor($0.accessibilityContrast == .high ? increasedContrast : tone) }
    }
}

extension UIColor {
    /// A tone of the look as a colour.
    convenience init(_ tone: Tone) {
        self.init(red: CGFloat(tone.red) / 255, green: CGFloat(tone.green) / 255, blue: CGFloat(tone.blue) / 255,
                  alpha: tone.alpha)
    }
}

extension ShapeStyle where Self == Color {
    /// His words, and the companion's replies (`Ink.ink`).
    static var ink: Color { Color(uiColor: Ink.ink) }
    /// The app's small text (`Ink.ink2`).
    static var ink2: Color { Color(uiColor: Ink.ink2) }
    /// Symbols, placeholders, disabled controls, large text only (`Ink.faint`).
    static var faint: Color { Color(uiColor: Ink.faint) }
    /// Controls, Send, the dot on what's new (`Ink.emphasis`).
    static var emphasis: Color { Color(uiColor: Ink.emphasis) }
    /// Lines and borders (`Ink.rule`).
    static var rule: Color { Color(uiColor: Ink.rule) }
    /// A line or border that has to show more (`Ink.ruleStrong`).
    static var ruleStrong: Color { Color(uiColor: Ink.ruleStrong) }
    /// Behind everything on a screen (`Ink.surface`).
    static var surface: Color { Color(uiColor: Ink.surface) }
    /// A raised surface (`Ink.raised`).
    static var raised: Color { Color(uiColor: Ink.raised) }
    /// What sits on a raised surface (`Ink.raised2`).
    static var raised2: Color { Color(uiColor: Ink.raised2) }
}

extension View {
    /// A switch in iOS's own colour when it's on, where the app's other controls are white (the
    /// app's tint): white under its white knob, on and off couldn't be told apart.
    func stockSwitch() -> some View { tint(Color?.none) }
}
