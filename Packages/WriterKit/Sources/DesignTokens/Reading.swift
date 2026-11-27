/// The rules for setting the author's writing to be read at length: how wide the column is and,
/// from how long its lines are (the measure, in em of the type size), how much room lines get
/// and how readily words break. The page, read or edited, and the conversation set their text
/// by these.
public enum Reading {
    /// The longest a line gets, in em: about 66 characters, past which the eye loses its place
    /// on the way back.
    public static let measureCap = 33.0

    /// How wide the reading column is on a screen `width` points wide: the width less the margin
    /// at each side, up to `measureCap`.
    public static func column(width: Double, fontSize: Double, margin: Double = Spacing.margin) -> Double {
        max(0, min(width - 2 * margin, measureCap * fontSize))
    }

    /// The measure of a column: its width in em of the type size, which the rules below go by.
    public static func measure(columnWidth: Double, fontSize: Double) -> Double {
        columnWidth / fontSize
    }

    /// About how many characters a line of that measure holds: two to the em.
    public static func charactersPerLine(measureEm: Double) -> Double {
        2 * measureEm
    }

    /// Line height as a multiple of the type size: a longer line needs more room for the eye to
    /// find the next one, and the short lines of very large text need less. It eases between
    /// its three values, so as the text size grows a line never gets shorter.
    public static func leading(measureEm: Double) -> Double {
        byMeasure(measureEm, short: 1.30, middling: 1.40, long: 1.47)
    }

    /// How readily words break at a line's end, for `NSParagraphStyle.hyphenationFactor`: freely
    /// on short lines, which few whole words fill, and sparingly on long ones.
    public static func hyphenation(measureEm: Double) -> Double {
        byMeasure(measureEm, short: 0.9, middling: 0.6, long: 0.4)
    }

    /// The line height in points for type of `fontSize` in a column: its leading, on a whole
    /// pixel of the screen so every line sits the same. The app sets it as the paragraph's exact
    /// line height. A scale of 0, UIKit's "unspecified", leaves it unrounded.
    public static func lineHeight(fontSize: Double, columnWidth: Double, displayScale: Double) -> Double {
        let height = fontSize * leading(measureEm: measure(columnWidth: columnWidth, fontSize: fontSize))
        return displayScale > 0 ? (height * displayScale).rounded() / displayScale : height
    }

    /// How far to raise the text so it sits in the middle of a line taller than the font's own,
    /// since TextKit puts all the extra room above it.
    public static func baselineOffset(lineHeight: Double, fontLineHeight: Double) -> Double {
        (lineHeight - fontLineHeight) / 2
    }

    /// The space between paragraphs of the writing, in em: half a line of type.
    public static let paragraphSpacing = 0.5

    /// The space between the items of a list, in em: closer than paragraphs, so the list holds
    /// together.
    public static let listItemSpacing = 0.25

    /// The space after a list's last item, in em: a paragraph's, so the writing takes up again.
    public static let listEndSpacing = 0.5

    /// Lines up to 12 em are short, as very large text makes them; 16 to 24 em middling, as on
    /// the folded Duo; from 28 em long, as unfolded. Between those, a value moves in a straight
    /// line from one to the next: a step there made a slightly larger text size set shorter lines.
    private static func byMeasure(_ measureEm: Double, short: Double, middling: Double, long: Double) -> Double {
        switch measureEm {
        case ..<12: short
        case ..<16: short + (middling - short) * (measureEm - 12) / 4
        case ...24: middling
        case ..<28: middling + (long - middling) * (measureEm - 24) / 4
        default: long
        }
    }
}
