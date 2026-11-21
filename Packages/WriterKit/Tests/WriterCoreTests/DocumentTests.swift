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
        XCTAssertTrue(page.contains(allOf: "dawn mara"))                         // title and text, any order
        XCTAssertFalse(page.contains(allOf: "dawn harbour"))
        XCTAssertEqual(page.paragraph(matching: "dawn"), 1)
    }
}
