import XCTest
@testable import WriterCore

final class DocumentTests: XCTestCase {
    func testSplitAndMergeRoundTrip() {
        var d = Document(paragraphs: [Paragraph(text: "Hello world")])
        let i = d.split(at: 0, offset: 5)
        XCTAssertEqual(i, 1)
        XCTAssertEqual(d.paragraphs.map(\.text), ["Hello", " world"])
        let caret = d.mergeWithPrevious(1)
        XCTAssertEqual(caret, 5)
        XCTAssertEqual(d.paragraphs.map(\.text), ["Hello world"])
    }

    func testMergeFirstParagraphDoesNothing() {
        var d = Document(paragraphs: [Paragraph(text: "a")])
        XCTAssertNil(d.mergeWithPrevious(0))
    }

    func testSetParagraphsKeepsIdentityOfUnchangedAndEditedParagraphs() {
        var d = Document(paragraphs: [Paragraph(text: "one"), Paragraph(text: "two"), Paragraph(text: "three")])
        let ids = d.paragraphs.map(\.id)
        d.setParagraphs(["one", "two edited", "three"].map { Paragraph(text: $0) })
        XCTAssertEqual(d.paragraphs.map(\.text), ["one", "two edited", "three"])
        XCTAssertEqual(d.paragraphs.map(\.id), ids)
    }

    func testSetParagraphsNewParagraphGetsNewID() {
        var d = Document(paragraphs: [Paragraph(text: "one")])
        let first = d.paragraphs[0].id
        d.setParagraphs(["one", "new"].map { Paragraph(text: $0) })
        XCTAssertEqual(d.paragraphs[0].id, first)
        XCTAssertNotEqual(d.paragraphs[1].id, first)
    }

    func testEmptyDocumentAlwaysHasOneParagraph() {
        XCTAssertEqual(Document(paragraphs: []).paragraphs.count, 1)
    }

    func testStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try DocumentStore(directory: dir)
        let d = Document(title: "T", paragraphs: [Paragraph(text: "x")])
        try store.save(d)
        XCTAssertEqual(store.all(), [d])
    }

    func testSearchResultsShowAndOpenAtTheWords() {
        XCTAssertEqual(Search.terms(#"bell "north mooring" tide"#), ["bell", "north mooring", "tide"])
        let page = Document(title: "Mara", paragraphs: [
            Paragraph(text: "Keeps the lighthouse."),
            Paragraph(text: "Once sailed the long route past the Café de la Côte at dawn."),
        ])
        XCTAssertEqual(page.offset(of: "dawn cote", inParagraph: 1), 47)          // the earliest term, accents ignored
        XCTAssertNil(page.offset(of: "harbour", inParagraph: 0))
        XCTAssertEqual(page.excerpt(paragraph: 0), "Keeps the lighthouse.")
        XCTAssertEqual(page.excerpt(paragraph: 1, at: 47), "…ute past the Café de la Côte at dawn.")
    }

    func testTypesShareFieldsAndPageFieldsAreMentions() throws {
        let place = PageType(name: "Place")
        let tower = Document(title: "The Black Tower", type: place.id)
        let species = FieldDefinition(name: "Species", kind: .choice, options: ["Human", "Elf"])
        let age = FieldDefinition(name: "Age", kind: .number)
        let home = FieldDefinition(name: "Home", kind: .page, pageType: place.id)
        let character = PageType(name: "Character", fields: [species.id, age.id, home.id])
        let creature = PageType(name: "Creature", fields: [species.id])
        let schema = Schema(fields: [species, age, home], types: [place, character, creature])
        XCTAssertEqual(schema.fields(of: character).map(\.name), ["Species", "Age", "Home"])
        XCTAssertEqual(schema.fields(of: creature), [species])                  // one shared field

        let mara = Document(title: "Mara", type: character.id,
                            values: [species.id: .text("Elf"), age.id: .number(34), home.id: .page(tower.id)])
        XCTAssertEqual(try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(mara)), mara)
        XCTAssertEqual(mara.fieldText(schema.fields(of: character)) { $0 == tower.id ? tower.title : nil },
                       "Species: Elf\nAge: 34\nHome: The Black Tower")
        XCTAssertTrue(mara.mentions(tower.id))                                   // a page field is a backlink

        let old = #"{"id":"\#(UUID().uuidString)","title":"Old","paragraphs":[{"id":"\#(UUID().uuidString)","text":"Hi"}],"modified":0}"#
        let page = try JSONDecoder().decode(Document.self, from: Data(old.utf8))
        XCTAssertNil(page.type)
        XCTAssertTrue(page.values.isEmpty)

        let store = SchemaStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json"))
        XCTAssertEqual(try store.load(), Schema())
        try store.save(schema)
        XCTAssertEqual(try store.load(), schema)
    }
}

final class SchemaTypeTests: XCTestCase {
    private let home = FieldDefinition(name: "Home", kind: .page)
    private let age = FieldDefinition(name: "Age", kind: .number)

    func testRenamingKeepsTheTypesFields() {
        let place = PageType(name: "Plcae", fields: [age.id])
        var schema = Schema(fields: [age], types: [place])
        schema.renameType(place.id, to: "Place")
        XCTAssertEqual(schema.type(place.id)?.name, "Place")
        XCTAssertEqual(schema.fields(of: schema.type(place.id)), [age])
    }

    func testRemovingKeepsSharedFieldsAndFreesPageFields() {
        let place = PageType(name: "Place")
        var home = home
        home.pageType = place.id
        let character = PageType(name: "Character", fields: [home.id, age.id])
        var schema = Schema(fields: [home, age], types: [place, character])
        schema.removeType(place.id)
        XCTAssertNil(schema.type(place.id))
        XCTAssertEqual(schema.fields.count, 2)                                    // nothing lost
        XCTAssertNil(schema.fields.first { $0.id == home.id }?.pageType)          // now takes any page
        XCTAssertEqual(schema.fields(of: schema.type(character.id)).map(\.id), [home.id, age.id])
    }
}

final class RecentlyDeletedTests: XCTestCase {
    func testADeletedPageWaitsThirtyDays() {
        var page = Document(title: "Mara")
        XCTAssertNil(page.goesForGood)
        let now = Date()
        page.deleted = now
        XCTAssertEqual(page.goesForGood, now.addingTimeInterval(30 * 86_400))
        XCTAssertEqual(page.daysLeft(now: now), 30)
        XCTAssertEqual(page.daysLeft(now: now.addingTimeInterval(29.5 * 86_400)), 1)   // part of a day counts
        XCTAssertEqual(page.daysLeft(now: now.addingTimeInterval(31 * 86_400)), 0)
    }

    func testDeletedSurvivesSavingAndOldPagesLoad() throws {
        var page = Document(title: "Mara")
        page.deleted = Date(timeIntervalSince1970: 1_000_000)
        let saved = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(saved.deleted, page.deleted)
        // Saved before Recently Deleted existed: no key, not deleted.
        let old = try JSONEncoder().encode(Document(title: "Old"))
        XCTAssertFalse(String(decoding: old, as: UTF8.self).contains("deleted"))
        XCTAssertNil(try JSONDecoder().decode(Document.self, from: old).deleted)
    }
}
