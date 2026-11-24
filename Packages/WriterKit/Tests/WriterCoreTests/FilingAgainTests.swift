import XCTest
@testable import WriterCore

/// When Try Again reads the author's message again for filing: only if nothing came of it before.
final class FilingAgainTests: XCTestCase {
    private func answered(_ filed: FilingRecord?) -> Conversation.Turn {
        Conversation.Turn(question: "Is that like a sailor?", answer: "I think it was actually a bireme", filed: filed)
    }

    func testAnAnswerNeverReadIsFiled() {
        XCTAssertTrue(answered(nil).needsFiling)
        XCTAssertFalse(Conversation.Turn(question: "Hi").needsFiling)   // nothing said yet
    }

    /// The first reading found nothing (a weaker model read "trireme"): Try Again reads it again.
    func testAnAnswerThatFiledNothingIsReadAgain() {
        XCTAssertTrue(answered(FilingRecord()).needsFiling)
    }

    func testAnAnswerThatFiledSomethingIsntReadAgain() {
        let filed = FilingRecord(entries: [.typed(page: UUID(), type: UUID())])
        XCTAssertFalse(answered(filed).needsFiling)
    }

    /// Everything filed from it was undone: reading it again would bring back what they took back.
    func testAnAnswerWhoseFilingWasUndoneIsntReadAgain() throws {
        var page = Document(title: "Casperica", paragraphs: [Paragraph(text: "")])
        let field = UUID()
        page.values[field] = .text("bireme")
        var pages = [page], schema = Schema()
        var record = FilingRecord(entries: [.value(page: page.id, field: field, value: .text("bireme"))])
        _ = record.undo(try XCTUnwrap(record.actions.first), pages: &pages, schema: &schema)
        XCTAssertTrue(record.entries.isEmpty)
        XCTAssertTrue(record.undid)
        XCTAssertFalse(answered(record).needsFiling)
    }

    /// An empty record from before `undid` can't tell "found nothing" from "all undone":
    /// it counts as undone, so nothing the author took back is read in again.
    func testRecordsSavedBeforeUndidExistedArentReadAgain() throws {
        let old = try JSONDecoder().decode(FilingRecord.self, from: Data(#"{"entries":[]}"#.utf8))
        XCTAssertTrue(old.undid)
        XCTAssertNil(old.seen)
        XCTAssertFalse(answered(old).needsFiling)
        let field = UUID()
        let new = FilingRecord(seen: [field: .text("trireme")])
        let again = try JSONDecoder().decode(FilingRecord.self, from: JSONEncoder().encode(new))
        XCTAssertFalse(again.undid)
        XCTAssertEqual(again.seen, [field: .text("trireme")])
        XCTAssertTrue(answered(again).needsFiling)
    }
}
