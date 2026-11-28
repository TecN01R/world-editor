import SwiftUI
import UIKit

/// The app's one look, in grey and white only, as ChatGPT has it (Kevin, 2026-11-27: "All the
/// mixture of cool and warm colors and random icon colors just seems unprofessional and poorly
/// thought out"): iOS's own dark greys (the elevated ones, not black), its own text colours, and
/// no accent colour, so nothing warm fights iOS's cool menus, keyboard and glass. Every control
/// is white; emphasis is white too (Send a white circle), and links are underlined rather than
/// coloured. Red only where iOS uses it, to delete. Decided from research and other apps, not by
/// him ("experience will be [the arbiter]"). Set on every screen in iOS's own ways (a navigation
/// container's background, the window's background and tint colour, `tint`). With it, the one
/// margin and reading column every screen shares (docs/design.md).
enum Look {
    /// Behind everything: iOS's own (the elevated level's grey, `WorldEditorApp.applyLook`).
    static let background = UIColor.systemBackground
    /// A raised surface, such as the author's message bubble.
    static let raised = UIColor.secondarySystemBackground
    /// The author's words and the companion's replies: a soft off-white, never pure white, which
    /// glares in long reading (Kevin, 2026-11-27: "easy to read chapter upon chapter"). Controls
    /// and the app's own words keep iOS's `label`; light mode, should it come back, gets that too.
    static let ink = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.9, alpha: 1) : .label }
    /// What stands out: Send, what's new, the caret. White, as every control is.
    static let emphasis = UIColor.label

    /// The one margin at the sides of every screen.
    static let margin: CGFloat = 20

    /// The reading column's greatest width: 33 em of the page font, about 66 characters a line.
    @MainActor static var measure: CGFloat { 33 * Role.writing.font.pointSize }

    /// The one reading column in `width`: the page, read or edited, and the conversation with its
    /// message bar. The width less the margins, up to `measure`; centred.
    @MainActor static func column(_ width: CGFloat) -> CGFloat { max(0, min(width - 2 * margin, measure)) }

    /// A link: underlined, not coloured (a text view's `linkTextAttributes`).
    static var link: [NSAttributedString.Key: Any] { [.underlineStyle: NSUnderlineStyle.single.rawValue] }
}

/// Undo, with one look everywhere: an icon button labelled Undo. Where it sits says what it
/// takes back, for VoiceOver too (`accessibilityLabel`).
struct UndoButton: View {
    let action: () -> Void

    var body: some View {
        Button("Undo", systemImage: "arrow.uturn.backward", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)   // in a list, only the button takes the tap, not its row
    }
}

extension View {
    /// In the reading column (`Look.column`): the margin at the sides, at most `Look.measure`
    /// wide, centred.
    func readingColumn() -> some View { modifier(ReadingColumn()) }

    /// The look's background behind this screen: its whole navigation container, bars included,
    /// and whatever isn't one, with lists and forms showing it through.
    func lookBackground() -> some View {
        let background = Color(Look.background)
        return scrollContentBackground(.hidden)
            .containerBackground(background, for: .navigation)
            .background(background)
    }
}

private struct ReadingColumn: ViewModifier {
    /// Read so a new text size resizes the column with the page font.
    @Environment(\.dynamicTypeSize) private var size

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: Look.measure)
            .padding(.horizontal, Look.margin)
            .frame(maxWidth: .infinity)
    }
}
