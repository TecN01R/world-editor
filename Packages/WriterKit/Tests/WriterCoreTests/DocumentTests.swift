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
        XCTAssertEqual(try store.all(), [d])
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
        XCTAssertEqual(store.load(), Schema())
        try store.save(schema)
        XCTAssertEqual(store.load(), schema)
    }
}
