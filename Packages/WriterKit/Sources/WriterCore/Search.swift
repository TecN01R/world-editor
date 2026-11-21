import Foundation

/// Showing search results: which words to bold and where a passage's match
/// is. Finding and ranking is Spotlight's job (the app's `PageIndex`); plain
/// word matching here only covers the moment before Spotlight answers.
public enum Search {
    /// Where `query` first appears in `text`, ignoring case and accents.
    public static func range(of query: String, in text: String) -> Range<String.Index>? {
        query.isEmpty ? nil : text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
    }

    /// The terms of `query`: its words, with "quoted phrases" kept whole.
    public static func terms(_ query: String) -> [String] {
        var terms: [String] = [], current = "", quoted = false
        func finish() {
            let term = current.trimmingCharacters(in: .whitespaces)
            if !term.isEmpty { terms.append(term) }
            current = ""
        }
        for c in query {
            if c == "\"" || c == "“" || c == "”" { finish(); quoted.toggle() }
            else if c.isWhitespace && !quoted { finish() }
            else { current.append(c) }
        }
        finish()
        return terms
    }
}

extension Document {
    /// Whether every term of `query` appears in the title or text.
    public func contains(allOf query: String) -> Bool {
        let terms = Search.terms(query)
        return !terms.isEmpty && terms.allSatisfy { term in
            Search.range(of: term, in: title) != nil || paragraphs.contains { Search.range(of: term, in: $0.text) != nil }
        }
    }

    /// The first paragraph holding any of `query`'s terms.
    public func paragraph(matching query: String) -> Int? {
        let terms = Search.terms(query)
        return paragraphs.firstIndex { p in terms.contains { Search.range(of: $0, in: p.text) != nil } }
    }

    /// The UTF-16 offset of the first of `query`'s terms in paragraph `index`,
    /// so a result opens at the words, not the paragraph's start.
    public func offset(of query: String, inParagraph index: Int) -> Int? {
        let text = paragraphs[index].text
        let first = Search.terms(query).compactMap { Search.range(of: $0, in: text)?.lowerBound }.min()
        return first.map { text.utf16.distance(from: text.startIndex, to: $0) }
    }

    /// Paragraph `index` from `lead` characters before UTF-16 `offset`, with
    /// "…" if cut, so the match shows in a one-line result.
    public func excerpt(paragraph index: Int, at offset: Int = 0, lead: Int = 24) -> String {
        let text = paragraphs[index].text
        let at = text.utf16.index(text.startIndex, offsetBy: min(offset, text.utf16.count))
        let start = text.index(at, offsetBy: -lead, limitedBy: text.startIndex) ?? text.startIndex
        return (start > text.startIndex ? "…" : "") + text[start...]
    }
}
