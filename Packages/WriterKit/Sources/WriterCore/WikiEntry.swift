import Foundation

/// A page read as a wiki entry (Kevin, 2026-11-27: "I do love reading a good wiki"; not keeping
/// one: "I want to feel like my world is growing itself and I'm uncovering it"): its writing with
/// the names of the world's other pages linked, as a wiki links them, and where else the world
/// mentions it, quoting the sentence that does, in the author's own words.
public enum WikiEntry {
    /// A stretch of writing: plain, or naming one of the world's pages.
    public struct Piece: Equatable, Sendable {
        public var text: String
        public var page: UUID?
    }

    /// Where another page mentions this one, and the sentence that does (nil: a field holds it).
    public struct Mention: Equatable, Sendable {
        public var page: UUID
        public var quote: String?
    }

    /// `text` in pieces, each naming one of `pages` (other than `except`) or not: whole words,
    /// ignoring case and accents, the longest name first ("The Salt Road" before "Salt"), each
    /// page linked once per text, as a wiki links a name the first time. Names under three
    /// letters are left alone, as too likely to be other words.
    public static func pieces(of text: String, linking pages: [Document], except: UUID) -> [Piece] {
        let names = pages.filter { $0.id != except && $0.deleted == nil }
            .map { (name: $0.heading.trimmingCharacters(in: .whitespaces), id: $0.id) }
            .sorted { $0.name.count > $1.name.count }
        // Each page's first place in the text that a longer name hasn't taken.
        var found: [(range: Range<String.Index>, id: UUID)] = []
        for (name, id) in names {
            let free = ranges(naming: name, in: text).first { range in !found.contains { $0.range.overlaps(range) } }
            if let free { found.append((free, id)) }
        }
        found.sort { $0.range.lowerBound < $1.range.lowerBound }
        var pieces: [Piece] = []
        var at = text.startIndex
        for (range, id) in found {
            if at < range.lowerBound { pieces.append(Piece(text: String(text[at..<range.lowerBound]))) }
            pieces.append(Piece(text: String(text[range]), page: id))
            at = range.upperBound
        }
        if at < text.endIndex { pieces.append(Piece(text: String(text[at...]))) }
        return pieces
    }

    /// The other pages that mention `page` (an `@` link, its name in their writing, or a field
    /// holding it), in `pages`' order, each with the first sentence that names or links it.
    public static func mentions(of page: Document, in pages: [Document], schema: Schema) -> [Mention] {
        let name = page.heading
        return pages.compactMap { other in
            guard other.id != page.id, other.deleted == nil else { return nil }
            for paragraph in other.paragraphs {
                let text = paragraph.text
                let linkedAt = paragraph.links.first { $0.page == page.id }
                    .map { String.Index(utf16Offset: min($0.location, text.utf16.count), in: text) }
                if let at = linkedAt ?? ranges(naming: name, in: text).first?.lowerBound {
                    return Mention(page: other.id, quote: sentence(around: at, in: text))
                }
            }
            let holds = schema.fields(of: schema.type(other.type)).contains { other.values[$0.id] == .page(page.id) }
            return holds ? Mention(page: other.id, quote: nil) : nil
        }
    }

    /// Where `text` names `name` as whole words, ignoring case and accents: "Mira" in "Mira's
    /// road", not in "Miradel". Names under three letters are never found, as too likely to be
    /// other words.
    static func ranges(naming name: String, in text: String) -> [Range<String.Index>] {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard name.count >= 3 else { return [] }
        func inWord(_ c: Character) -> Bool { c.isLetter || c.isNumber }
        var ranges: [Range<String.Index>] = []
        var from = text.startIndex
        while let range = text.range(of: name, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) {
            let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : " "
            let after = range.upperBound < text.endIndex ? text[range.upperBound] : " "
            if !inWord(before) && !inWord(after) { ranges.append(range) }
            from = range.upperBound
        }
        return ranges
    }

    /// The sentence of `text` that `index` is in: from after the last ".", "!" or "?" before it
    /// (followed by white space, or ending the text) to the next one, trimmed.
    static func sentence(around index: String.Index, in text: String) -> String {
        func ends(_ i: String.Index) -> Bool {
            ".!?".contains(text[i]) && (text.index(after: i) == text.endIndex || text[text.index(after: i)].isWhitespace)
        }
        let start = text[..<index].indices.last(where: ends).map { text.index(after: $0) } ?? text.startIndex
        let end = text[index...].indices.first(where: ends).map { text.index(after: $0) } ?? text.endIndex
        return text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
