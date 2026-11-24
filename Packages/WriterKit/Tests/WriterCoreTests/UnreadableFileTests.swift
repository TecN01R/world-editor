import XCTest
@testable import WriterCore

/// A saved file this version can't read (a newer version's, or damaged) is left exactly
/// as it is: never saved over, never deleted, and reported.
final class UnreadableFileTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Types and fields from a newer version, with a kind of field this one doesn't know.
    private let newerSchema = Data("""
        {"fields":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"map","name":"Route","options":[]}],"types":[]}
        """.utf8)

    func testTypesAndFieldsAVersionCantReadAreNeverSavedOver() throws {
        let url = folder.appendingPathComponent("Schema.json")
        try newerSchema.write(to: url)
        let store = SchemaStore(url: url)

        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? UnreadableFile, UnreadableFile(url: url)) }
        XCTAssertThrowsError(try store.save(Schema(types: [PageType(name: "Character")])))
        XCTAssertEqual(try Data(contentsOf: url), newerSchema)
    }

    func testNoTypesAndFieldsYetIsntAnError() throws {
        let store = SchemaStore(url: folder.appendingPathComponent("Schema.json"))
        XCTAssertEqual(try store.load(), Schema())
        let schema = Schema(types: [PageType(name: "Place")])
        try store.save(schema)
        XCTAssertEqual(try store.load(), schema)
    }

    func testAConversationAVersionCantReadIsKeptAsItIs() throws {
        let store = try ConversationStore(directory: folder)
        let page = UUID(), damaged = Data("{\"page\":".utf8)
        let url = folder.appendingPathComponent("\(page.uuidString).json")
        try damaged.write(to: url)
        let readable = Conversation(page: UUID(), turns: [.init(question: "Who is she?", answer: "A cooper.")])
        try store.save(readable)

        XCTAssertThrowsError(try store.load(page))
        XCTAssertThrowsError(try store.save(Conversation(page: page)))
        store.delete(page)
        XCTAssertTrue(store.hasTalk(page))   // so the page it's on isn't thrown away
        XCTAssertEqual(store.all(), [readable])
        XCTAssertEqual(store.scan().unreadable.map(\.lastPathComponent), [url.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: url), damaged)

        XCTAssertEqual(try store.load(UUID()).turns, [])   // nothing said yet isn't an error
        XCTAssertFalse(store.hasTalk(UUID()))
    }

    func testAPageAVersionCantReadIsReportedAndLeftAlone() throws {
        let store = try DocumentStore(directory: folder)
        let page = Document(title: "Harbour", paragraphs: [Paragraph(text: "Grey water.")])
        try store.save(page)
        let url = folder.appendingPathComponent("\(UUID().uuidString).json")
        let newer = Data("{\"id\":\"\(UUID().uuidString)\",\"title\":\"Map\",\"paragraphs\":[{\"id\":\"\(UUID().uuidString)\",\"text\":\"x\",\"kind\":\"table\"}],\"modified\":0}".utf8)
        try newer.write(to: url)

        let found = store.scan()
        XCTAssertEqual(found.pages.map(\.id), [page.id])
        XCTAssertEqual(found.unreadable.map(\.lastPathComponent), [url.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: url), newer)
    }

    /// A page with a type or a field filled in isn't empty, so leaving it never discards it.
    func testAPageWithOnlyATypeOrFieldsIsntEmpty() {
        var page = Document()
        XCTAssertTrue(page.isEmpty)
        page.type = UUID()
        XCTAssertFalse(page.isEmpty)
        page.type = nil
        page.values[UUID()] = .text("cooper")
        XCTAssertFalse(page.isEmpty)
    }

    /// The same field twice, its id in upper and lower case, loads instead of crashing.
    func testAFieldSavedTwiceUnderOneIdLoads() throws {
        let field = UUID().uuidString
        let json = """
            {"id":"\(UUID().uuidString)","title":"","modified":0,"paragraphs":[{"id":"\(UUID().uuidString)","text":""}],
             "values":{"\(field)":{"text":{"_0":"a"}},"\(field.lowercased())":{"text":{"_0":"b"}}}}
            """
        let page = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        XCTAssertEqual(page.values.count, 1)
    }

    /// Pasted text's line breaks of every kind split paragraphs.
    func testEveryKindOfLineBreakSplitsParagraphs() {
        var page = Document()
        page.replace(0..<0, in: 0, with: "one\rtwo\u{2029}three\r\nfour\u{2028}five")
        XCTAssertEqual(page.paragraphs.map(\.text), ["one", "two", "three", "four", "five"])
    }

    /// Selecting whole lines takes the line break after the last one; the next line isn't touched.
    func testAListLeavesTheLineAfterASelectionAlone() {
        var page = Document(paragraphs: [Paragraph(text: "ab"), Paragraph(text: "cd")])
        page.toggleKind(.bullet, in: 0..<3)   // "ab\n"
        XCTAssertEqual(page.paragraphs.map(\.kind), [.bullet, .body])
    }
}
