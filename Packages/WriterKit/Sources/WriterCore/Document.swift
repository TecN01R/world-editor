import Foundation

/// How a paragraph is presented: plain body text or an item in a list.
/// Numbers are not stored; a numbered item's number is its position in its
/// run of consecutive numbered paragraphs (`Document.listOrdinal(at:)`).
public enum ParagraphKind: String, Codable, Hashable, Sendable, CaseIterable {
    case body, bullet, numbered

    public var isList: Bool { self != .body }
}

/// Character-level emphasis.
public struct InlineStyle: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let bold = InlineStyle(rawValue: 1 << 0)
    public static let italic = InlineStyle(rawValue: 1 << 1)
}

/// A styled stretch of a paragraph. Offsets are UTF-16 units, the same units
/// TextKit and `NSRange` use, so the editors can apply them directly.
public struct StyleRun: Codable, Hashable, Sendable {
    public var location: Int
    public var length: Int
    public var style: InlineStyle

    public init(location: Int, length: Int, style: InlineStyle) {
        self.location = location
        self.length = length
        self.style = style
    }
}

/// A paragraph is the unit both editors share: page view shows them together,
/// focus mode shows one per page. Identity is stable across edits so that
/// extracted facts can point back at the paragraph they came from.
public struct Paragraph: Identifiable, Hashable, Sendable {
    public var id: UUID
    public private(set) var text: String
    public var kind: ParagraphKind
    /// Sorted, non-overlapping, non-empty runs; unstyled text has no run.
    public private(set) var runs: [StyleRun]

    public init(id: UUID = UUID(), text: String = "", kind: ParagraphKind = .body, runs: [StyleRun] = []) {
        self.id = id
        self.text = text
        self.kind = kind
        self.runs = []
        setText(text, runs: runs)
    }

    public var length: Int { text.utf16.count }

    /// Replaces the text and its styling together; runs are clamped and merged.
    public mutating func setText(_ text: String, runs: [StyleRun] = []) {
        self.text = text
        var styles = [InlineStyle](repeating: [], count: text.utf16.count)
        for run in runs {
            let lo = max(0, run.location), hi = min(styles.count, run.location + run.length)
            if lo < hi { for i in lo..<hi { styles[i].formUnion(run.style) } }
        }
        self.runs = Self.runs(from: styles)
    }

    /// One style per UTF-16 unit.
    public var styles: [InlineStyle] {
        var styles = [InlineStyle](repeating: [], count: length)
        for run in runs { for i in run.location..<(run.location + run.length) { styles[i] = run.style } }
        return styles
    }

    /// The style new typing at `offset` continues: that of the character before it.
    public func style(at offset: Int) -> InlineStyle {
        let s = styles
        return offset > 0 && offset <= s.count ? s[offset - 1] : (s.first ?? [])
    }

    /// Replaces a UTF-16 range with `string`, which takes on `style`.
    public mutating func replace(_ range: Range<Int>, with string: String, style: InlineStyle) {
        var units = Array(text.utf16), styles = self.styles
        let lo = max(0, min(range.lowerBound, units.count)), hi = max(lo, min(range.upperBound, units.count))
        let inserted = Array(string.utf16)
        units.replaceSubrange(lo..<hi, with: inserted)
        styles.replaceSubrange(lo..<hi, with: Array(repeating: style, count: inserted.count))
        text = String(decoding: units, as: UTF16.self)
        runs = Self.runs(from: styles)
    }

    /// Sets or clears `style` over a UTF-16 range.
    public mutating func set(_ style: InlineStyle, _ on: Bool, in range: Range<Int>) {
        var styles = self.styles
        for i in range.clamped(to: 0..<styles.count) {
            if on { styles[i].formUnion(style) } else { styles[i].subtract(style) }
        }
        runs = Self.runs(from: styles)
    }

    /// The text and styling from `range`, as a new paragraph of the same kind.
    func slice(_ range: Range<Int>, id: UUID = UUID()) -> Paragraph {
        let units = Array(text.utf16), styles = self.styles
        let r = range.clamped(to: 0..<units.count)
        return Paragraph(id: id, text: String(decoding: units[r], as: UTF16.self), kind: kind,
                         runs: Self.runs(from: Array(styles[r])))
    }

    static func runs(from styles: [InlineStyle]) -> [StyleRun] {
        var runs: [StyleRun] = []
        for (i, style) in styles.enumerated() where !style.isEmpty {
            if let last = runs.last, last.style == style, last.location + last.length == i {
                runs[runs.count - 1].length += 1
            } else {
                runs.append(StyleRun(location: i, length: 1, style: style))
            }
        }
        return runs
    }
}

extension Paragraph: Codable {
    private enum CodingKeys: String, CodingKey { case id, text, kind, runs }

    // Older notes have only id and text; plain paragraphs are written that way too.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  text: try c.decode(String.self, forKey: .text),
                  kind: try c.decodeIfPresent(ParagraphKind.self, forKey: .kind) ?? .body,
                  runs: try c.decodeIfPresent([StyleRun].self, forKey: .runs) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        if kind != .body { try c.encode(kind, forKey: .kind) }
        if !runs.isEmpty { try c.encode(runs, forKey: .runs) }
    }
}

/// The user's writing. Only the user's own edits change it: nothing in the AI
/// layers holds a mutable reference to a `Document`.
///
/// Offsets are UTF-16 units. A position in the whole document counts each
/// paragraph's text plus one for the line break between paragraphs, matching
/// the text page view shows.
public struct Document: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// Separate from the writing, shown above it in Edit mode.
    public var title: String
    public private(set) var paragraphs: [Paragraph]
    public var modified: Date

    public init(id: UUID = UUID(), title: String = "", paragraphs: [Paragraph] = [Paragraph()], modified: Date = Date()) {
        self.id = id
        self.title = title
        self.paragraphs = paragraphs.isEmpty ? [Paragraph()] : paragraphs
        self.modified = modified
    }

    /// Plain text with one paragraph per line; what page view shows.
    public var plainText: String { paragraphs.map(\.text).joined(separator: "\n") }

    public var isEmpty: Bool {
        title.allSatisfy(\.isWhitespace) && paragraphs.allSatisfy { $0.text.allSatisfy(\.isWhitespace) }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }

    /// The page's name in the pages list: its title, or its first line until it has one.
    public var heading: String {
        let name = trimmedTitle.isEmpty ? nonEmptyLines.first : trimmedTitle
        return name.map { String($0.prefix(80)) } ?? ""
    }

    /// The first line of writing not already used as the heading.
    public var preview: String {
        let lines = trimmedTitle.isEmpty ? nonEmptyLines.dropFirst() : nonEmptyLines[...]
        return lines.first.map { String($0.prefix(120)) } ?? ""
    }

    private var nonEmptyLines: [String] {
        paragraphs.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public var wordCount: Int {
        paragraphs.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    public func paragraph(_ id: UUID) -> Paragraph? { paragraphs.first { $0.id == id } }
    public func index(of id: UUID) -> Int? { paragraphs.firstIndex { $0.id == id } }

    /// Position of each paragraph's first character in the whole document.
    public var paragraphStarts: [Int] {
        var starts: [Int] = [], at = 0
        for p in paragraphs { starts.append(at); at += p.length + 1 }
        return starts
    }

    /// The paragraph holding document position `location`, and the offset in it.
    public func locate(_ location: Int) -> (index: Int, offset: Int) {
        let starts = paragraphStarts
        let i = starts.lastIndex { $0 <= location } ?? 0
        return (i, max(0, min(location - starts[i], paragraphs[i].length)))
    }

    /// 1-based number of a numbered item within its run of numbered paragraphs.
    public func listOrdinal(at index: Int) -> Int? {
        guard paragraphs.indices.contains(index), paragraphs[index].kind == .numbered else { return nil }
        var n = 1, i = index - 1
        while i >= 0, paragraphs[i].kind == .numbered { n += 1; i -= 1 }
        return n
    }

    // MARK: Editing (user-initiated only)

    public mutating func setTitle(_ title: String) {
        self.title = title
        modified = Date()
    }

    /// Replaces the whole content (page view). Paragraph identities are kept for
    /// paragraphs whose text is unchanged or edited in place, so provenance
    /// survives ordinary editing.
    public mutating func setParagraphs(_ new: [Paragraph]) {
        paragraphs = ParagraphDiff.reconcile(old: paragraphs, new: new)
        modified = Date()
    }

    /// Replaces the whole text with unstyled body paragraphs, one per line.
    public mutating func setPlainText(_ text: String) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        setParagraphs(lines.map { Paragraph(text: $0) })
    }

    /// Replaces one paragraph's text and styling, keeping its identity and kind.
    public mutating func setText(_ text: String, runs: [StyleRun] = [], at index: Int) {
        guard paragraphs.indices.contains(index) else { return }
        paragraphs[index].setText(text, runs: runs)
        modified = Date()
    }

    /// Split paragraph `index` at `offset` (Return). The new paragraph continues
    /// a list, like Notes. Returns the new paragraph's index.
    @discardableResult
    public mutating func split(at index: Int, offset: Int) -> Int {
        guard paragraphs.indices.contains(index) else { return index }
        let p = paragraphs[index]
        let cut = max(0, min(offset, p.length))
        paragraphs[index] = p.slice(0..<cut, id: p.id)
        paragraphs.insert(p.slice(cut..<p.length), at: index + 1)
        modified = Date()
        return index + 1
    }

    /// Join paragraph `index` onto the previous one (Backspace at start), which
    /// keeps its kind. Returns the caret offset in the merged paragraph, or nil
    /// if there is nothing to merge.
    @discardableResult
    public mutating func mergeWithPrevious(_ index: Int) -> Int? {
        guard index > 0, paragraphs.indices.contains(index) else { return nil }
        let first = paragraphs[index - 1], second = paragraphs[index]
        let joinAt = first.length
        let moved = second.runs.map { StyleRun(location: $0.location + joinAt, length: $0.length, style: $0.style) }
        paragraphs[index - 1].setText(first.text + second.text, runs: first.runs + moved)
        paragraphs.remove(at: index)
        modified = Date()
        return joinAt
    }

    /// Types `string` over `range` of paragraph `index`; line breaks in it
    /// split the paragraph. The new text continues the style before it.
    /// Returns where the caret ends up.
    @discardableResult
    public mutating func replace(_ range: Range<Int>, in index: Int, with string: String) -> (index: Int, offset: Int) {
        guard paragraphs.indices.contains(index) else { return (index, 0) }
        let normalized = string.replacingOccurrences(of: "\r\n", with: "\n")
        let style = paragraphs[index].style(at: range.lowerBound)
        paragraphs[index].replace(range, with: normalized, style: style)
        var at = index
        while let nl = Array(paragraphs[at].text.utf16).firstIndex(of: 0x0A) {
            at = split(at: at, offset: nl)
            paragraphs[at].replace(0..<1, with: "", style: [])   // drop the line break itself
        }
        let lines = normalized.components(separatedBy: "\n")
        let offset = (lines.count == 1 ? range.lowerBound : 0) + lines.last!.utf16.count
        modified = Date()
        return (at, offset)
    }

    // MARK: Formatting a selection (document positions)

    /// Whether every character in `range` has `style`. An empty range has none.
    public func has(_ style: InlineStyle, in range: Range<Int>) -> Bool {
        var any = false
        for (i, local) in localRanges(range) {
            let styles = paragraphs[i].styles
            for k in local {
                any = true
                if !styles[k].contains(style) { return false }
            }
        }
        return any
    }

    /// Bold/Italic button: removes `style` if the whole selection has it, otherwise adds it.
    public mutating func toggle(_ style: InlineStyle, in range: Range<Int>) {
        let on = !has(style, in: range)
        for (i, local) in localRanges(range) { paragraphs[i].set(style, on, in: local) }
        modified = Date()
    }

    /// List buttons: every paragraph the selection touches becomes `kind`, or
    /// body text again if they all already were.
    public mutating func toggleKind(_ kind: ParagraphKind, in range: Range<Int>) {
        let touched = paragraphIndices(range)
        let target: ParagraphKind = touched.allSatisfy { paragraphs[$0].kind == kind } ? .body : kind
        for i in touched { paragraphs[i].kind = target }
        modified = Date()
    }

    public func paragraphIndices(_ range: Range<Int>) -> ClosedRange<Int> {
        locate(range.lowerBound).index...locate(range.upperBound).index
    }

    private func localRanges(_ range: Range<Int>) -> [(Int, Range<Int>)] {
        let starts = paragraphStarts
        return paragraphIndices(range).compactMap { i in
            let lo = max(range.lowerBound - starts[i], 0)
            let hi = min(range.upperBound - starts[i], paragraphs[i].length)
            return lo < hi ? (i, lo..<hi) : nil
        }
    }
}

/// Keeps paragraph IDs stable when page view replaces the whole content.
enum ParagraphDiff {
    static func reconcile(old: [Paragraph], new: [Paragraph]) -> [Paragraph] {
        // Match unchanged paragraphs first (in order), then reuse the remaining
        // old IDs positionally for edited paragraphs.
        var used = Set<Int>()
        var ids: [UUID?] = Array(repeating: nil, count: new.count)
        var searchFrom = 0
        for (i, p) in new.enumerated() {
            if let j = old[searchFrom...].firstIndex(where: { $0.text == p.text }), !used.contains(j) {
                ids[i] = old[j].id
                used.insert(j)
                searchFrom = j + 1
            }
        }
        var spare = old.indices.filter { !used.contains($0) }.makeIterator()
        let result = new.enumerated().map { i, p -> Paragraph in
            var p = p
            p.id = ids[i] ?? spare.next().map { old[$0].id } ?? UUID()
            return p
        }
        return result.isEmpty ? [Paragraph()] : result
    }
}
