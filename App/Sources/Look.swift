import SwiftUI
import UIKit

/// The app's one look, in grey and white only, as ChatGPT has it (Kevin, 2026-11-27: "All the
/// mixture of cool and warm colors and random icon colors just seems unprofessional and poorly
/// thought out"): iOS's own dark greys (the elevated ones, not black), its own text colours, and
/// no accent colour, so nothing warm fights iOS's cool menus, keyboard and glass. Every control
/// is white; emphasis is white too (Send a white circle), and links are underlined rather than
/// coloured. Red only where iOS uses it, to delete. Decided from research and other apps, not by
/// him ("experience will be [the arbiter]"). Set on every screen in iOS's own ways (a navigation
/// container's background, the window's background and tint colour, `tint`).
enum Look {
    /// Behind everything: iOS's own (the elevated level's grey, `WorldEditorApp.applyLook`).
    static let background = UIColor.systemBackground
    /// A raised surface, such as the author's message bubble.
    static let raised = UIColor.secondarySystemBackground
    /// The author's words and the companion's replies.
    static let ink = UIColor.label
    /// What stands out: Send, what's new, the caret. White, as every control is.
    static let emphasis = UIColor.label
}

extension View {
    /// The look's background behind this screen: its whole navigation container, bars included,
    /// and whatever isn't one, with lists and forms showing it through.
    func lookBackground() -> some View {
        let background = Color(Look.background)
        return scrollContentBackground(.hidden)
            .containerBackground(background, for: .navigation)
            .background(background)
    }
}
