import Foundation

/// A kind of page, such as Character or Place, chosen by the author. Every
/// page of a type shares its fields, so adding a field to Character gives
/// every character that field (each with its own value).
public struct PageType: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Its fields, in order: ids into the shared `Schema.fields`.
    public var fields: [UUID]

    public init(id: UUID = UUID(), name: String, fields: [UUID] = []) {
        self.id = id
        self.name = name
        self.fields = fields
    }
}

/// A field, shared: types pick fields from one list, so "Species" is defined
/// once (with its choices) and used by Character and Creature alike.
public struct FieldDefinition: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case text, longText, number, date, choice, toggle, page
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// The choices, for `.choice`.
    public var options: [String]
    /// For `.page`: only pages of this type are offered (any page when nil).
    public var pageType: UUID?

    public init(id: UUID = UUID(), name: String, kind: Kind, options: [String] = [], pageType: UUID? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.options = options
        self.pageType = pageType
    }
}

/// The author's shared fields and the types built from them.
public struct Schema: Codable, Hashable, Sendable {
    public var fields: [FieldDefinition]
    public var types: [PageType]

    public init(fields: [FieldDefinition] = [], types: [PageType] = []) {
        self.fields = fields
        self.types = types
    }

    public func type(_ id: UUID?) -> PageType? { id.flatMap { id in types.first { $0.id == id } } }

    /// The type's fields, in its order.
    public func fields(of type: PageType?) -> [FieldDefinition] {
        (type?.fields ?? []).compactMap { id in fields.first { $0.id == id } }
    }
}

public enum FieldValue: Codable, Hashable, Sendable {
    case text(String)
    case number(Double)
    case date(Date)
    case toggle(Bool)
    /// A link to another page, by id, so it follows renames.
    case page(UUID)

    /// How the value reads, for search; `pageName` gives a linked page's name.
    public func display(pageName: (UUID) -> String?) -> String? {
        switch self {
        case .text(let s): s
        case .number(let n): n.formatted()
        case .date(let d): d.formatted(date: .long, time: .omitted)
        case .toggle(let on): on ? "Yes" : "No"
        case .page(let id): pageName(id)
        }
    }
}

/// The author's fields and types, saved beside the pages.
public final class SchemaStore: @unchecked Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() -> Schema {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Schema.self, from: $0) } ?? Schema()
    }

    public func save(_ schema: Schema) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(schema).write(to: url, options: [.atomic])
    }
}

extension Document {
    /// "Name: value" lines for `fields` that have a value, for search.
    public func fieldText(_ fields: [FieldDefinition], pageName: (UUID) -> String?) -> String {
        fields.compactMap { field in
            values[field.id]?.display(pageName: pageName).map { "\(field.name): \($0)" }
        }
        .joined(separator: "\n")
    }
}
