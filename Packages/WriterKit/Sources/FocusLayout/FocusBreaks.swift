import Foundation

/// Where Focus mode may break a word across lines. Offsets are UTF-16, as
/// TextKit counts them.
public enum FocusBreaks {
    /// Where the paragraph's last word starts. That word is never hyphenated:
    /// it's usually the one being typed, and would split and rejoin under the
    /// caret.
    public static func lastWordStart(_ text: String) -> Int {
        let s = text as NSString
        var end = s.length
        while end > 0, isSpace(s.character(at: end - 1)) { end -= 1 }
        var start = end
        while start > 0, !isSpace(s.character(at: start - 1)) { start -= 1 }
        return start
    }

    /// Whether a line ending at `index` cuts a word in two, so it needs a
    /// hyphen to be allowed: text on both sides, and not a place lines may
    /// break anyway (after a hyphen, dash or slash; beside a character of a
    /// script that breaks between characters, such as Chinese or Thai).
    public static func splitsWord(_ text: String, at index: Int) -> Bool {
        let s = text as NSString
        guard index > 0, index < s.length,
              let before = scalar(s, at: s.rangeOfComposedCharacterSequence(at: index - 1).location),
              let after = scalar(s, at: index) else { return false }
        return !isSpace(before) && !isSpace(after) && !breaksAfter.contains(before)
            && !breaksAnywhere(before) && !breaksAnywhere(after)
    }

    private static let breaksAfter: Set<Unicode.Scalar> = ["-", "\u{2010}", "\u{2013}", "\u{2014}", "/"]

    /// Ideographs, kana, Hangul and the Southeast Asian scripts that write
    /// no spaces: lines break between their characters without a hyphen.
    private static func breaksAnywhere(_ c: Unicode.Scalar) -> Bool {
        if c.properties.isIdeographic { return true }
        switch c.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F,   // kana
             0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF,   // Hangul
             0x0E00...0x0EFF, 0x1000...0x109F, 0x1780...0x17FF:   // Thai, Lao, Myanmar, Khmer
            return true
        default:
            return false
        }
    }

    private static func scalar(_ s: NSString, at index: Int) -> Unicode.Scalar? {
        s.substring(with: s.rangeOfComposedCharacterSequence(at: index)).unicodeScalars.first
    }

    private static func isSpace(_ c: Unicode.Scalar) -> Bool { CharacterSet.whitespacesAndNewlines.contains(c) }

    private static func isSpace(_ c: unichar) -> Bool {
        Unicode.Scalar(c).map(CharacterSet.whitespacesAndNewlines.contains) ?? false
    }
}
