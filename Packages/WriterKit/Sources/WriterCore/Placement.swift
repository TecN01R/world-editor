import Foundation

/// One of the author's messages put into a page as its writing: Add to Page (Kevin,
/// 2026-11-24: "I actually fully desire it to fill my pages as long as it uses my own
/// words", marked "who authored what", and reversible). Kept on the message's turn
/// (`Conversation.Turn.placed`) for its Undo. Its words are theirs, tidied only in case
/// and punctuation (`HisWords`, in Guardrails, makes and checks them).
public struct Placement: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var page: UUID
    /// The paragraphs it added, in order, and the text each had then.
    public var paragraphs: [UUID]
    public var texts: [String]
    public var date: Date

    public init(id: UUID = UUID(), page: UUID, paragraphs: [UUID], texts: [String], date: Date = Date()) {
        self.id = id
        self.page = page
        self.paragraphs = paragraphs
        self.texts = texts
        self.date = date
    }
}

extension Document {
    /// Adds `texts` to the end of the page, one paragraph each, marked as placed by
    /// `placement`. An empty last line (a new page, or writing that ended with Return)
    /// takes the first of them. Returns the paragraphs it added, in order.
    public mutating func place(_ texts: [String], as placement: UUID) -> [UUID] {
        var added: [Paragraph] = texts.map { text in
            Paragraph(text: text, placed: [PlacedRun(location: 0, length: text.utf16.count, placement: placement)])
        }
        guard !added.isEmpty else { return [] }
        var paragraphs = self.paragraphs
        if let last = paragraphs.last, last.text.isEmpty {
            added[0].id = last.id
            paragraphs.removeLast()
        }
        setParagraphsAsIs(paragraphs + added)
        return added.map(\.id)
    }

    /// Takes `placement` back: each paragraph it added that's still as it left it, every
    /// letter its own. One the author has written in since is theirs now, and stays.
    /// Returns whether anything went.
    @discardableResult
    public mutating func takeBack(_ placement: Placement) -> Bool {
        let untouched = Set(zip(placement.paragraphs, placement.texts).filter { id, text in
            guard let p = paragraph(id) else { return false }
            return p.text == text && p.placed == [PlacedRun(location: 0, length: p.length, placement: placement.id)]
        }.map(\.0))
        guard !untouched.isEmpty else { return false }
        setParagraphsAsIs(paragraphs.filter { !untouched.contains($0.id) })
        return true
    }

    /// Whether any of `placement`'s words are still on the page, as placed.
    public func holds(_ placement: Placement) -> Bool {
        paragraphs.contains { $0.placed.contains { $0.placement == placement.id } }
    }
}
