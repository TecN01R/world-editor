import UIKit
import CoreText
import FocusLayout
import WriterCore

/// Measures with the same TextKit 1 stack, font and paragraph style as the
/// focus editor's text view, so fitting and display agree exactly.
struct TextKitMeasurer: TextMeasurer {
    /// Bold and italic runs of the text being fitted; they change its width.
    var runs: [StyleRun] = []

    static func font(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .regular)
        return UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size)
    }

    static func attributes(size: Double) -> [NSAttributedString.Key: Any] {
        let f = font(CGFloat(size))
        let p = NSMutableParagraphStyle()
        let lh = CGFloat(FitEngine.lineHeight(for: size) * size)
        p.minimumLineHeight = lh
        p.maximumLineHeight = lh
        p.lineBreakMode = .byWordWrapping
        // Fixed line boxes. TextKit puts extra leading above the glyphs rather
        // than splitting it; FocusEditor verifies the real layout after fitting
        // and steps down if anything overhangs, so the approximation is safe.
        return [
            .font: f,
            .kern: CGFloat(FitEngine.tracking(for: size) * size),
            .paragraphStyle: p,
            .foregroundColor: UIColor.label,
        ]
    }

    func measure(_ text: String, fontSize: Double, width: Double) -> TextMeasurement {
        let attrs = Self.attributes(size: fontSize)
        let styled = text.isEmpty ? NSAttributedString(string: "M", attributes: attrs)
                                  : RichText.attributed(text, runs: runs, attributes: attrs)
        let storage = NSTextStorage(attributedString: styled)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)

        var lines = 0
        var widest: CGFloat = 0
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, used, _, _, _ in
            lines += 1
            widest = max(widest, used.width)
        }
        let used = layout.usedRect(for: container)

        // A single word wider than the page would be broken mid-word: not allowed.
        let longest = Self.words.matches(in: styled.string, range: NSRange(location: 0, length: styled.length))
            .map { styled.attributedSubstring(from: $0.range).size().width }
            .max() ?? 0

        return TextMeasurement(width: Double(widest), height: Double(used.height),
                               lineCount: max(lines, 1), fitsWithoutBreakingWords: longest <= CGFloat(width))
    }

    private static let words = try! NSRegularExpression(pattern: "\\S+")

    func ink(_ text: String) -> InkMetrics {
        let size: CGFloat = 100
        let f = Self.font(size)
        let ct = f as CTFont
        let chars = Array((text.isEmpty ? "M" : text).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(ct, chars, &glyphs, chars.count)
        var rects = [CGRect](repeating: .zero, count: glyphs.count)
        CTFontGetBoundingRectsForGlyphs(ct, .default, glyphs, &rects, glyphs.count)
        let top = rects.map(\.maxY).max() ?? f.capHeight
        let bottom = rects.map(\.minY).min() ?? 0
        return InkMetrics(ascent: Double(f.ascender / size), descent: Double(-f.descender / size),
                          inkAscent: Double(top / size), inkDescent: Double(max(0, -bottom) / size))
    }
}
