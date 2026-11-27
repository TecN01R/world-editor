import Foundation

/// The author's words as print sets them, for reading (Kevin, 2026-11-27: "the text has to look
/// gorgeous like it was printed"): curly quotes and apostrophes, true dashes and ellipses. Only
/// ever for showing: what the author typed is stored as they typed it.
public enum Typeset {
    /// One thing print sets differently: the stretch of the text it replaces, in UTF-16 units
    /// (as TextKit and `NSRange` count), and what it becomes.
    public struct Change: Equatable, Sendable {
        public var range: Range<Int>
        public var replacement: String
    }

    /// `text` as print sets it.
    public static func printed(_ text: String) -> String {
        var units = Array(text.utf16)
        for change in changes(in: text).reversed() {
            units.replaceSubrange(change.range, with: change.replacement.utf16)
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// What print sets differently in `text`, first to last, so styled text can be changed in
    /// place, keeping its styles and links:
    /// - a straight quote opens (“ ‘) at the start, after a space, a bracket or an opening quote,
    ///   and after a dash when a word follows; otherwise it closes (” ’);
    /// - an apostrophe after a letter or digit, or before a digit ('90s), is ’;
    /// - two or three hyphens are an em dash (—); one, or four or more (a rule), stay;
    /// - three dots are an ellipsis (…).
    public static func changes(in text: String) -> [Change] {
        let scalars = Array(text.unicodeScalars)
        var changes: [Change] = []
        var at = 0                                // UTF-16 offset of scalars[i]
        var previous: Unicode.Scalar?             // the one before, as printed
        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            let next = i + 1 < scalars.count ? scalars[i + 1] : nil
            // Hyphens and dots count in runs: how many in a row start here.
            var run: Int { scalars[i...].prefix { $0 == scalar }.count }
            var replacement: String?
            var length = 1
            switch scalar {
            case "\"":
                replacement = opens(after: previous, before: next) ? "\u{201C}" : "\u{201D}"
            case "'":
                let apostrophe = previous.map(isWord) == true || next.map(isDigit) == true
                replacement = !apostrophe && opens(after: previous, before: next) ? "\u{2018}" : "\u{2019}"
            case "-":
                length = run
                if length == 2 || length == 3 { replacement = "\u{2014}" }
            case ".":
                length = min(run, 3)
                if length == 3 { replacement = "\u{2026}" }
            default:
                break
            }
            if let replacement {
                changes.append(Change(range: at..<(at + length), replacement: replacement))
                previous = replacement.unicodeScalars.last
            } else {
                previous = scalars[i + length - 1]
            }
            at += scalars[i..<(i + length)].reduce(0) { $0 + $1.utf16.count }
            i += length
        }
        return changes
    }

    /// Whether a quote between `previous` and `next` opens rather than closes.
    private static func opens(after previous: Unicode.Scalar?, before next: Unicode.Scalar?) -> Bool {
        guard let previous else { return true }
        if previous.properties.isWhitespace || "([{\u{201C}\u{2018}".unicodeScalars.contains(previous) { return true }
        // After a dash, it opens what follows ("He said—“Go”") or closes what broke off ("“Wait—”").
        if "-\u{2013}\u{2014}".unicodeScalars.contains(previous) { return next.map(isWord) ?? false }
        return false
    }

    private static func isWord(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        return properties.isAlphabetic || properties.numericType != nil
            || [.nonspacingMark, .spacingMark, .enclosingMark].contains(properties.generalCategory)
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar.properties.numericType != nil }
}
