import Foundation

/// Finding pages by what they say: titles and text, ignoring case and accents.
public enum Search {
    /// Where `query` first appears in `text`.
    public static func range(of query: String, in text: String) -> Range<String.Index>? {
        query.isEmpty ? nil : text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
    }
}

extension Document {
    /// Whether the title or any paragraph contains `query`.
    public func matches(_ query: String) -> Bool {
        Search.range(of: query, in: title) != nil || paragraphs.contains { Search.range(of: query, in: $0.text) != nil }
    }

    /// The first paragraph containing `query`, starting a little before the
    /// match so it shows in a one-line result.
    public func snippet(matching query: String, lead: Int = 24) -> String? {
        for p in paragraphs {
            guard let r = Search.range(of: query, in: p.text) else { continue }
            let start = p.text.index(r.lowerBound, offsetBy: -lead, limitedBy: p.text.startIndex) ?? p.text.startIndex
            return (start > p.text.startIndex ? "…" : "") + p.text[start...]
        }
        return nil
    }
}
