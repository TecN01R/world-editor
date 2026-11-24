import XCTest
@testable import WriterCore

final class WorldStoreTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("worlds-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    func testSavesListsAndDeletesWorlds() throws {
        let store = try WorldStore(root: base.appendingPathComponent("Worlds"))
        let b = World(name: "Breakwater"), a = World(name: "Archipelago")
        try store.save(b)
        try store.save(a)
        XCTAssertEqual(store.all(), [a, b])                   // by name
        try store.delete(a.id)
        XCTAssertEqual(store.all(), [b])
    }

    func testFindsTheWorldAPageIsIn() throws {
        let store = try WorldStore(root: base.appendingPathComponent("Worlds"))
        let world = World(name: "Breakwater")
        try store.save(world)
        let page = Document(title: "Mara")
        try DocumentStore(directory: store.documents(world.id)).save(page)
        XCTAssertEqual(store.world(containing: page.id), world.id)
        XCTAssertNil(store.world(containing: UUID()))
        XCTAssertEqual(store.pageCount(world.id), 1)
    }

    func testAdoptsPagesSavedBeforeWorlds() throws {
        let legacy = base.appendingPathComponent("Documents", isDirectory: true)
        let legacySchema = base.appendingPathComponent("Schema.json")
        let page = Document(title: "Mara")
        try DocumentStore(directory: legacy).save(page)
        let schema = Schema(types: [PageType(name: "Character")])
        try SchemaStore(url: legacySchema).save(schema)

        let store = try WorldStore(root: base.appendingPathComponent("Worlds"))
        let world = try XCTUnwrap(store.adoptLegacy(documents: legacy, schema: legacySchema))
        XCTAssertEqual(world.name, World.defaultName)
        XCTAssertEqual(store.all(), [world])
        XCTAssertEqual(try DocumentStore(directory: store.documents(world.id)).all().map(\.id), [page.id])
        XCTAssertEqual(try SchemaStore(url: store.schema(world.id)).load(), schema)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))     // moved, not copied
        XCTAssertNil(try store.adoptLegacy(documents: legacy, schema: legacySchema))   // only once
    }

    func testAWorldCutShortBeforeItsNameStillCounts() throws {
        let store = try WorldStore(root: base.appendingPathComponent("Worlds"))
        let id = UUID()
        try FileManager.default.createDirectory(at: store.documents(id), withIntermediateDirectories: true)
        XCTAssertEqual(store.all(), [World(id: id, name: World.defaultName)])
    }

    func testAMoveCutShortIsFinishedInTheSameWorld() throws {
        let legacy = base.appendingPathComponent("Documents", isDirectory: true)
        let legacySchema = base.appendingPathComponent("Schema.json")
        let schema = Schema(types: [PageType(name: "Character")])
        try SchemaStore(url: legacySchema).save(schema)
        // The pages were moved, then the run stopped: no schema, no World.json.
        let store = try WorldStore(root: base.appendingPathComponent("Worlds"))
        let id = UUID()
        let page = Document(title: "Mara")
        try DocumentStore(directory: store.documents(id)).save(page)

        let world = try XCTUnwrap(store.adoptLegacy(documents: legacy, schema: legacySchema))
        XCTAssertEqual(world.id, id)                                         // the same world, not a second
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(try SchemaStore(url: store.schema(id)).load(), schema)    // its types joined its pages
    }

    func testRemovesExpiredPagesInOtherWorlds() throws {
        let store = try WorldStore(root: base.appendingPathComponent("Worlds"))
        let open = World(name: "Open"), other = World(name: "Other")
        try store.save(open)
        try store.save(other)
        var expired = Document(title: "Old")
        expired.deleted = Date().addingTimeInterval(-31 * 86_400)
        var waiting = Document(title: "Recent")
        waiting.deleted = Date()
        let pages = try DocumentStore(directory: store.documents(other.id))
        try pages.save(expired)
        try pages.save(waiting)
        try DocumentStore(directory: store.documents(open.id)).save(expired)

        store.removeExpired(except: open.id)
        XCTAssertEqual(pages.all().map(\.id), [waiting.id])
        XCTAssertEqual(store.pageCount(open.id), 1)                         // the open world is the app's to handle
    }
}
