import SwiftUI
import UIKit
import DesignTokens

/// One of the few ways text is set (docs/design.md, Type). Whose words they are decides the face:
/// his are New York, the app's own San Francisco. Each role has one size, line height and colour,
/// and grows with Dynamic Type as its text style does. The numbers are `TextRole`'s, tested in
/// `DesignTokens`; this makes the font from them, for UIKit (`font`, `attributes`) and for SwiftUI
/// (`View.role`), so no screen sets a font, size or colour of its own.
enum Role {
    // His words, in New York.

    /// A page's title, read or edited.
    case title
    /// A page's writing, and his messages. Its line height follows its column (`ReadingType`).
    case writing
    /// A page's name in a row or card.
    case name
    /// A field's value.
    case value
    /// A preview line or a quote under a name.
    case line
    /// A page's name in a note under a reply.
    case chip

    // The app's own, in San Francisco.

    /// The app's sentences.
    case body
    /// The companion's replies: `body` with more room between lines.
    case reply
    /// A heading in scrolling content.
    case heading
    /// A field's name, a page's kind, a date.
    case label
    /// Notes under replies: what was filed, looked up, thought.
    case note

    /// The role's numbers.
    var numbers: TextRole {
        switch self {
        case .title: .words.title
        case .writing: .words.body
        case .name: .words.name
        case .value: .words.value
        case .line: .words.line
        case .chip: .words.chip
        case .body: .ui.body
        case .reply: .ui.reply
        case .heading: .ui.heading
        case .label: .ui.label
        case .note: .ui.note
        }
    }

    /// `ink` for his words and what's read at length; `ink2` for the app's small text and a
    /// preview line.
    var color: UIColor {
        switch self {
        case .title, .writing, .name, .value, .chip, .body, .reply: Ink.ink
        case .line, .heading, .label, .note: Ink.ink2
        }
    }

    /// The role's font at the current text size.
    var font: UIFont {
        let numbers = numbers
        let system = UIFont.systemFont(ofSize: numbers.size, weight: numbers.weight.uiKit)
        let newYork = numbers.face == .newYork ? system.fontDescriptor.withDesign(.serif) : nil
        let base = newYork.map { UIFont(descriptor: $0, size: numbers.size) } ?? system
        return UIFontMetrics(forTextStyle: numbers.scalesAs.uiKit).scaledFont(for: base)
    }

    /// Baseline to baseline at the current text size, on a whole pixel of a screen with
    /// `displayScale` of them to the point (0, UIKit's "unspecified", leaves it unrounded). Nil
    /// for `writing`, whose line height follows its column (`ReadingType`).
    func lineHeight(displayScale: CGFloat) -> CGFloat? {
        guard let lineHeight = numbers.lineHeight else { return nil }
        let scaled = UIFontMetrics(forTextStyle: numbers.scalesAs.uiKit).scaledValue(for: lineHeight)
        return scaled.onPixel(of: displayScale)
    }

    /// Text in the role as UIKit sets it: its font and colour and, for a role with a line height
    /// of its own, lines exactly that far apart with the text in the middle of each (TextKit
    /// puts a taller line's extra room above the text otherwise).
    func attributes(displayScale: CGFloat) -> [NSAttributedString.Key: Any] {
        let font = font
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let lineHeight = lineHeight(displayScale: displayScale) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            attributes[.paragraphStyle] = paragraph
            attributes[.baselineOffset] = Reading.baselineOffset(lineHeight: lineHeight, fontLineHeight: font.lineHeight)
        }
        return attributes
    }
}

extension CGFloat {
    /// On a whole pixel of a screen with `displayScale` of them to the point; as it is for 0,
    /// UIKit's "unspecified".
    func onPixel(of displayScale: CGFloat) -> CGFloat {
        displayScale > 0 ? (self * displayScale).rounded() / displayScale : self
    }
}

extension View {
    /// Sets text in a role: its font at the current text size, its exact line height and its
    /// colour.
    func role(_ role: Role) -> some View { modifier(RoleStyle(role: role)) }
}

private struct RoleStyle: ViewModifier {
    let role: Role
    /// Read so a new text size sets the text again at that size.
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .font(Font(role.font))
            .lineHeight(role.lineHeight(displayScale: displayScale).map { .exact(points: $0) })
            .foregroundStyle(Color(uiColor: role.color))
    }
}

private extension TextRole.Weight {
    var uiKit: UIFont.Weight {
        switch self {
        case .regular: .regular
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

private extension TextRole.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .title1: .title1
        case .headline: .headline
        case .body: .body
        case .subheadline: .subheadline
        case .footnote: .footnote
        }
    }
}
