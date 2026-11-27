import SwiftUI
import UIKit

/// The app's own colours, set only where iOS lets an app colour its views (the backgrounds
/// behind the writing, the conversation and the lists; the accent; the writing's ink), never
/// iOS's menus, alerts or keyboard. Warm by default, after gruvbox (Kevin, 2026-11-27, of
/// warmth: "I used to be partial to gruvbox myself but I don't want to deviate outside what
/// iOS allows"); each world's own, drawn from its art, is to come. Dark only, as the app is
/// (Info.plist's `UIUserInterfaceStyle`). Contrast on the background: the ink 10.8:1, the
/// accent 8.7:1.
enum Palette {
    /// Behind the writing, the conversation and the lists: gruvbox's bg0.
    static let background = color(0x282828)
    /// The author's words, wherever they're shown: gruvbox's fg1, a cream (pure white on
    /// black shimmered and read heavy).
    static let ink = color(0xEBDBB2)
    /// Buttons, links and the caret: gruvbox's yellow.
    static let accent = color(0xFABD2F)

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// A list, form or scroll view on the palette's background in place of iOS's grey; a
    /// list's rows keep iOS's own (a custom row background hides iOS's selection highlight)
    /// unless set with `calmRow`.
    func paletteBackground() -> some View {
        scrollContentBackground(.hidden).background(Color(Palette.background))
    }

    /// A list row on the palette's background, with no line between it and the next: the
    /// pages list as a book's contents rather than a settings screen (Kevin, 2026-11-27).
    /// Its background hides iOS's selection highlight, which is little loss: the highlight
    /// shows only in the unfolded drawer, and choosing a page closes the drawer.
    func calmRow() -> some View {
        listRowBackground(Color(Palette.background)).listRowSeparator(.hidden)
    }
}
