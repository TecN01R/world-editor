import Foundation

/// What the companion filed from one of the author's messages (types, fields,
/// values, new pages), kept on the turn so it can be shown and undone.
/// Filing happens on its own, with Undo (Kevin's ruling, 2026-11-23; see
/// docs/ai-charter.md). `Filer` (Guardrails) makes it.
public struct FilingRecord: Codable, Hashable, Sendable {
    public enum Entry: Codable, Hashable, Sendable {
        /// A page that had no type got this one.
        case typed(page: UUID, type: UUID)
        /// A new page, with its `modified` date then, to tell whether it was edited since.
        case created(page: UUID, modified: Date)
        /// An empty field got a value.
        case value(page: UUID, field: UUID, value: FieldValue)
        /// A field's value was corrected ("Actually it's a bireme"); `was` comes back on Undo.
        case replaced(page: UUID, field: UUID, was: FieldValue, value: FieldValue)
        /// The open page was renamed: the author named its subject ("Her name is Mara").
        case renamed(page: UUID, was: String, title: String)
        /// A page with no writing got the author's description of it as its text
        /// ("an island republic of glassblowers"; Kevin, 2026-11-24: "Put that in the page
        /// content, not the type").
        case described(page: UUID, text: String)
        case newType(UUID)
        case newField(UUID)
        /// An existing or new field added to a type.
        case fieldAdded(type: UUID, field: UUID)
    }

    public var entries: [Entry]
    /// The author took something filed here back.
    public private(set) var undid: Bool
    /// The open page's fields when the message was first read: reading it again
    /// (Try Again) may replace only a value still as it was then, never one the
    /// author has changed since.
    public var seen: [UUID: FieldValue]?
    /// The open page's title then: reading it again renames the page only if it's still that.
    public var seenTitle: String?
    /// When it was filed: Undo's newest first across conversations goes by this.
    public var date: Date?

    public init(entries: [Entry] = [], undid: Bool = false, seen: [UUID: FieldValue]? = nil, seenTitle: String? = nil) {
        self.entries = entries
        self.undid = undid
        self.seen = seen
        self.seenTitle = seenTitle
    }

    private enum CodingKeys: String, CodingKey { case entries, undid, seen, seenTitle, date }

    /// A record saved before `undid` existed counts as undone: an empty one can't tell
    /// "found nothing" from "all undone", and reading it again could bring back what the
    /// author took back.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decode([Entry].self, forKey: .entries)
        undid = try c.decodeIfPresent(Bool.self, forKey: .undid) ?? true
        seen = try c.decodeIfPresent([UUID: FieldValue].self, forKey: .seen)
        seenTitle = try c.decodeIfPresent(String.self, forKey: .seenTitle)
        date = try c.decodeIfPresent(Date.self, forKey: .date)
    }

    /// The things it did, each undone on its own: pages made, types given,
    /// fields filled or corrected. (New types and fields come with them.)
    public var actions: [Entry] {
        entries.filter {
            switch $0 {
            case .created, .typed, .value, .replaced, .renamed, .described: true
            case .newType, .newField, .fieldAdded: false
            }
        }
    }

    /// Nothing left to show or undo.
    public var isEmpty: Bool { actions.isEmpty }

    /// Its message gave nothing to file, and the author has undone nothing: reading it
    /// again can't bring back anything they took back.
    public var filedNothing: Bool { entries.isEmpty && !undid }

    /// Takes back one of its `actions`, except what the author has changed
    /// since: a value they changed again stays, and a type or field another page
    /// now uses stays. A new type or field nothing uses any more goes too.
    /// Undo goes newest first (`Conversation.changedLater`); a page it made takes
    /// with it what this same message filed on it or linked to it.
    /// - Parameters:
    ///   - kept: pages to keep rather than delete if this made them (the author has
    ///     talked about them in their own conversation).
    ///   - deleted: pages in Recently Deleted, which still count as using a type or field.
    /// - Returns: the page it made, if this action made it (gone from `pages`
    ///   unless `edited`: written on since, by the author or by filing from
    ///   another conversation, or `kept`; it goes to Recently Deleted instead).
    public mutating func undo(_ action: Entry, pages: inout [Document], schema: inout Schema,
                              kept: (UUID) -> Bool = { _ in false }, deleted: [Document] = []) -> (page: UUID, edited: Bool)? {
        guard let at = entries.firstIndex(of: action) else { return nil }
        entries.remove(at: at)
        undid = true
        func index(_ id: UUID) -> Int? { pages.firstIndex { $0.id == id } }
        var made: (page: UUID, edited: Bool)?
        switch action {
        case .value(let page, let field, let value):
            if let i = index(page), pages[i].values[field] == value { pages[i].values[field] = nil }
        case .replaced(let page, let field, let was, let value):
            if let i = index(page), pages[i].values[field] == value { pages[i].values[field] = was }
        case .typed(let page, let type):
            if let i = index(page), pages[i].type == type { pages[i].type = nil }
        case .renamed(let page, let was, let title):
            if let i = index(page), pages[i].title == title { pages[i].title = was }
        case .described(let page, let text):
            if let i = index(page), pages[i].paragraphs.map(\.text) == [text] { pages[i].fileDescription("") }
        case .created(let page, let modified):
            if let i = index(page) {
                // What this message filed on it, value by value: anything else, or a value
                // changed since (by hand, or corrected elsewhere), means it's been worked on.
                let mine = Dictionary(entries.compactMap { e in
                    e.page == page ? e.field.flatMap { f in e.value.map { (f, $0) } } : nil
                }, uniquingKeysWith: { $1 })
                made = (page, kept(page) || pages[i].modified != modified || pages[i].values.contains { mine[$0.key] != $0.value })
            }
        case .newType, .newField, .fieldAdded:
            return nil
        }
        if let gone = made.flatMap({ $0.edited ? nil : $0.page }) {
            // Links to it go with it, and so do their lines (and the lines of what was filed on
            // it); a link that replaced a value puts that value back.
            for case .replaced(let page, let field, let was, .page(gone)) in entries {
                if let i = index(page), pages[i].values[field] == .page(gone) { pages[i].values[field] = was }
            }
            for i in pages.indices { pages[i].values = pages[i].values.filter { $0.value != .page(gone) } }
            entries.removeAll { $0.page == gone || $0.linked == gone }
            pages.removeAll { $0.id == gone }
        }
        Self.tidy(entries, pages: pages + deleted, schema: &schema)
        return made
    }

    /// Takes the types and fields filing made (`entries`' `newType`, `newField` and
    /// `fieldAdded`) out of `schema` once no page uses them. Run over every record
    /// after an Undo: a type one message made may be last used by another's page.
    public static func tidy(_ entries: [Entry], pages: [Document], schema: inout Schema) {
        for entry in entries.reversed() {
            switch entry {
            case .fieldAdded(let type, let field):
                if !pages.contains(where: { $0.type == type && $0.values[field] != nil }),
                   let t = schema.types.firstIndex(where: { $0.id == type }) {
                    schema.types[t].fields.removeAll { $0 == field }
                }
            case .newField(let field):
                if !schema.types.contains(where: { $0.fields.contains(field) }),
                   !pages.contains(where: { $0.values[field] != nil }) {
                    schema.fields.removeAll { $0.id == field }
                }
            case .newType(let type):
                if !pages.contains(where: { $0.type == type }) { schema.removeType(type) }
            case .created, .typed, .value, .replaced, .renamed, .described:
                break
            }
        }
    }
}

extension FilingRecord.Entry {
    /// The page this made, typed or filled in.
    public var page: UUID? {
        switch self {
        case .created(let page, _), .typed(let page, _), .value(let page, _, _), .replaced(let page, _, _, _),
             .renamed(let page, _, _), .described(let page, _): page
        case .newType, .newField, .fieldAdded: nil
        }
    }

    /// The field it filled in.
    public var field: UUID? {
        switch self {
        case .value(_, let field, _), .replaced(_, let field, _, _): field
        default: nil
        }
    }

    /// The value it gave a field.
    public var value: FieldValue? {
        switch self {
        case .value(_, _, let value), .replaced(_, _, _, let value): value
        default: nil
        }
    }

    /// The value a correction replaced.
    public var was: FieldValue? {
        if case .replaced(_, _, let was, _) = self { was } else { nil }
    }

    /// The page its value links to.
    public var linked: UUID? {
        switch self {
        case .value(_, _, .page(let id)), .replaced(_, _, _, .page(let id)): id
        default: nil
        }
    }

    /// Whether `later`, filed after this, changed what this did: a later value in the
    /// same field, a later name for the page this renamed, a field filled on the page this
    /// typed (fields come with the type), or, from a later message, anything filed on,
    /// linked to, or corrected away from the page this made (from the same message, that
    /// goes with the page instead).
    public func isChanged(by later: Self, sameMessage: Bool) -> Bool {
        switch self {
        case .value(let page, let field, _), .replaced(let page, let field, _, _):
            later.page == page && later.field == field
        case .typed(let page, _):
            later.page == page && later.field != nil
        case .renamed(let page, _, _):
            if case .renamed(page, _, _) = later { true } else { false }
        case .described:
            false   // only a page with no writing is described, so nothing filed later changes it
        case .created(let page, _):
            !sameMessage && (later.page == page || later.linked == page || later.was == .page(page))
        case .newType, .newField, .fieldAdded:
            false
        }
    }
}
