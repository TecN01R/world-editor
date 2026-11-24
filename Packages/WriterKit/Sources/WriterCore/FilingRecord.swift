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
        case newType(UUID)
        case newField(UUID)
        /// An existing or new field added to a type.
        case fieldAdded(type: UUID, field: UUID)
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) { self.entries = entries }

    /// The things it did, each undone on its own: pages made, types given,
    /// fields filled or corrected. (New types and fields come with them.)
    public var actions: [Entry] {
        entries.filter {
            switch $0 {
            case .created, .typed, .value, .replaced: true
            case .newType, .newField, .fieldAdded: false
            }
        }
    }

    /// Nothing left to show or undo.
    public var isEmpty: Bool { actions.isEmpty }

    /// Takes back one of its `actions`, except what the author has changed
    /// since: a value they changed again stays, and a type or field another page
    /// now uses stays. A new type or field nothing uses any more goes too.
    /// - Returns: the page it made, if this action made it (gone from `pages`
    ///   unless `edited`: the author wrote on it since, so it's theirs to delete).
    public mutating func undo(_ action: Entry, pages: inout [Document], schema: inout Schema)
        -> (page: UUID, edited: Bool)? {
        guard let at = entries.firstIndex(of: action) else { return nil }
        entries.remove(at: at)
        func index(_ id: UUID) -> Int? { pages.firstIndex { $0.id == id } }
        var made: (page: UUID, edited: Bool)?
        switch action {
        case .value(let page, let field, let value):
            if let i = index(page), pages[i].values[field] == value { pages[i].values[field] = nil }
        case .replaced(let page, let field, let was, let value):
            if let i = index(page), pages[i].values[field] == value { pages[i].values[field] = was }
        case .typed(let page, let type):
            if let i = index(page), pages[i].type == type { pages[i].type = nil }
        case .created(let page, let modified):
            if let i = index(page) { made = (page, pages[i].modified != modified) }
        case .newType, .newField, .fieldAdded:
            return nil
        }
        // Whether the rest is still used, with the page made gone (unless it's kept).
        let gone = made.flatMap { $0.edited ? nil : $0.page }
        let live = pages.filter { $0.id != gone }
        for entry in entries.reversed() {
            switch entry {
            case .fieldAdded(let type, let field):
                if !live.contains(where: { $0.type == type && $0.values[field] != nil }),
                   let t = schema.types.firstIndex(where: { $0.id == type }) {
                    schema.types[t].fields.removeAll { $0 == field }
                }
            case .newField(let field):
                if !schema.types.contains(where: { $0.fields.contains(field) }),
                   !live.contains(where: { $0.values[field] != nil }) {
                    schema.fields.removeAll { $0.id == field }
                }
            case .newType(let type):
                if !live.contains(where: { $0.type == type }) { schema.removeType(type) }
            case .created, .typed, .value, .replaced:
                break
            }
        }
        if let gone {
            // Links to it go with it, and so do their lines; a link that replaced a value puts it back.
            for case .replaced(let page, let field, let was, .page(gone)) in entries {
                if let i = index(page), pages[i].values[field] == .page(gone) { pages[i].values[field] = was }
            }
            for i in pages.indices { pages[i].values = pages[i].values.filter { $0.value != .page(gone) } }
            entries.removeAll {
                switch $0 {
                case .value(_, _, .page(gone)), .replaced(_, _, _, .page(gone)): true
                default: false
                }
            }
            pages.removeAll { $0.id == gone }
        }
        return made
    }
}
