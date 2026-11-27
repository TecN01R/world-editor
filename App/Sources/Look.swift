import SwiftUI
import UIKit

/// How the app looks, chosen in the companion's menu (Kevin, 2026-11-27, of three directions
/// drawn: "I can't decide but they feel better than what we have today"; then "it'd be cool to
/// have themes ... I'm not trying to create a design or maintenance burden either"). A look is
/// colours only, the same screens in every one: Night Study, iOS's own soft grey; Lamplight, a
/// warm, muted near-black with cream writing and amber; World Book, a deep green with cream and
/// gold. Set only in iOS's own ways (a navigation container's background, the tint, the window's
/// background and tint colours), on every edge.
enum Look: String, CaseIterable, Identifiable {
    case nightStudy, lamplight, worldBook

    static let key = "look"
    /// The look chosen, for UIKit, which can't watch `@AppStorage`.
    static var current: Look { UserDefaults.standard.string(forKey: key).flatMap(Look.init) ?? .nightStudy }

    var id: Self { self }

    var name: String {
        switch self {
        case .nightStudy: "Night Study"
        case .lamplight: "Lamplight"
        case .worldBook: "World Book"
        }
    }

    /// Behind everything; nil: iOS's own.
    var background: UIColor? {
        switch self {
        case .nightStudy: nil
        case .lamplight: Self.color(0x1E1915)
        case .worldBook: Self.color(0x172220)
        }
    }

    /// Buttons, links and the caret; nil: iOS's own blue.
    /// Contrast on the background: amber 7.9:1, gold 6.8:1.
    var accent: UIColor? {
        switch self {
        case .nightStudy: nil
        case .lamplight: Self.color(0xD8A657)
        case .worldBook: Self.color(0xC9A24A)
        }
    }

    /// The author's words: cream in Lamplight and World Book (13.8:1 and 12.3:1 on their
    /// backgrounds), a touch off-white in Night Study (pure white on black shimmers and reads heavy).
    var ink: UIColor {
        switch self {
        case .nightStudy: UIColor(white: 1, alpha: 0.88)
        case .lamplight: Self.color(0xEEE4D3)
        case .worldBook: Self.color(0xE9DFC7)
        }
    }

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The look's background behind a screen: its whole navigation container (bars included) and
/// whatever isn't one (the companion's column), with lists and forms showing it through. In
/// Night Study, iOS's own, untouched.
private struct LookBackground: ViewModifier {
    @AppStorage(Look.key) private var look = Look.nightStudy

    func body(content: Content) -> some View {
        if let background = look.background.map(Color.init) {
            content
                .scrollContentBackground(.hidden)
                .containerBackground(background, for: .navigation)
                .background(background)
        } else {
            content
        }
    }
}

extension View {
    /// The chosen look's background behind this screen (`Look`).
    func lookBackground() -> some View { modifier(LookBackground()) }
}
