import Foundation
import XCTest
@testable import WriterCore

/// The author's words placed into a page by filing: marked as placed, kept through
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

    func testWordsAddedToTheAuthorsParagraphAreMarkedAndGoWithTheirSpace() {
        var doc = Document(paragraphs: [Paragraph(text: "She grew up in Holm."), Paragraph(text: "Mine.")])
        let id = UUID(), mine = doc.paragraphs[0].id
        XCTAssertTrue(doc.append("She rows.", to: mine, as: id))
        XCTAssertEqual(doc.paragraphs.map(\.text), ["She grew up in Holm. She rows.", "Mine."])
        XCTAssertEqual(doc.paragraphs[0].placed, [PlacedRun(location: 21, length: 9, placement: id)])
        XCTAssertEqual(doc.paragraphs[0].id, mine)
        let placement = Placement(id: id, page: doc.id, paragraphs: [mine], texts: ["She rows."], appended: [true])
        XCTAssertTrue(doc.takeBack(placement))
        XCTAssertEqual(doc.paragraphs.map(\.text), ["She grew up in Holm.", "Mine."])
        XCTAssertTrue(doc.paragraphs[0].placed.isEmpty)
    }

    func testAddedWordsTheAuthorWroteInStayAndSoDoesTheirParagraph() {
        var doc = Document(paragraphs: [Paragraph(text: "She grew up in Holm.")])
        let id = UUID(), mine = doc.paragraphs[0].id
        _ = doc.append("She rows.", to: mine, as: id)
        doc.replace(24..<24, in: 0, with: " still")   // "… She still rows."
        XCTAssertEqual(doc.paragraphs[0].text, "She grew up in Holm. She still rows.")
        let placement = Placement(id: id, page: doc.id, paragraphs: [mine], texts: ["She rows."], appended: [true])
        XCTAssertFalse(doc.takeBack(placement))
        XCTAssertEqual(doc.paragraphs.map(\.text), ["She grew up in Holm. She still rows."])
    }

    func testOlderRecordsWithoutAppendedStillLoad() throws {
        let id = UUID(), page = UUID(), paragraph = UUID()
        let json = """
        {"id":"\(id)","page":"\(page)","paragraphs":["\(paragraph)"],"texts":["She rows."],"date":0}
        """
        let placement = try JSONDecoder().decode(Placement.self, from: Data(json.utf8))
        XCTAssertEqual(placement.appended, [])
        XCTAssertFalse(placement.isAppended(0))
    }
}
