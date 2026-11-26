import Foundation
import WriterCore

/// Documents the writer hands the companion (Kevin, 2026-11-25: "when can we get picture
/// analysis and pdf or text analysis"): a PDF's or text file's text, attached to their message
/// (`Conversation.Turn.attached`). A short one goes to the model whole, in their turn; a long
/// one goes with its opening, and the model searches the rest with `search_document`, which
/// answers with the passages that match, saying which document and where. Something to read
/// and answer from: not their words, so nothing in it is filed (docs/companion-roadmap.md, step 3).
public enum Documents {
    /// Up to this long, a document goes to the model whole.
    public static let wholeCharacters = 8000
    /// How much of a longer one's opening goes with it.
    static let openingCharacters = 2000
    public static let toolName = "search_document"
    public static let toolDescription = "Searches the documents the writer attached to this conversation for a few "
        + "words. Returns the passages that match, saying which document and where."
    public static let queryGuide = "A few words to look for in the attached documents"
    public static let needsQuery = "search_document needs a few words to look for."
    /// A piece of a long document, as it's searched, and how far pieces overlap.
    static let pieceCharacters = 1500
    static let overlap = 300
    /// The most passages, and characters, a search returns.
    static let passagesPerSearch = 4
    public static let maxCharacters = 6000

    public static func nothingFound(_ query: String) -> String {
        "Nothing in the attached documents mentions \u{201C}\(CompanionPrompt.oneLine(query, maxCharacters: 80))\u{201D}."
    }

    /// The author's turn as the model reads it: their words, then each document they attached,
    /// whole or, past `wholeCharacters`, its opening and how to read the rest. Pictures go to
    /// the model as pictures (`CompanionPrompt.Turn.pictures`), not here.
    public static func turn(_ message: String, _ attached: [Conversation.Attached]) -> String {
        var parts = message.isEmpty ? [] : [message]
        for document in attached where document.picture == nil {
            let text = document.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count <= wholeCharacters {
                parts.append("[Attached: \(document.name)]\n" + text)
            } else {
                parts.append("[Attached: \(document.name), \(text.count) characters. Its opening is below; "
                             + "search the rest with \(toolName).]\n" + String(text.prefix(openingCharacters)) + "\u{2026}")
            }
        }
        return parts.joined(separator: "\n\n")
    }

    /// The long documents attached in a conversation, in pieces, for `search_document`.
    public struct Lookup: Sendable {
        struct Piece: Sendable {
            let document: String
            let part: Int
            let parts: Int
            let text: String
            let words: Set<String>
        }
        let pieces: [Piece]

        /// Nil when nothing attached in `conversation` is long enough to need searching.
        public init?(_ conversation: Conversation) {
            var pieces: [Piece] = []
            for document in conversation.turns.flatMap({ $0.attached ?? [] }) where document.text.count > wholeCharacters {
                let texts = Documents.pieces(document.text)
                for (i, text) in texts.enumerated() {
                    pieces.append(Piece(document: document.name, part: i + 1, parts: texts.count, text: text,
                                        words: Set(PageLookup.words(text).map(\.word))))
                }
            }
            guard !pieces.isEmpty else { return nil }
            self.pieces = pieces
        }

        /// The passages that best match `query`: those with the most of its words, rarer words
        /// counting for more, in the order they come, within `maxCharacters`.
        public func results(for query: String) -> String {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return Documents.needsQuery }
            let wanted = Set(PageLookup.terms(query, leavingOut: PageLookup.stopwords).joined())
            func rarity(_ word: String) -> Double {
                log(Double(pieces.count + 1) / Double(pieces.filter { $0.words.contains(word) }.count + 1)) + 1
            }
            let weights = Dictionary(uniqueKeysWithValues: wanted.map { ($0, rarity($0)) })
            let scored = pieces.indices
                .map { i in (index: i, score: wanted.intersection(pieces[i].words).reduce(0) { $0 + weights[$1, default: 0] }) }
                .filter { $0.score > 0 }
            guard !scored.isEmpty else { return Reasoned.gemmaPlain(Documents.nothingFound(query)) }
            // The highest scores, the earlier piece first on a tie; then back in the documents' order.
            let best = scored.sorted { ($0.score, -$0.index) > ($1.score, -$1.index) }
                .prefix(Documents.passagesPerSearch).map(\.index).sorted()
            var text = "From the attached documents, for \u{201C}\(CompanionPrompt.oneLine(query, maxCharacters: 80))\u{201D}:"
            for i in best {
                let piece = pieces[i]
                let part = "[\(piece.document), part \(piece.part) of \(piece.parts)]\n\(piece.text)"
                guard text.count + part.count + 2 <= Documents.maxCharacters else { break }
                text += "\n\n" + part
            }
            return Reasoned.gemmaPlain(text)
        }
    }

    /// `text` in pieces of about `pieceCharacters`, each overlapping the last by `overlap`,
    /// cut where a paragraph, a sentence or at least a word ends.
    static func pieces(_ text: String) -> [String] {
        var pieces: [String] = [], start = text.startIndex
        while start < text.endIndex {
            var end = text.index(start, offsetBy: pieceCharacters, limitedBy: text.endIndex) ?? text.endIndex
            if end < text.endIndex {
                let window = text[text.index(start, offsetBy: pieceCharacters / 2)..<end]
                if let cut = window.range(of: "\n", options: .backwards)?.upperBound
                    ?? window.range(of: ". ", options: .backwards)?.upperBound
                    ?? window.lastIndex(where: \.isWhitespace) {
                    end = cut
                }
            }
            let piece = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
            guard end < text.endIndex else { break }
            start = text.index(end, offsetBy: -min(overlap, text.distance(from: start, to: end) / 2))
        }
        return pieces
    }
}
