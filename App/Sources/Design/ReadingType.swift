import UIKit
import DesignTokens
import WriterCore

/// How the author's writing is set to be read at length (docs/design.md, Reading), in one column
/// on one screen at one text size: New York at the body size in `ink`; lines exactly the height
/// their length calls for, the text in the middle of each; hyphenated more freely the shorter the
/// lines; ragged right, a lone last word pushed out; half a line between paragraphs, a quarter
/// between a list's items. The rules and their numbers are `Reading`'s, tested in `DesignTokens`.
///
/// The page sets its writing by this read and edited, so the two can't drift. A text view keeps
/// the one its text was last set by, and when its column, its screen or the text size gives
/// another, sets the text again in place (`restyle`).
struct ReadingType: Equatable {
    /// How wide the column is that the writing is set in, in points.
    let columnWidth: CGFloat
    /// New York at the body size, grown with the text size.
    let font: UIFont
    /// Baseline to baseline: more room the longer the column's lines are, on a whole pixel.
    let lineHeight: CGFloat
    /// The screen's pixels to the point, which a paragraph's spacing is rounded to as well, so
    /// the lines after it sit on whole pixels as the ones before.
    private let displayScale: CGFloat

    /// The writing's setting in a column `columnWidth` points wide on a screen with `displayScale`
    /// pixels to the point (0, UIKit's "unspecified", rounds nothing), at the current text size.
    init(columnWidth: CGFloat, displayScale: CGFloat) {
        self.columnWidth = columnWidth
        self.displayScale = displayScale
        font = Role.writing.font
        lineHeight = Reading.lineHeight(fontSize: font.pointSize, columnWidth: columnWidth, displayScale: displayScale)
    }

    /// The same when they set text the same. (Two fonts made alike aren't promised to be equal
    /// objects, and a text view compares these on every layout.)
    static func == (a: ReadingType, b: ReadingType) -> Bool {
        a.columnWidth == b.columnWidth && a.lineHeight == b.lineHeight && a.displayScale == b.displayScale
            && a.font.pointSize == b.font.pointSize && a.font.fontName == b.font.fontName
    }

    /// How far the text is raised to sit in the middle of its line, with the caret and the
    /// selection: TextKit puts all of a taller line's extra room above the text otherwise.
    private var baselineOffset: CGFloat {
        Reading.baselineOffset(lineHeight: lineHeight, fontLineHeight: font.lineHeight)
    }

    // MARK: A paragraph

    /// A paragraph of the writing as the page sets it. Its `kind` and the kind of the paragraph
    /// after it (`next`, nil for the last) decide its list marker and the room under it.
    @MainActor func attributes(kind: ParagraphKind, before next: ParagraphKind?) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: Ink.ink, .paragraphStyle: paragraphStyle(kind: kind, before: next),
         .baselineOffset: baselineOffset]
    }

    /// What's typed next in such a paragraph: its attributes, in the bold or italic (`style`)
    /// before the caret.
    @MainActor func typingAttributes(kind: ParagraphKind, before next: ParagraphKind?,
                                     style: InlineStyle) -> [NSAttributedString.Key: Any] {
        var attributes = attributes(kind: kind, before: next)
        attributes[.font] = RichText.font(font, style)
        return attributes
    }

    /// The reading rules on a paragraph's style: `style` as it is (whatever else it carries) with
    /// its lines' height, how readily its words break, the room under it and its list set.
    /// Alignment stays natural, so the right edge is ragged.
    @MainActor private func paragraphStyle(_ style: NSParagraphStyle = .default, kind: ParagraphKind,
                                           before next: ParagraphKind?) -> NSParagraphStyle {
        let style = style.mutableCopy() as! NSMutableParagraphStyle
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.paragraphSpacing = (Self.spacing(after: kind, before: next) * font.pointSize).onPixel(of: displayScale)
        style.hyphenationFactor = Float(Reading.hyphenation(measureEm: Reading.measure(columnWidth: columnWidth,
                                                                                    fontSize: font.pointSize)))
        style.lineBreakStrategy = .pushOut
        style.textLists = RichText.list(for: kind).map { [$0] } ?? []
        return style
    }

    /// The room under a paragraph, in em: half a line of type; a quarter between the items of a
    /// list, and a paragraph's after its last. None under the last paragraph of all, where the
    /// page's own gap comes next.
    private static func spacing(after kind: ParagraphKind, before next: ParagraphKind?) -> Double {
        guard let next else { return 0 }
        guard kind.isList else { return Reading.paragraphSpacing }
        return next == kind ? Reading.listItemSpacing : Reading.listEndSpacing
    }

    // MARK: The whole text

    /// `paragraphs` as the page sets them, read or edited: each made by `paragraph` from it and
    /// its `attributes`, with a line break in those attributes between one and the next.
    @MainActor func text(of paragraphs: [Paragraph],
                         _ paragraph: (Paragraph, [NSAttributedString.Key: Any]) -> NSAttributedString) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for (i, p) in paragraphs.enumerated() {
            let isLast = i == paragraphs.count - 1
            let attributes = attributes(kind: p.kind, before: isLast ? nil : paragraphs[i + 1].kind)
            text.append(paragraph(p, attributes))
            if !isLast { text.append(NSAttributedString(string: "\n", attributes: attributes)) }
        }
        return text
    }

    /// Sets `text` by this in place, wherever it was set by another or its paragraphs now follow
    /// one another differently: fonts at this size keeping their bold and italic, and each
    /// paragraph's lines, hyphenation and the room under it. The string is untouched, so in a
    /// text view Undo, the caret and text still being composed stay as they are. A paragraph's
    /// kind is what its first character's style says; `trailingKind` is the kind of the empty
    /// last paragraph of a text ending in a line break, which has no character to say it.
    /// Returns whether anything changed.
    @MainActor @discardableResult
    func restyle(_ text: NSMutableAttributedString, trailingKind: ParagraphKind? = nil) -> Bool {
        let string = text.string as NSString
        // Each paragraph with its line break, which carries its style too.
        var paragraphs: [(range: NSRange, style: NSParagraphStyle?)] = []
        var start = 0
        while start < string.length {
            let lineBreak = string.range(of: "\n", range: NSRange(location: start, length: string.length - start))
            let end = lineBreak.location == NSNotFound ? string.length : NSMaxRange(lineBreak)
            paragraphs.append((NSRange(location: start, length: end - start),
                               text.attribute(.paragraphStyle, at: start, effectiveRange: nil) as? NSParagraphStyle))
            start = end
        }

        var changed = false
        func set(_ key: NSAttributedString.Key, _ value: Any, in range: NSRange) {
            if !changed { text.beginEditing() }
            changed = true
            text.addAttribute(key, value: value, range: range)
        }
        let kinds = paragraphs.map { RichText.kind(of: $0.style) }
        for (i, paragraph) in paragraphs.enumerated() {
            let next: ParagraphKind?
            if i + 1 < kinds.count {
                next = kinds[i + 1]
            } else if string.hasSuffix("\n") {
                next = trailingKind
            } else {
                next = nil
            }
            let style = paragraphStyle(paragraph.style ?? .default, kind: kinds[i], before: next)
            text.enumerateAttribute(.paragraphStyle, in: paragraph.range) { value, range, _ in
                if value as? NSParagraphStyle != style { set(.paragraphStyle, style, in: range) }
            }
        }
        let all = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.font, in: all) { value, range, _ in
            let old = value as? UIFont
            if old?.pointSize != font.pointSize { set(.font, RichText.font(font, RichText.style(of: old)), in: range) }
        }
        text.enumerateAttribute(.baselineOffset, in: all) { value, range, _ in
            if value as? CGFloat != baselineOffset { set(.baselineOffset, baselineOffset, in: range) }
        }
        if changed { text.endEditing() }
        return changed
    }
}
