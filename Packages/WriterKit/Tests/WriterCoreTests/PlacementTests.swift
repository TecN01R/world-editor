import Foundation
import XCTest
@testable import WriterCore

/// The author's words placed into a page (Add to Page): marked as placed, kept through
/// editing, and taken back only where still as placed.
final class PlacementTests: XCTestCase {
    func testPlacedWordsGoAtTheEndMarkedAndAnEmptyLastLineTakesTheFirst() {
        var doc = Document(paragraphs: [Paragraph(text: "Mine."), Paragraph()])
        let placement = UUID()
        let ids = doc.place(["She rows.", "She is free."], as: placement)
        XCTAssertEqual(doc.paragraphs.map(\.text), ["Mine.", "She rows.", "She is free."])
        XCTAssertEqual(ids, doc.paragraphs.dropFirst().map(\.id))
        XCTAssertEqual(doc.paragraphs[1].placed, [PlacedRun(location: 0, length: 9, placement: placement)])
        XCTAssertTrue(doc.paragraphs[0].placed.isEmpty)
    }

    func testTypingInsidePlacedWordsIsTheAuthorsAndTheMarksSurviveSplitsAndJoins() {
        let placement = UUID()
        var doc = Document(paragraphs: [Paragraph()])
        _ = doc.place(["She rows."], as: placement)
        doc.replace(3..<3, in: 0, with: " still")   // "She still rows."
        XCTAssertEqual(doc.paragraphs[0].text, "She still rows.")
        XCTAssertEqual(doc.paragraphs[0].placed, [PlacedRun(location: 0, length: 3, placement: placement),
                                                  PlacedRun(location: 9, length: 6, placement: placement)])
        let next = doc.split(at: 0, offset: 9)
        XCTAssertEqual(doc.paragraphs[next].placed, [PlacedRun(location: 0, length: 6, placement: placement)])
        doc.mergeWithPrevious(next)
        XCTAssertEqual(doc.paragraphs[0].placed.count, 2)
    }

    func testTakingBackRemovesOnlyWhatsStillAsPlaced() {
        var doc = Document(paragraphs: [Paragraph(text: "Mine.")])
        let id = UUID()
        let texts = ["She rows.", "She is free."]
        let placement = Placement(id: id, page: doc.id, paragraphs: doc.place(texts, as: id), texts: texts)
        XCTAssertTrue(doc.holds(placement))
        doc.replace(0..<0, in: 2, with: "Yes, ")   // the author wrote in the second
        XCTAssertTrue(doc.takeBack(placement))
        XCTAssertEqual(doc.paragraphs.map(\.text), ["Mine.", "Yes, She is free."])
        XCTAssertFalse(doc.takeBack(placement))
    }

    func testTakingBackEverythingLeavesAnEmptyPageNotNoParagraphs() {
        var doc = Document()
        let id = UUID()
        let placement = Placement(id: id, page: doc.id, paragraphs: doc.place(["Hello."], as: id), texts: ["Hello."])
        XCTAssertTrue(doc.takeBack(placement))
        XCTAssertEqual(doc.paragraphs.map(\.text), [""])
        XCTAssertFalse(doc.holds(placement))
    }

    func testMarksAreSavedAndPagesWithoutThemStillLoad() throws {
        let id = UUID()
        var doc = Document()
        _ = doc.place(["She rows."], as: id)
        let loaded = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(doc))
        XCTAssertEqual(loaded.paragraphs, doc.paragraphs)
        let plain = try JSONEncoder().encode(Paragraph(text: "Mine."))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("placed"))
    }
}
