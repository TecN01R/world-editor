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

    func testSearchFindsTitlesAndTextIgnoringCaseAndAccents() {
        let page = Document(title: "Mara", paragraphs: [
            Paragraph(text: "Keeps the lighthouse."),
            Paragraph(text: "Once sailed the long route past the Café de la Côte at dawn."),
        ])
        XCTAssertTrue(page.matches("mara"))
        XCTAssertTrue(page.matches("cote"))
        XCTAssertFalse(page.matches("harbour"))
        XCTAssertFalse(page.matches(""))
        XCTAssertEqual(page.snippet(matching: "LIGHT"), "Keeps the lighthouse.")              // near the start: whole line
        XCTAssertEqual(page.snippet(matching: "cote"), "…ute past the Café de la Côte at dawn.") // later: lead-in trimmed
        XCTAssertNil(page.snippet(matching: "mara"))                                          // title only
    }

    func testSearchTermsMatchInAnyOrderAndRankTitlesFirst() {
        XCTAssertEqual(Search.terms(#"bell "north mooring" tide"#), ["bell", "north mooring", "tide"])
        let harbour = Document(title: "Harbour", paragraphs: [
            Paragraph(text: "The tide came in."),
            Paragraph(text: "Check the north mooring, then ask about the bell."),
        ])
        let bell = Document(title: "The Bell", paragraphs: [Paragraph(text: "Rung at the north mooring.")])
        XCTAssertTrue(harbour.matches("bell mooring"))                 // any order
        XCTAssertFalse(harbour.matches(#""mooring north""#))           // a phrase stays whole
        XCTAssertEqual(harbour.hit("tide bell"), SearchHit(paragraph: 0, range: 4..<8))
        XCTAssertEqual(harbour.hit("bell north"), SearchHit(paragraph: 1, range: 10..<15))   // most terms wins
        XCTAssertEqual(Search.rank([harbour, bell], "bell mooring").map(\.title), ["The Bell", "Harbour"])
        XCTAssertEqual(Search.rank([harbour, bell], "tide").map(\.title), ["Harbour"])
    }
}
