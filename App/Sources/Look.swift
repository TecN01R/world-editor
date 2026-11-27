import SwiftUI
import UIKit

/// The app's one look (Kevin, 2026-11-27: "I don't need multiple themes we need to arrive at one
/// layout"; "experience will be [the arbiter] and so will research and comparing to other apps").
/// Apple's dark greys, warmed very slightly: between pure black, which ChatGPT's users called
/// "painful to look at", and a brown that reads as muddy; off-white text, never pure white; one
/// muted amber accent (private/reports/, and the comparison with writing and chat apps the same
/// day). Set only in iOS's own ways (a navigation container's background, the window's background
/// and tint colour, `tint`), on every screen, so nothing sits as a coloured panel inside grey bars,
/// as gruvbox did ("The gruvbox looks half assed").
enum Look {
    /// Behind everything (Apple's elevated base grey #1C1C1E, warmed).
    static let background = color(0x1C1A17)
    /// A raised surface, such as the author's message bubble (Apple's #2C2C2E, warmed).
    static let raised = color(0x2C2925)
    /// The author's words (their pages' writing and titles, in Edit and Focus mode, and their
    /// messages) and the companion's replies: 13.3:1 on the background.
    static let ink = color(0xE6E1D8)
    /// Buttons, links, the caret and what's new: 7.7:1 on the background, as is the background's
    /// colour drawn on it (the Send arrow).
    static let accent = color(0xD4A373)

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// The look's background behind this screen: its whole navigation container, bars included,
    /// and whatever isn't one (the companion's column), with lists and forms showing it through.
    func lookBackground() -> some View {
        let background = Color(Look.background)
        return scrollContentBackground(.hidden)
            .containerBackground(background, for: .navigation)
            .background(background)
    }
}
