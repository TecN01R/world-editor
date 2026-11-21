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

    func testSetPlainTextKeepsIdentityOfUnchangedAndEditedParagraphs() {
        var d = Document(paragraphs: [Paragraph(text: "one"), Paragraph(text: "two"), Paragraph(text: "three")])
        let ids = d.paragraphs.map(\.id)
        d.setPlainText("one\ntwo edited\nthree")
        XCTAssertEqual(d.paragraphs.map(\.text), ["one", "two edited", "three"])
        XCTAssertEqual(d.paragraphs.map(\.id), ids)
    }

    func testSetPlainTextNewParagraphGetsNewID() {
        var d = Document(paragraphs: [Paragraph(text: "one")])
        let first = d.paragraphs[0].id
        d.setPlainText("one\nnew")
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
}
