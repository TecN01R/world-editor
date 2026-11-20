import Foundation

/// A paragraph is the unit both editors share: page view shows them together,
/// focus mode shows one per page. Identity is stable across edits so that
/// extracted facts can point back at the paragraph they came from.
public struct Paragraph: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }
}

/// The user's writing. Only the user's own edits change it: nothing in the AI
/// layers holds a mutable reference to a `Document`.
public struct Document: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public private(set) var paragraphs: [Paragraph]
    public var modified: Date

    public init(id: UUID = UUID(), title: String = "", paragraphs: [Paragraph] = [Paragraph()], modified: Date = Date()) {
        self.id = id
        self.title = title
        self.paragraphs = paragraphs.isEmpty ? [Paragraph()] : paragraphs
        self.modified = modified
    }

    /// Plain text with one paragraph per line; what page view edits.
    public var plainText: String { paragraphs.map(\.text).joined(separator: "\n") }

    public var wordCount: Int {
        paragraphs.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    public func paragraph(_ id: UUID) -> Paragraph? { paragraphs.first { $0.id == id } }
    public func index(of id: UUID) -> Int? { paragraphs.firstIndex { $0.id == id } }

    // MARK: Editing (user-initiated only)

    /// Replace the whole text (page view). Paragraph identities are kept for
    /// paragraphs whose text is unchanged or edited in place, so provenance
    /// survives ordinary editing.
    public mutating func setPlainText(_ text: String) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        paragraphs = ParagraphDiff.reconcile(old: paragraphs, newTexts: lines)
        modified = Date()
    }

    public mutating func setText(_ text: String, at index: Int) {
        guard paragraphs.indices.contains(index) else { return }
        paragraphs[index].text = text
        modified = Date()
    }

    /// Split paragraph `index` at character `offset` (Return). Returns the new paragraph's index.
    @discardableResult
    public mutating func split(at index: Int, offset: Int) -> Int {
        guard paragraphs.indices.contains(index) else { return index }
        let text = paragraphs[index].text
        let cut = text.index(text.startIndex, offsetBy: max(0, min(offset, text.count)))
        paragraphs[index].text = String(text[..<cut])
        paragraphs.insert(Paragraph(text: String(text[cut...])), at: index + 1)
        modified = Date()
        return index + 1
    }

    /// Join paragraph `index` onto the previous one (Backspace at start).
    /// Returns the caret offset in the merged paragraph, or nil if nothing to merge.
    @discardableResult
    public mutating func mergeWithPrevious(_ index: Int) -> Int? {
        guard index > 0, paragraphs.indices.contains(index) else { return nil }
        let joinAt = paragraphs[index - 1].text.count
        paragraphs[index - 1].text += paragraphs[index].text
        paragraphs.remove(at: index)
        modified = Date()
        return joinAt
    }
}

/// Keeps paragraph IDs stable when page view replaces the whole text.
enum ParagraphDiff {
    static func reconcile(old: [Paragraph], newTexts: [String]) -> [Paragraph] {
        // Match unchanged paragraphs first (in order), then reuse the remaining
        // old IDs positionally for edited paragraphs.
        var used = Set<Int>()
        var result: [Paragraph?] = Array(repeating: nil, count: newTexts.count)
        var searchFrom = 0
        for (i, text) in newTexts.enumerated() {
            if let j = old[searchFrom...].firstIndex(where: { $0.text == text }), !used.contains(j) {
                result[i] = Paragraph(id: old[j].id, text: text)
                used.insert(j)
                searchFrom = j + 1
            }
        }
        var spare = old.indices.filter { !used.contains($0) }.makeIterator()
        for i in result.indices where result[i] == nil {
            if let j = spare.next() { result[i] = Paragraph(id: old[j].id, text: newTexts[i]) }
            else { result[i] = Paragraph(text: newTexts[i]) }
        }
        let paragraphs = result.compactMap { $0 }
        return paragraphs.isEmpty ? [Paragraph()] : paragraphs
    }
}
