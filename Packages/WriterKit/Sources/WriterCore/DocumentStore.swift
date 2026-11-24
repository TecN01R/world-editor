import Foundation

/// Stores documents as JSON files, one per document, in a directory the app
/// owns. Writes are atomic so a crash can never leave a half-written page.
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

    /// Every page this version can read, most recently changed first.
    public func all() -> [Document] { scan().pages }

    /// Every page, most recently changed first, and the files this version can't read
    /// (left as they are: nothing saves over them, since their pages never load).
    public func scan() -> (pages: [Document], unreadable: [URL]) {
        let found = SavedFile<Document>.all(in: directory, decoder: decoder)
        return (found.values.sorted { $0.modified > $1.modified }, found.unreadable)
    }

    public func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: url(for: id))
    }
}
