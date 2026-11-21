import Foundation

/// Typing `@` starts a mention: the text from the `@` to the caret is a query
/// for a page title. A bare `@` offers the most recent pages.
public enum Mention {
    /// How long a query may grow: about one unfolded line, as Apple Notes
    /// keeps its `>>` suggestions up for one line (two when folded).
    public static let maxLength = 60

    /// The `@query` ending at `caret` (UTF-16), with its range including the `@`.
    /// The `@` starts the paragraph or follows a space; the query may hold
    /// spaces and punctuation, so a new page can be "The Black Tower".
    public static func query(in text: String, caret: Int) -> (range: Range<Int>, query: String)? {
        let units = Array(text.utf16)
        guard caret <= units.count,
              let at = units[..<caret].lastIndex(of: 0x40),                       // "@"
              at == 0 || isSpace(units[at - 1]),
              caret - at - 1 <= maxLength else { return nil }
        let query = String(decoding: units[(at + 1)..<caret], as: UTF16.self)
        if let first = query.unicodeScalars.first, first.properties.isWhitespace { return nil }
        return (at..<caret, query)
    }

    /// Whether `title` contains `query`, ignoring case and accents. Everything matches a bare `@`.
    public static func matches(_ query: String, _ title: String) -> Bool {
        query.isEmpty || Search.range(of: query, in: title) != nil
    }

    private static func isSpace(_ unit: UInt16) -> Bool {
        Unicode.Scalar(unit).map(\.properties.isWhitespace) ?? false
    }
}
