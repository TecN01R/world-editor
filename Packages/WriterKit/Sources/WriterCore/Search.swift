import Foundation

/// Showing search results: which words to bold and where a passage's match
/// is, and the passages a page is searched as. Finding and ranking for the
/// search field is Spotlight's job (the app's `PageIndex`); the companion's
/// search (Guardrails' `PageLookup`) ranks the same passages by their words.
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

    /// One passage of a page, as Spotlight indexes it and the companion's search
    /// finds it: its title, its fields or one paragraph. Its `id` is the Spotlight
    /// item's, "<page>/title", "<page>/fields" or "<page>/<paragraph>", so the
    /// ids written to the index and read back from it are the same.
    public struct Item: Hashable, Sendable {
        public enum Part: Hashable, Sendable {
            case title, fields
            case paragraph(UUID)
        }

        public var page: UUID
        public var part: Part

        public init(page: UUID, part: Part) {
            self.page = page
            self.part = part
        }

        /// The item `id` names; nil if it names none.
        public init?(id: String) {
            let parts = id.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, let page = UUID(uuidString: String(parts[0])) else { return nil }
            switch parts[1] {
            case "title": part = .title
            case "fields": part = .fields
            default:
                guard let paragraph = UUID(uuidString: String(parts[1])) else { return nil }
                part = .paragraph(paragraph)
            }
            self.page = page
        }

        public var id: String {
            let part = switch part {
            case .title: "title"
            case .fields: "fields"
            case .paragraph(let id): id.uuidString
            }
            return "\(page.uuidString)/\(part)"
        }
    }

    /// What is indexed of `page`: its title, its `fields` text ("Species: Elf"
    /// lines) and each paragraph, leaving out the empty ones.
    public static func passages(of page: Document, fields: String) -> [(item: Item, text: String)] {
        let title = page.title.trimmingCharacters(in: .whitespaces)
        let paragraphs = page.paragraphs.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        return (title.isEmpty ? [] : [(Item(page: page.id, part: .title), title)])
            + (fields.isEmpty ? [] : [(Item(page: page.id, part: .fields), fields)])
            + paragraphs.map { (Item(page: page.id, part: .paragraph($0.id)), $0.text) }
    }
}

extension Document {
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
