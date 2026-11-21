import Foundation

/// Typing `@` starts a mention: the text from the `@` to the caret is a query
/// for a page title. A bare `@` offers the most recent pages.
public enum Mention {
    /// The `@query` ending at `caret` (UTF-16), with its range including the `@`.
    /// The `@` starts the paragraph or follows a space. The query may contain
    /// spaces only while it still matches one of `titles`, so ordinary writing
    /// after an `@` soon stops being a mention.
    public static func query(in text: String, caret: Int, titles: [String]) -> (range: Range<Int>, query: String)? {
        let units = Array(text.utf16)
        guard caret <= units.count,
              let at = units[..<caret].lastIndex(of: 0x40),                       // "@"
              at == 0 || isSpace(units[at - 1]) else { return nil }
        let query = String(decoding: units[(at + 1)..<caret], as: UTF16.self)
        if let first = query.unicodeScalars.first, first.properties.isWhitespace { return nil }
        if query.contains(where: \.isWhitespace), !titles.contains(where: { matches(query, $0) }) { return nil }
        return (at..<caret, query)
    }

    /// Whether `title` contains `query`, ignoring case and accents. Everything matches a bare `@`.
    public static func matches(_ query: String, _ title: String) -> Bool {
        query.isEmpty || title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func isSpace(_ unit: UInt16) -> Bool {
        Unicode.Scalar(unit).map(\.properties.isWhitespace) ?? false
    }
}
