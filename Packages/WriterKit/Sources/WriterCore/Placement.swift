import Foundation

/// The author's sentences put into a page as its writing, by filing, each where it fits (at
/// the end of the author's paragraph about the same thing) or at the page's end (Kevin,
/// 2026-11-24: "I actually fully desire it to fill my pages as long as it uses my own words",
/// marked "who authored what", and reversible; 2026-11-26: "automatically"). Kept in the message's
/// `FilingRecord` (`.placed`) for its Undo. Its words are theirs, tidied only in case and
/// punctuation (`HisWords`, in Guardrails, makes and checks them).
public struct Placement: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var page: UUID
    /// The paragraphs it put words in, in order, and the words it put in each.
    public var paragraphs: [UUID]
    public var texts: [String]
    /// For each, whether its words went on at the end of a paragraph of the author's, where
    /// they fit (true), or are a paragraph of their own (false). Older records have none:
    /// all their own.
    public var appended: [Bool]
    public var date: Date

    public init(id: UUID = UUID(), page: UUID, paragraphs: [UUID], texts: [String], appended: [Bool] = [],
                date: Date = Date()) {
        self.id = id
        self.page = page
        self.paragraphs = paragraphs
        self.texts = texts
        self.appended = appended
        self.date = date
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        page = try c.decode(UUID.self, forKey: .page)
        paragraphs = try c.decode([UUID].self, forKey: .paragraphs)
        texts = try c.decode([String].self, forKey: .texts)
        appended = try c.decodeIfPresent([Bool].self, forKey: .appended) ?? []
        date = try c.decode(Date.self, forKey: .date)
    }

    /// Whether the words of its `n`th paragraph went on at the end of one of the author's.
    func isAppended(_ n: Int) -> Bool { appended.indices.contains(n) && appended[n] }
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

    /// Adds `text` at the end of paragraph `id`, after a space, marked as placed by
    /// `placement`. False if the page has no such paragraph.
    public mutating func append(_ text: String, to id: UUID, as placement: UUID) -> Bool {
        guard let i = paragraphs.firstIndex(where: { $0.id == id }) else { return false }
        var new = paragraphs
        let p = new[i]
        let space = p.text.isEmpty || p.text.last?.isWhitespace == true ? "" : " "
        let run = PlacedRun(location: p.length + space.utf16.count, length: text.utf16.count, placement: placement)
        new[i].setText(p.text + space + text, runs: p.runs, links: p.links, placed: p.placed + [run])
        setParagraphsAsIs(new)
        return true
    }

    /// Takes `placement` back where it's still as it left it, every letter its own: a
    /// paragraph it added goes, words it added to one of the author's go with the space
    /// before them. Words the author has written in since are theirs now, and stay.
    /// Returns whether anything went.
    @discardableResult
    public mutating func takeBack(_ placement: Placement) -> Bool {
        var kept = paragraphs
        var changed = false
        for (n, (id, text)) in zip(placement.paragraphs, placement.texts).enumerated() {
            guard let i = kept.firstIndex(where: { $0.id == id }) else { continue }
            let p = kept[i]
            let runs = p.placed.filter { $0.placement == placement.id }
            if placement.isAppended(n) {
                guard runs.count == 1, let run = runs.first else { continue }
                let units = Array(p.text.utf16)
                let range = run.location..<(run.location + run.length)
                guard String(decoding: units[range], as: UTF16.self) == text else { continue }
                let from = run.location > 0 && units[run.location - 1] == 0x20 ? run.location - 1 : run.location
                kept[i].replace(from..<range.upperBound, with: "", style: [])
            } else {
                guard p.text == text,
                      p.placed == [PlacedRun(location: 0, length: p.length, placement: placement.id)] else { continue }
                kept.remove(at: i)
            }
            changed = true
        }
        guard changed else { return false }
        setParagraphsAsIs(kept)
        return true
    }
}
