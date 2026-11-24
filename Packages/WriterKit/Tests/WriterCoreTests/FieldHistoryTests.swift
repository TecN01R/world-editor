import XCTest
@testable import WriterCore

/// A field changed more than once has a timeline (Kevin, 2026-11-24).
final class FieldHistoryTests: XCTestCase {
    let page = UUID(), vessel = UUID(), age = UUID()

    func testAFieldsValuesOldestFirstWithTheirMessages() {
        var talk = Conversation(page: page)
        let first = Date(timeIntervalSince1970: 1000), second = Date(timeIntervalSince1970: 2000)
        talk.ask("What's she like?")
        talk.answer("A rower on a trireme", at: first)
        talk.turns[0].filed = FilingRecord(entries: [.value(page: page, field: vessel, value: .text("trireme")),
                                                     .value(page: page, field: age, value: .text("24"))])
        talk.ask("A trireme!")
        talk.answer("Actually it's a bireme", at: second)
        talk.turns[1].filed = FilingRecord(entries: [.replaced(page: page, field: vessel, was: .text("trireme"),
                                                               value: .text("bireme"))])

        let history = talk.history(of: vessel, on: page)
        XCTAssertEqual(history.map(\.value), [.text("trireme"), .text("bireme")])
        XCTAssertEqual(history.map(\.message), ["A rower on a trireme", "Actually it's a bireme"])
        XCTAssertEqual(history.map(\.date), [first, second])
        XCTAssertEqual(talk.history(of: age, on: page).count, 1)
        XCTAssertTrue(talk.history(of: vessel, on: UUID()).isEmpty)
    }

    /// Undone values leave the timeline; old conversations without answer times use the question's.
    func testUndoneValuesLeaveAndOldTurnsUseTheirQuestionsTime() throws {
        let asked = Date(timeIntervalSince1970: 500)
        var turn = Conversation.Turn(question: "?", answer: "a trireme", asked: asked,
                                     filed: FilingRecord(entries: [.value(page: page, field: vessel, value: .text("trireme"))]))
        var talk = Conversation(page: page, turns: [turn])
        XCTAssertEqual(talk.history(of: vessel, on: page).map(\.date), [asked])

        var doc = Document(title: "Casperica", paragraphs: [Paragraph(text: "")])
        doc.values[vessel] = .text("trireme")
        var pages = [doc], schema = Schema()
        var record = try XCTUnwrap(turn.filed)
        _ = record.undo(try XCTUnwrap(record.actions.first), pages: &pages, schema: &schema)
        turn.filed = record
        talk.turns[0] = turn
        XCTAssertTrue(talk.history(of: vessel, on: page).isEmpty)
    }
}
