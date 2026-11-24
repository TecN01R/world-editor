import XCTest
@testable import WriterCore

/// Undo to here: a change and everything filed since that built on it, newest first
/// (Kevin, 2026-11-24).
final class UndoChainTests: XCTestCase {
    let page = UUID(), vessel = UUID(), ruler = UUID()

    private func talk(_ records: [FilingRecord]) -> Conversation {
        Conversation(page: page, turns: records.map { Conversation.Turn(question: "?", answer: "!", filed: $0) })
    }

    func testAFieldsLaterValuesComeOffNewestFirst() throws {
        let trireme = FilingRecord.Entry.value(page: page, field: vessel, value: .text("trireme"))
        let bireme = FilingRecord.Entry.replaced(page: page, field: vessel, was: .text("trireme"), value: .text("bireme"))
        let galley = FilingRecord.Entry.replaced(page: page, field: vessel, was: .text("bireme"), value: .text("galley"))
        let conversation = talk([FilingRecord(entries: [trireme]), FilingRecord(entries: [bireme]), FilingRecord(entries: [galley])])
        let chain = try XCTUnwrap(conversation.undoChain(trireme, in: conversation.turns[0].id))
        XCTAssertEqual(chain.map(\.action), [galley, bireme, trireme])
        XCTAssertEqual(try XCTUnwrap(conversation.undoChain(galley, in: conversation.turns[2].id)).map(\.action), [galley])
    }

    /// A page made, then a fact on it and a link to it from later messages: all come off with it.
    func testAPageTakesWhatWasBuiltOnIt() throws {
        let made = FilingRecord.Entry.created(page: page, modified: Date())
        let onIt = FilingRecord.Entry.value(page: page, field: ruler, value: .text("a council"))
        let other = UUID()
        let toIt = FilingRecord.Entry.value(page: other, field: vessel, value: .page(page))
        let unrelated = FilingRecord.Entry.value(page: other, field: ruler, value: .text("no one"))
        let conversation = talk([FilingRecord(entries: [made]), FilingRecord(entries: [onIt]),
                                 FilingRecord(entries: [toIt, unrelated])])
        let chain = try XCTUnwrap(conversation.undoChain(made, in: conversation.turns[0].id))
        XCTAssertEqual(chain.map(\.action), [toIt, onIt, made])
    }

    /// Within one message: a type waits for its fields, a page's own links go with it.
    func testWithinOneMessage() throws {
        let typed = FilingRecord.Entry.typed(page: page, type: UUID())
        let filled = FilingRecord.Entry.value(page: page, field: vessel, value: .text("trireme"))
        let conversation = talk([FilingRecord(entries: [typed, filled])])
        XCTAssertEqual(try XCTUnwrap(conversation.undoChain(typed, in: conversation.turns[0].id)).map(\.action), [filled, typed])

        let made = FilingRecord.Entry.created(page: page, modified: Date())
        let toIt = FilingRecord.Entry.value(page: UUID(), field: ruler, value: .page(page))
        let withIt = talk([FilingRecord(entries: [made, toIt])])
        XCTAssertEqual(try XCTUnwrap(withIt.undoChain(made, in: withIt.turns[0].id)).map(\.action), [made])
    }

    /// Something filed from another conversation built on it: undone there first.
    func testBuiltOnElsewhereStops() {
        let trireme = FilingRecord.Entry.value(page: page, field: vessel, value: .text("trireme"))
        var mine = talk([FilingRecord(entries: [trireme])])
        mine.turns[0].filed?.date = Date(timeIntervalSince1970: 100)
        var later = FilingRecord(entries: [.replaced(page: page, field: vessel, was: .text("trireme"), value: .text("bireme"))])
        later.date = Date(timeIntervalSince1970: 200)
        let other = Conversation(page: UUID(), turns: [Conversation.Turn(question: "?", answer: "!", filed: later)])
        XCTAssertNil(mine.undoChain(trireme, in: mine.turns[0].id, elsewhere: [other]))
        XCTAssertEqual(mine.undoChain(trireme, in: mine.turns[0].id)?.count, 1)
    }
}
