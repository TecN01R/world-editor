/// A colour of the app's one look, a grey or white: sRGB in 8-bit parts, and how solid it is.
/// The numbers are kept here so the look's contrast is tested on Linux; the app turns a tone
/// into a `Color` or `UIColor`.
public struct Tone: Hashable, Sendable, CustomStringConvertible {
    /// The sRGB parts, 0 to 255, for the app to make its colour from.
    public let red: UInt8, green: UInt8, blue: UInt8
    /// How solid it is, 0 (clear) to 1. Under 1 for iOS's secondary label and the rules, which
    /// let their surface show through.
    public let alpha: Double

    /// A tone from its parts: for a colour that isn't one of the tokens, such as one iOS
    /// resolved, to be measured or compared with them. `alpha` outside 0 to 1 counts as the
    /// nearer end, as UIKit counts it.
    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha > 0 ? min(alpha, 1) : 0   // not a number counts as clear
    }

    /// A solid tone as the design specification writes it: `Tone(hex: 0x1C1C1E)` is #1C1C1E.
    public init(hex: UInt32) {
        precondition(hex <= 0xFF_FFFF, "A tone is written 0xRRGGBB")
        self.init(red: UInt8(hex >> 16), green: UInt8((hex >> 8) & 0xFF), blue: UInt8(hex & 0xFF))
    }

    /// The tone as the design specification writes it, for a failed test to show: "#1C1C1E",
    /// or "#EBEBF599" (alpha last) when it is see-through.
    public var hex: String {
        var parts = [red, green, blue]
        if alpha < 1 { parts.append(UInt8((alpha * 255).rounded())) }
        return "#" + parts.map { ($0 < 16 ? "0" : "") + String($0, radix: 16, uppercase: true) }.joined()
    }

    /// `hex`, so a failed test names the tone.
    public var description: String { hex }

    /// The same tone letting more through: `ink.opacity(0.2)` is ink at 20%, a rule.
    public func opacity(_ opacity: Double) -> Tone {
        Tone(red: red, green: green, blue: blue, alpha: alpha * opacity)
    }

    /// What shows where this tone is drawn on a solid `surface`, the two mixed by alpha as iOS
    /// mixes them: the colour a see-through tone's contrast is measured with.
    public func over(_ surface: Tone) -> Tone {
        assert(surface.alpha == 1, "A tone is measured on a solid surface")
        func mix(_ top: UInt8, _ bottom: UInt8) -> UInt8 {
            UInt8((Double(top) * alpha + Double(bottom) * (1 - alpha)).rounded())
        }
        return Tone(red: mix(red, surface.red), green: mix(green, surface.green), blue: mix(blue, surface.blue))
    }
}

// The look's tones: dark appearance, the only one. The app draws its surfaces and `faint` with
// iOS's own dynamic colours; their values here are mirrors, so text can be measured against them.
extension Tone {
    /// The backgrounds, as `Tone.surface.base`.
    public static let surface = Surfaces()

    /// The author's words and the companion's replies: a soft white that doesn't glare over a
    /// long read.
    public static let ink = Tone(hex: 0xE6E6E6)

    /// Small text under 20 pt that isn't the writing itself: labels, notes, previews, dates,
    /// headings. Previews are the author's words, so this is not only the app's own text.
    public static let ink2 = Tone(hex: 0xC2C2C7)

    /// iOS's secondary label colour: symbols, placeholders, disabled controls, text from 24 pt,
    /// and whatever iOS draws itself. Too dim for small text.
    public static let faint = Tone(hex: 0xEBEBF5).opacity(0.6)

    /// Controls, Send, and the dot on what's new.
    public static let emphasis = Tone(hex: 0xFFFFFF)

    /// Lines and borders: ink at 20%.
    public static let rule = ink.opacity(0.2)

    /// A line or border that has to show more: ink at 35%.
    public static let ruleStrong = ink.opacity(0.35)

    /// What takes the inks' place while Increase Contrast is on, as `Tone.increasedContrast.ink`.
    public static let increasedContrast = IncreasedContrast()

    /// The look's backgrounds: iOS's dark greys one level up, never black.
    public struct Surfaces: Sendable {
        /// Behind everything on a screen.
        public let base = Tone(hex: 0x1C1C1E)
        /// A raised surface: the author's message bubble, a card.
        public let raised = Tone(hex: 0x2C2C2E)
        /// What sits on a raised surface and has to stand out from it.
        public let raised2 = Tone(hex: 0x3A3A3C)
    }

    /// The inks for someone who has turned Increase Contrast on in iOS's Accessibility settings.
    public struct IncreasedContrast: Sendable {
        /// In place of `Tone.ink`: full white.
        public let ink = Tone(hex: 0xFFFFFF)
        /// In place of `Tone.ink2`.
        public let ink2 = Tone(hex: 0xDEDEE3)
    }
}
