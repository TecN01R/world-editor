import XCTest
@testable import WriterCore

/// Undo goes newest first for each field and page (Kevin, 2026-11-24): what a later
/// message built on waits until that is undone.
final class UndoNewestFirstTests: XCTestCase {
    let casperica = Document(title: "Casperica", paragraphs: [Paragraph(text: "A rower.")])
    let vessel = UUID(), age = UUID(), ruler = UUID(), nation = UUID()

    /// A conversation whose answers filed `records`, oldest first.
    private func talk(_ records: [FilingRecord]) -> Conversation {
        Conversation(page: casperica.id, turns: records.map {
            Conversation.Turn(question: "?", answer: "!", filed: $0)
        })
    }

    /// "Vessel: trireme", then "Actually it's a bireme": the trireme line waits for the bireme one.
    func testACorrectedValueWaitsForTheCorrection() throws {
        let first = FilingRecord(entries: [.value(page: casperica.id, field: vessel, value: .text("trireme"))])
        var second = FilingRecord(entries: [.replaced(page: casperica.id, field: vessel, was: .text("trireme"),
                                                      value: .text("bireme"))])
        var conversation = talk([first, second])
        let trireme = first.actions[0], bireme = second.actions[0]
        XCTAssertTrue(conversation.changedLater(trireme, in: conversation.turns[0].id))
        XCTAssertFalse(conversation.changedLater(bireme, in: conversation.turns[1].id))

        // Undo the bireme: trireme is back, and now its own Undo works, emptying the field.
        var her = casperica
        her.values[vessel] = .text("bireme")
        var pages = [her], schema = Schema()
        _ = second.undo(bireme, pages: &pages, schema: &schema)
        conversation.turns[1].filed = second
        XCTAssertEqual(pages[0].values[vessel], .text("trireme"))
        XCTAssertFalse(conversation.changedLater(trireme, in: conversation.turns[0].id))
        var undone = first
        _ = undone.undo(trireme, pages: &pages, schema: &schema)
        XCTAssertNil(pages[0].values[vessel])
    }

    /// A page made in one message, then a fact on it or a link to it in a later one.
    func testAPageWaitsForWhatLaterMessagesFiledOnIt() {
        let myriddea = UUID(), ysolde = UUID()
        let made = FilingRecord(entries: [.created(page: myriddea, modified: Date())])
        let onIt = FilingRecord(entries: [.value(page: myriddea, field: ruler, value: .page(ysolde))])
        let toIt = FilingRecord(entries: [.value(page: casperica.id, field: nation, value: .page(myriddea))])
        for later in [onIt, toIt] {
            let conversation = talk([made, later])
            XCTAssertTrue(conversation.changedLater(made.actions[0], in: conversation.turns[0].id))
        }
        let alone = talk([made, FilingRecord()])
        XCTAssertFalse(alone.changedLater(made.actions[0], in: alone.turns[0].id))
    }

    /// From the same message, a page's links and facts go with it (one Undo, as before).
    func testAPageTakesWhatItsOwnMessageFiledOnIt() throws {
        let myriddea = Document(title: "Myriddea", paragraphs: [Paragraph(text: "A thalassocratic nation")])
        var her = casperica, nationPage = myriddea
        her.values[nation] = .page(myriddea.id)
        nationPage.values[ruler] = .text("a council")
        var record = FilingRecord(entries: [
            .created(page: myriddea.id, modified: myriddea.modified),
            .value(page: casperica.id, field: nation, value: .page(myriddea.id)),
            .value(page: myriddea.id, field: ruler, value: .text("a council")),
        ])
        let conversation = talk([record])
        XCTAssertFalse(conversation.changedLater(record.actions[0], in: conversation.turns[0].id))

        var pages = [her, nationPage], schema = Schema()
        let made = try XCTUnwrap(record.undo(record.actions[0], pages: &pages, schema: &schema))
        XCTAssertFalse(made.edited)
        XCTAssertEqual(pages.map(\.id), [casperica.id])
        XCTAssertNil(pages[0].values[nation])
        XCTAssertTrue(record.isEmpty)
    }

    /// A type waits for the fields filled on that page, even from the same message (they come with it).
    func testATypeWaitsForTheFieldsFilledUnderIt() {
        let character = UUID()
        let record = FilingRecord(entries: [.typed(page: casperica.id, type: character),
                                            .value(page: casperica.id, field: age, value: .text("24"))])
        let conversation = talk([record])
        XCTAssertTrue(conversation.changedLater(record.actions[0], in: conversation.turns[0].id))
        XCTAssertFalse(conversation.changedLater(record.actions[1], in: conversation.turns[0].id))
    }

    /// Filing from another conversation added to the page: undoing it sends it to Recently Deleted.
    func testAPageFilledFromElsewhereCountsAsEdited() throws {
        var myriddea = Document(title: "Myriddea", paragraphs: [Paragraph(text: "")])
        let at = myriddea.modified
        myriddea.values[ruler] = .text("a council")   // filed while talking on another page
        var record = FilingRecord(entries: [.created(page: myriddea.id, modified: at)])
        var pages = [casperica, myriddea], schema = Schema()
        let made = try XCTUnwrap(record.undo(record.actions[0], pages: &pages, schema: &schema))
        XCTAssertTrue(made.edited)
        XCTAssertEqual(pages.count, 2)   // the app sends it to Recently Deleted
    }
}
