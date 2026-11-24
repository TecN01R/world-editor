import Foundation

/// A world (a project, a novel…): its own pages, types and fields.
public struct World: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    /// The name a world gets when it has none (the first, made from pages
    /// saved before worlds existed).
    public static let defaultName = "My World"
}

/// Worlds on disk, one folder each: `<root>/<id>/` holds `World.json`, the
/// pages in `Documents/` and the types and fields in `Schema.json`.
public final class WorldStore: @unchecked Sendable {
    public let root: URL

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func documents(_ id: UUID) -> URL { folder(id).appendingPathComponent("Documents", isDirectory: true) }
    public func schema(_ id: UUID) -> URL { folder(id).appendingPathComponent("Schema.json") }
    /// The companion's conversations, one per page.
    public func conversations(_ id: UUID) -> URL { folder(id).appendingPathComponent("Conversations", isDirectory: true) }
    private func info(_ id: UUID) -> URL { folder(id).appendingPathComponent("World.json") }

    /// Every world, by name. A folder whose `World.json` is missing (a move
    /// cut short) still counts, under the default name, so no pages are lost.
    public func all() -> [World] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { UUID(uuidString: $0.lastPathComponent) }
            .map { id in
                (try? Data(contentsOf: info(id))).flatMap { try? JSONDecoder().decode(World.self, from: $0) }
                    ?? World(id: id, name: World.defaultName)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func save(_ world: World) throws {
        try FileManager.default.createDirectory(at: documents(world.id), withIntermediateDirectories: true)
        try JSONEncoder().encode(world).write(to: info(world.id), options: [.atomic])
    }

    /// Deletes a world and everything in it.
    public func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: folder(id))
    }

    /// The world a page is saved in, if any.
    public func world(containing page: UUID) -> UUID? {
        all().first { FileManager.default.fileExists(atPath: documents($0.id).appendingPathComponent("\(page.uuidString).json").path) }?.id
    }

    /// How many pages a world holds, Recently Deleted included.
    public func pageCount(_ id: UUID) -> Int {
        ((try? FileManager.default.contentsOfDirectory(at: documents(id), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.count
    }

    /// Moves pages saved before worlds existed (a `documents` folder and a
    /// `schema` file) into a new world, and returns it; nil if there are none.
    /// The folders are renamed, not copied, so it's quick and can't leave two
    /// copies. Cut short, the next run finishes the same world (the one
    /// without its `World.json`), so pages and their types stay together.
    public func adoptLegacy(documents legacy: URL, schema legacySchema: URL) throws -> World? {
        let fm = FileManager.default
        let pagesLeft = fm.fileExists(atPath: legacy.path), schemaLeft = fm.fileExists(atPath: legacySchema.path)
        guard pagesLeft || schemaLeft else { return nil }
        let unfinished = all().first { !fm.fileExists(atPath: info($0.id).path) }
        let world = unfinished ?? World(name: World.defaultName)
        try fm.createDirectory(at: folder(world.id), withIntermediateDirectories: true)
        if pagesLeft { try fm.moveItem(at: legacy, to: documents(world.id)) }
        if schemaLeft { try fm.moveItem(at: legacySchema, to: schema(world.id)) }
        try save(world)
        return world
    }

    /// Deletes for good, in every world but `except`, the pages whose 30 days
    /// in Recently Deleted are up, and their conversations.
    public func removeExpired(except open: UUID?, now: Date = Date()) {
        for world in all() where world.id != open {
            guard let store = try? DocumentStore(directory: documents(world.id)) else { continue }
            let talk = try? ConversationStore(directory: conversations(world.id))
            for page in store.all() where page.goesForGood.map({ $0 <= now }) == true {
                try? store.delete(page.id)
                talk?.delete(page.id)
            }
        }
    }
}
