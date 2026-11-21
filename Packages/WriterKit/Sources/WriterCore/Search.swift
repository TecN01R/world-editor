import Foundation

/// Finding pages by what they say: titles and text, ignoring case and accents.
/// A query is a set of terms, words or "quoted phrases", that must all appear,
/// in any order.
public enum Search {
    /// Where `query` first appears in `text`.
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

    /// `query` pages from `pages`, best first: title matches, then pages
    /// with all the terms in one paragraph, then the rest; ties keep their order.
    public static func rank(_ pages: [Document], _ query: String) -> [Document] {
        let terms = terms(query)
        guard !terms.isEmpty else { return pages }
        return pages.enumerated()
            .compactMap { i, page in page.score(terms).map { (page, $0, i) } }
            .sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }
            .map(\.0)
    }
}

/// Where a search matched: a paragraph and the first term's UTF-16 range in it.
public struct SearchHit: Equatable, Sendable {
    public let paragraph: Int
    public let range: Range<Int>
}

extension Document {
    /// Whether every term of `query` appears in the title or text.
    public func matches(_ query: String) -> Bool {
        let terms = Search.terms(query)
        return !terms.isEmpty && score(terms) != nil
    }

    /// The best place `query` appears in the text: the paragraph holding the
    /// most terms, earliest first.
    public func hit(_ query: String) -> SearchHit? {
        let terms = Search.terms(query)
        var best: (count: Int, hit: SearchHit)?
        for (i, p) in paragraphs.enumerated() {
            let found = terms.compactMap { Search.range(of: $0, in: p.text) }
            guard let first = found.min(by: { $0.lowerBound < $1.lowerBound }),
                  found.count > (best?.count ?? 0) else { continue }
            let lo = p.text.utf16.distance(from: p.text.startIndex, to: first.lowerBound)
            let hi = p.text.utf16.distance(from: p.text.startIndex, to: first.upperBound)
            best = (found.count, SearchHit(paragraph: i, range: lo..<hi))
        }
        return best?.hit
    }

    /// The best matching paragraph, starting a little before the match so it
    /// shows in a one-line result.
    public func snippet(matching query: String, lead: Int = 24) -> String? {
        hit(query).map { excerpt(paragraph: $0.paragraph, at: $0.range.lowerBound, lead: lead) }
    }

    /// Paragraph `index` from `lead` characters before UTF-16 `offset`, with "…" if cut.
    public func excerpt(paragraph index: Int, at offset: Int = 0, lead: Int = 24) -> String {
        let text = paragraphs[index].text
        let at = text.utf16.index(text.startIndex, offsetBy: min(offset, text.utf16.count))
        let start = text.index(at, offsetBy: -lead, limitedBy: text.startIndex) ?? text.startIndex
        return (start > text.startIndex ? "…" : "") + text[start...]
    }

    /// How well the page matches all `terms`, or nil if any is missing.
    func score(_ terms: [String]) -> Int? {
        var score = 0
        for term in terms {
            if Search.range(of: term, in: title) != nil { score += 2 }
            else if !paragraphs.contains(where: { Search.range(of: term, in: $0.text) != nil }) { return nil }
        }
        let together = paragraphs.contains { p in terms.allSatisfy { Search.range(of: $0, in: p.text) != nil } }
        return score + (together ? 1 : 0)
    }
}
