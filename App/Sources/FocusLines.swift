import FocusLayout
import UIKit

/// Focus mode's line breaking, used by both its text view and its size
/// search so they break lines the same way. Words hyphenate, except the
/// paragraph's last one (see `FocusBreaks`). TextKit 1, which lets the
/// last word opt out; TextKit 2 has no such hook.
final class FocusHyphenation: NSObject, NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldBreakLineByHyphenatingBeforeCharacterAt charIndex: Int) -> Bool {
        guard let text = layoutManager.textStorage?.string else { return true }
        return charIndex < FocusBreaks.lastWordStart(text)
    }
}

/// Lays text out as the Focus text view does, off screen, and reports
/// where its letters are drawn.
final class FocusLines {
    struct Layout {
        /// The line boxes' height.
        var height: CGFloat
        /// The letters as drawn (glyph outlines), top-left origin; `.zero` if none.
        var ink: CGRect
        /// A word was cut without a hyphen, because it can't fit on a line.
        var splitsWord: Bool
        /// Where the longest line ends, counting spaces at its end.
        var end: CGFloat
    }

    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer()
    private let hyphenation = FocusHyphenation()

    init() {
        container.lineFragmentPadding = 0
        layoutManager.delegate = hyphenation
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
    }

    func layout(_ s: NSAttributedString, width: CGFloat) -> Layout {
        storage.setAttributedString(s)
        container.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        let text = s.string, lastWord = FocusBreaks.lastWordStart(text)
        var ink = CGRect.null, splitsWord = false, lineEnd: CGFloat = 0
        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: container)) { rect, _, _, glyphs, _ in
            let chars = self.layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let line = NSMutableAttributedString(attributedString: s.attributedSubstring(from: chars))
            let end = NSMaxRange(chars)
            if FocusBreaks.splitsWord(text, at: end) {
                if end < lastWord, Self.canHyphenate(text, at: end) {
                    line.append(NSAttributedString(string: "-", attributes: s.attributes(at: end - 1, effectiveRange: nil)))
                } else {
                    splitsWord = true
                }
            }
            // Core Text gives the glyph outlines; TextKit gives where the line sits.
            let ct = CTLineCreateWithAttributedString(line)
            let origin = self.layoutManager.location(forGlyphAt: glyphs.location)   // x after alignment; y the baseline
            let x = rect.minX + origin.x, baseline = rect.minY + origin.y
            lineEnd = max(lineEnd, x + CGFloat(CTLineGetTypographicBounds(ct, nil, nil, nil)))
            let b = CTLineGetBoundsWithOptions(ct, .useGlyphPathBounds)
            guard !b.isEmpty else { return }
            ink = ink.union(CGRect(x: x + b.minX, y: baseline - b.maxY, width: b.width, height: b.height))
        }
        return Layout(height: ceil(layoutManager.usedRect(for: container).height),
                      ink: ink.isNull ? .zero : ink, splitsWord: splitsWord, end: lineEnd)
    }

    /// Whether the language allows a hyphen at `index`, as TextKit decides.
    private static func canHyphenate(_ text: String, at index: Int) -> Bool {
        let s = text as CFString
        return CFStringGetHyphenationLocationBeforeIndex(s, index + 1, CFRange(location: 0, length: CFStringGetLength(s)),
                                                         0, CFLocaleCopyCurrent(), nil) == index
    }
}
