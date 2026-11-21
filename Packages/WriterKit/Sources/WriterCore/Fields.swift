import Foundation

/// A kind of page, such as Character or Place, chosen by the author. Every
/// page of a type shares its fields, so adding a field to Character gives
/// every character that field (each with its own value).
public struct PageType: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var fields: [FieldDefinition]

    public init(id: UUID = UUID(), name: String, fields: [FieldDefinition] = []) {
        self.id = id
        self.name = name
        self.fields = fields
    }
}

public struct FieldDefinition: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case text, longText, number, date, choice, toggle
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// The choices, for `.choice`.
    public var options: [String]

    public init(id: UUID = UUID(), name: String, kind: Kind, options: [String] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.options = options
    }
}

public enum FieldValue: Codable, Hashable, Sendable {
    case text(String)
    case number(Double)
    case date(Date)
    case toggle(Bool)

    /// How the value reads, for search.
    public var display: String {
        switch self {
        case .text(let s): s
        case .number(let n): n.formatted()
        case .date(let d): d.formatted(date: .long, time: .omitted)
        case .toggle(let on): on ? "Yes" : "No"
        }
    }
}

/// The author's page types, saved beside the pages.
public final class TypeStore: @unchecked Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() -> [PageType] {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([PageType].self, from: $0) } ?? []
    }

    public func save(_ types: [PageType]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(types).write(to: url, options: [.atomic])
    }
}

extension Document {
    /// "Name: value" lines for the fields of `type` that have a value, for search.
    public func fieldText(_ type: PageType?) -> String {
        (type?.fields ?? []).compactMap { field in values[field.id].map { "\(field.name): \($0.display)" } }
            .joined(separator: "\n")
    }
}
