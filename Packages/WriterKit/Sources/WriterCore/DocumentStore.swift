import Foundation

/// Stores documents as JSON files, one per document, in a directory the app
/// owns. Writes are atomic so a crash can never leave a half-written note.
public final class DocumentStore: @unchecked Sendable {
    public let directory: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .deferredToDate   // full precision; ISO 8601 drops fractions
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        return d
    }()

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    public func save(_ document: Document) throws {
        let data = try encoder.encode(document)
        try data.write(to: url(for: document.id), options: [.atomic])
    }

    public func load(_ id: UUID) throws -> Document {
        try decoder.decode(Document.self, from: Data(contentsOf: url(for: id)))
    }

    public func all() throws -> [Document] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Document.self, from: Data(contentsOf: $0)) }
            .sorted { $0.modified > $1.modified }
    }

    public func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: url(for: id))
    }
}
