import Foundation

/// How a paragraph is presented: plain body text or an item in a list.
/// Numbers are not stored; a numbered item's number is its position in its
/// run of consecutive numbered paragraphs (TextKit's `NSTextList` counts them).
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

/// An `@` link: a stretch of a paragraph that points at another page.
/// Offsets are UTF-16 units, like `StyleRun`.
public struct PageLink: Codable, Hashable, Sendable {
    public var location: Int
    public var length: Int
    public var page: UUID

    public init(location: Int, length: Int, page: UUID) {
        self.location = location
        self.length = length
        self.page = page
    }
}

/// A stretch of a paragraph the companion placed there from one of the author's
/// messages (`Placement`): their words, marked so they can see what was placed and
/// take it back. Offsets are UTF-16 units, like `StyleRun`. What they type is never
/// marked, so typing inside placed words makes those letters plainly theirs.
public struct PlacedRun: Codable, Hashable, Sendable {
    public var location: Int
    public var length: Int
    /// The `Placement` it came from.
    public var placement: UUID

    public init(location: Int, length: Int, placement: UUID) {
        self.location = location
        self.length = length
        self.placement = placement
    }
}

/// A paragraph is the unit both editors share: Edit mode shows them together,
/// Focus mode shows one per page. Identity is stable across edits so that
/// extracted facts can point back at the paragraph they came from.
public struct Paragraph: Identifiable, Hashable, Sendable {
    public var id: UUID
    public private(set) var text: String
    public var kind: ParagraphKind
    /// Sorted, non-overlapping, non-empty runs; unstyled text has no run.
    public private(set) var runs: [StyleRun]
    /// Sorted, non-overlapping `@` links.
    public private(set) var links: [PageLink]
    /// Sorted, non-overlapping stretches placed from the author's messages.
    public private(set) var placed: [PlacedRun]

    public init(id: UUID = UUID(), text: String = "", kind: ParagraphKind = .body,
                runs: [StyleRun] = [], links: [PageLink] = [], placed: [PlacedRun] = []) {
        self.id = id
        self.text = text
        self.kind = kind
        self.runs = []
        self.links = []
        self.placed = []
        setText(text, runs: runs, links: links, placed: placed)
    }

    public var length: Int { text.utf16.count }

    /// Replaces the text with its styling, links and placed stretches, each clamped and merged.
    public mutating func setText(_ text: String, runs: [StyleRun] = [], links: [PageLink] = [], placed: [PlacedRun] = []) {
        self.text = text
        let count = text.utf16.count
        var styles = [InlineStyle](repeating: [], count: count)
        for run in runs {
            let lo = max(0, run.location), hi = min(count, run.location + run.length)
            if lo < hi { for i in lo..<hi { styles[i].formUnion(run.style) } }
        }
        var targets = [UUID?](repeating: nil, count: count)
        for link in links {
            let lo = max(0, link.location), hi = min(count, link.location + link.length)
            if lo < hi { for i in lo..<hi { targets[i] = link.page } }
        }
        var sources = [UUID?](repeating: nil, count: count)
        for run in placed {
            let lo = max(0, run.location), hi = min(count, run.location + run.length)
            if lo < hi { for i in lo..<hi { sources[i] = run.placement } }
        }
        self.runs = Self.runs(from: styles)
        self.links = Self.links(from: targets)
        self.placed = Self.placed(from: sources)
    }

    /// The page linked at each UTF-16 unit.
    var targets: [UUID?] {
        var targets = [UUID?](repeating: nil, count: length)
        for link in links { for i in link.location..<(link.location + link.length) { targets[i] = link.page } }
        return targets
    }

    /// The placement each UTF-16 unit came from.
    var sources: [UUID?] {
        var sources = [UUID?](repeating: nil, count: length)
        for run in placed { for i in run.location..<(run.location + run.length) { sources[i] = run.placement } }
        return sources
    }

    /// The link around `offset`, if the caret is inside one or just after it.
    public func link(at offset: Int) -> PageLink? {
        links.first { $0.location < offset && offset <= $0.location + $0.length }
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

    /// Replaces a UTF-16 range with `string`, which takes on `style`. Typed
    /// text never extends a link, and is never marked as placed.
    public mutating func replace(_ range: Range<Int>, with string: String, style: InlineStyle) {
        var units = Array(text.utf16), styles = self.styles, targets = self.targets, sources = self.sources
        let lo = max(0, min(range.lowerBound, units.count)), hi = max(lo, min(range.upperBound, units.count))
        let inserted = Array(string.utf16)
        units.replaceSubrange(lo..<hi, with: inserted)
        styles.replaceSubrange(lo..<hi, with: Array(repeating: style, count: inserted.count))
        targets.replaceSubrange(lo..<hi, with: Array(repeating: nil, count: inserted.count))
        sources.replaceSubrange(lo..<hi, with: Array(repeating: nil, count: inserted.count))
        text = String(decoding: units, as: UTF16.self)
        runs = Self.runs(from: styles)
        links = Self.links(from: targets)
        placed = Self.placed(from: sources)
    }

    /// Sets or clears `style` over a UTF-16 range.
    public mutating func set(_ style: InlineStyle, _ on: Bool, in range: Range<Int>) {
        var styles = self.styles
        for i in range.clamped(to: 0..<styles.count) {
            if on { styles[i].formUnion(style) } else { styles[i].subtract(style) }
        }
        runs = Self.runs(from: styles)
    }

    /// Rewrites the text of every link to `page` as `title`, keeping each
    /// link's styling. Returns whether anything changed.
    @discardableResult
    public mutating func retitleLinks(to page: UUID, as title: String) -> Bool {
        var units = Array(text.utf16), styles = self.styles, targets = self.targets, sources = self.sources
        let new = Array(title.utf16)
        var changed = false
        for link in links.reversed() where link.page == page {
            let r = link.location..<(link.location + link.length)
            guard Array(units[r]) != new else { continue }
            units.replaceSubrange(r, with: new)
            styles.replaceSubrange(r, with: Array(repeating: styles[link.location], count: new.count))
            targets.replaceSubrange(r, with: Array(repeating: page, count: new.count))
            sources.replaceSubrange(r, with: Array(repeating: sources[link.location], count: new.count))
            changed = true
        }
        guard changed else { return false }
        text = String(decoding: units, as: UTF16.self)
        runs = Self.runs(from: styles)
        links = Self.links(from: targets)
        placed = Self.placed(from: sources)
        return true
    }

    /// The text, styling, links and placed stretches from `range`, as a new paragraph of the same kind.
    func slice(_ range: Range<Int>, id: UUID = UUID()) -> Paragraph {
        let units = Array(text.utf16), styles = self.styles, targets = self.targets, sources = self.sources
        let r = range.clamped(to: 0..<units.count)
        return Paragraph(id: id, text: String(decoding: units[r], as: UTF16.self), kind: kind,
                         runs: Self.runs(from: Array(styles[r])), links: Self.links(from: Array(targets[r])),
                         placed: Self.placed(from: Array(sources[r])))
    }

    static func links(from targets: [UUID?]) -> [PageLink] {
        var links: [PageLink] = []
        for (i, target) in targets.enumerated() {
            guard let target else { continue }
            if let last = links.last, last.page == target, last.location + last.length == i {
                links[links.count - 1].length += 1
            } else {
                links.append(PageLink(location: i, length: 1, page: target))
            }
        }
        return links
    }

    static func placed(from sources: [UUID?]) -> [PlacedRun] {
        var placed: [PlacedRun] = []
        for (i, source) in sources.enumerated() {
            guard let source else { continue }
            if let last = placed.last, last.placement == source, last.location + last.length == i {
                placed[placed.count - 1].length += 1
            } else {
                placed.append(PlacedRun(location: i, length: 1, placement: source))
            }
        }
        return placed
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
    private enum CodingKeys: String, CodingKey { case id, text, kind, runs, links, placed }

    // Older pages have only id and text; plain paragraphs are written that way too.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  text: try c.decode(String.self, forKey: .text),
                  kind: try c.decodeIfPresent(ParagraphKind.self, forKey: .kind) ?? .body,
                  runs: try c.decodeIfPresent([StyleRun].self, forKey: .runs) ?? [],
                  links: try c.decodeIfPresent([PageLink].self, forKey: .links) ?? [],
                  placed: try c.decodeIfPresent([PlacedRun].self, forKey: .placed) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        if kind != .body { try c.encode(kind, forKey: .kind) }
        if !runs.isEmpty { try c.encode(runs, forKey: .runs) }
        if !links.isEmpty { try c.encode(links, forKey: .links) }
        if !placed.isEmpty { try c.encode(placed, forKey: .placed) }
    }
}

/// The user's writing. Only the user's own edits change it: nothing in the AI
/// layers holds a mutable reference to a `Document`.
///
/// Offsets are UTF-16 units. A position in the whole document counts each
/// paragraph's text plus one for the line break between paragraphs, matching
/// the text Edit mode shows.
public struct Document: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// Separate from the writing, shown above it in Edit mode.
    public var title: String
    public private(set) var paragraphs: [Paragraph]
    public var modified: Date
    /// The page's type (Character, Place…), whose fields it has; nil for a plain page.
    public var type: UUID?
    /// Field values by field id. A value outlives its field being removed
    /// from the type; it just isn't shown.
    public var values: [UUID: FieldValue]
    /// When it was deleted, while it waits in Recently Deleted; nil otherwise.
    public var deleted: Date?

    public init(id: UUID = UUID(), title: String = "", paragraphs: [Paragraph] = [Paragraph()], modified: Date = Date(),
                type: UUID? = nil, values: [UUID: FieldValue] = [:]) {
        self.id = id
        self.title = title
        self.paragraphs = paragraphs.isEmpty ? [Paragraph()] : paragraphs
        self.modified = modified
        self.type = type
        self.values = values
    }

    private enum CodingKeys: String, CodingKey { case id, title, paragraphs, modified, type, values, deleted }

    /// Pages saved before types existed have no `type` or `values`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let values = try c.decodeIfPresent([String: FieldValue].self, forKey: .values) ?? [:]
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                  paragraphs: try c.decode([Paragraph].self, forKey: .paragraphs),
                  modified: try c.decode(Date.self, forKey: .modified),
                  type: try c.decodeIfPresent(UUID.self, forKey: .type),
                  values: Dictionary(values.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } }) { first, _ in first })
        deleted = try c.decodeIfPresent(Date.self, forKey: .deleted)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(paragraphs, forKey: .paragraphs)
        try c.encode(modified, forKey: .modified)
        try c.encodeIfPresent(type, forKey: .type)
        if !values.isEmpty {
            try c.encode(Dictionary(uniqueKeysWithValues: values.map { ($0.key.uuidString, $0.value) }), forKey: .values)
        }
        try c.encodeIfPresent(deleted, forKey: .deleted)
    }

    /// How long a deleted page waits in Recently Deleted, as in Notes.
    public static let keptAfterDeleting: TimeInterval = 30 * 86_400

    /// When a deleted page goes for good; nil if it isn't deleted.
    public var goesForGood: Date? { deleted?.addingTimeInterval(Self.keptAfterDeleting) }

    /// Whole days left in Recently Deleted (at least 1 until it goes).
    public func daysLeft(now: Date = Date()) -> Int? {
        goesForGood.map { max(0, Int(($0.timeIntervalSince(now) / 86_400).rounded(.up))) }
    }

    /// Nothing on it: no title, no writing, no type and no field values. Leaving an empty
    /// page discards it, so a page with only a type or fields filled in isn't empty.
    public var isEmpty: Bool {
        title.allSatisfy(\.isWhitespace) && paragraphs.allSatisfy { $0.text.allSatisfy(\.isWhitespace) }
            && type == nil && values.isEmpty
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }

    /// The page's name in the pages list: its title, or its first line until it has one.
    public var heading: String {
        let name = trimmedTitle.isEmpty ? nonEmptyLines.first : trimmedTitle
        return name.map { String($0.prefix(80)) } ?? ""
    }

    /// What a page with no name is called, wherever it's named.
    public static let untitled = "Untitled"

    /// The page's name wherever it's shown: its heading, or "Untitled" until it has one.
    public var displayName: String { heading.isEmpty ? Self.untitled : heading }

    /// The page's title at the top of the page itself, where it is read: all of it, however long,
    /// as the editor shows it (`heading` stops at 80 characters, for rows and links). Until it
    /// has a title, `displayName`.
    public var displayTitle: String { trimmedTitle.isEmpty ? displayName : trimmedTitle }

    /// The first line of writing not already used as the heading.
    public var preview: String {
        let lines = trimmedTitle.isEmpty ? nonEmptyLines.dropFirst() : nonEmptyLines[...]
        return lines.first.map { String($0.prefix(120)) } ?? ""
    }

    private var nonEmptyLines: [String] {
        paragraphs.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public func paragraph(_ id: UUID) -> Paragraph? { paragraphs.first { $0.id == id } }

    /// Rewrites links to `page` as its new `title` (renaming a page renames its links).
    @discardableResult
    public mutating func retitleLinks(to page: UUID, as title: String) -> Bool {
        guard !title.isEmpty else { return false }
        var changed = false
        for i in paragraphs.indices where paragraphs[i].retitleLinks(to: page, as: title) { changed = true }
        return changed   // not an edit of this page, so `modified` stays
    }

    /// Takes back the description filing once gave the page (`FilingRecord.Entry.described`),
    /// if its writing still begins with it as given; what was written or placed after it
    /// stays. Filing's doing, not the author's edit, so `modified` stays.
    public mutating func takeBackDescription(_ text: String) {
        guard paragraphs.first?.text == text else { return }
        paragraphs.removeFirst()
        if paragraphs.isEmpty { paragraphs = [Paragraph()] }
    }

    /// Whether any `@` link or page field on this page points at `page` (backlinks).
    public func mentions(_ page: UUID) -> Bool {
        paragraphs.contains { $0.links.contains { $0.page == page } } || values.values.contains(.page(page))
    }

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

    // MARK: Editing (user-initiated only)

    public mutating func setTitle(_ title: String) {
        self.title = title
        modified = Date()
    }

    /// Replaces the whole content (Edit mode). Paragraph identities are kept for
    /// paragraphs whose text is unchanged or edited in place, so provenance
    /// survives ordinary editing.
    public mutating func setParagraphs(_ new: [Paragraph]) {
        paragraphs = ParagraphDiff.reconcile(old: paragraphs, new: new)
        modified = Date()
    }

    /// Replaces the whole content with `new` as it is, identities included (placing the
    /// author's words and taking them back know which paragraphs are which). Filing's doing,
    /// not the author's edit, so `modified` stays.
    mutating func setParagraphsAsIs(_ new: [Paragraph]) {
        paragraphs = new.isEmpty ? [Paragraph()] : new
    }

    /// Replaces one paragraph's text, styling, links and placed stretches, keeping its identity and kind.
    public mutating func setText(_ text: String, runs: [StyleRun] = [], links: [PageLink] = [], placed: [PlacedRun] = [],
                                 at index: Int) {
        guard paragraphs.indices.contains(index) else { return }
        paragraphs[index].setText(text, runs: runs, links: links, placed: placed)
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
        let runs = second.runs.map { StyleRun(location: $0.location + joinAt, length: $0.length, style: $0.style) }
        let links = second.links.map { PageLink(location: $0.location + joinAt, length: $0.length, page: $0.page) }
        let placed = second.placed.map { PlacedRun(location: $0.location + joinAt, length: $0.length, placement: $0.placement) }
        paragraphs[index - 1].setText(first.text + second.text, runs: first.runs + runs, links: first.links + links,
                                      placed: first.placed + placed)
        paragraphs.remove(at: index)
        modified = Date()
        return joinAt
    }

    /// `text` with every kind of line break ("\r\n", "\r", U+2028, U+2029…) as "\n",
    /// the one paragraphs split on, as pasted text may have any of them.
    public static func plainLineBreaks(_ text: String) -> String {
        String(text.map { $0.isNewline ? "\n" : $0 })
    }

    /// Types `string` over `range` of paragraph `index`; line breaks in it
    /// split the paragraph. The new text continues the style before it.
    /// Returns where the caret ends up.
    @discardableResult
    public mutating func replace(_ range: Range<Int>, in index: Int, with string: String) -> (index: Int, offset: Int) {
        guard paragraphs.indices.contains(index) else { return (index, 0) }
        let normalized = Self.plainLineBreaks(string)
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
        // A selection ending just past a line break (as selecting whole lines does)
        // leaves the next paragraph alone.
        let touched = paragraphIndices(range.isEmpty ? range : range.lowerBound..<(range.upperBound - 1))
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

/// Keeps paragraph IDs stable when Edit mode replaces the whole content.
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
