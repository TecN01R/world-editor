import XCTest
@testable import Guardrails
import WriterCore

/// How filing reads the author's message: where sentences end, whole words, and which
/// sentences correct something.
final class SentenceTests: XCTestCase {
    func testSentencesDontEndInsideNumbersTitlesOrInitials() {
        XCTAssertEqual(Statement.split("Dr. Vance sailed 3.5 leagues. J. R. Hale stayed! Did he?").map(\.text),
                       ["Dr. Vance sailed 3.5 leagues.", "J. R. Hale stayed!", "Did he?"])
        XCTAssertEqual(Statement.split("So did I. Then she left.").map(\.text), ["So did I.", "Then she left."])
        XCTAssertEqual(Statement.split("She said \"go.\" He went.").count, 2)
    }

    func testPhrasesAreFoundOnlyAsWholeWords() {
        XCTAssertNil(Statement.wholeWords("Al", in: "She always sails alone."))
        XCTAssertNotNil(Statement.wholeWords("Al", in: "She always sails with Al."))
        XCTAssertNotNil(Statement.wholeWords("cooper", in: "She's a Cooper, by trade."))
    }

    func testWhatCountsAsACorrection() {
        for (sentence, previous) in [("Actually she's a cooper.", nil), ("She's not a baker, she's a cooper.", nil),
                                     ("No, she's a cooper.", nil), ("She's a cooper.", "Wait."),
                                     ("She's a cooper.", "Sorry, I was wrong.")] as [(String, String?)] {
            XCTAssertTrue(Statement.corrects(sentence, after: previous), sentence)
        }
        for (sentence, previous) in [("She's a cooper.", "She has no siblings."), ("She's a cooper.", "She's not from here."),
                                     ("He's a mean man and a cooper.", nil), ("She's a cooper.", nil)] as [(String, String?)] {
            XCTAssertFalse(Statement.corrects(sentence, after: previous), sentence)
        }
    }

    // MARK: Filing

    private let trade = FieldDefinition(name: "Trade", kind: .text)
    private lazy var character = PageType(name: "Character", fields: [trade.id])

    private func filed(_ message: String, value: String, field: String = "Trade") -> FieldValue? {
        var schema = Schema(fields: [trade], types: [character])
        var her = Document(title: "Wren", paragraphs: [Paragraph(text: "A girl of the docks.")])
        her.type = character.id
        her.values[trade.id] = .text("baker")
        var pages = [her]
        _ = Filer.file(Filings(facts: [.init(page: "Wren", field: field, value: value)]),
                       message: message, open: her.id, pages: &pages, schema: &schema)
        let def = schema.fields.first { $0.name == field }
        return def.flatMap { pages[0].values[$0.id] }
    }

    /// A filled field changes only when the sentence saying the new value corrects it.
    func testAFilledFieldChangesOnlyForACorrection() {
        XCTAssertEqual(filed("She has no siblings. She's a cooper.", value: "cooper"), .text("baker"))
        XCTAssertEqual(filed("He's a mean man. She's a cooper.", value: "cooper"), .text("baker"))
        XCTAssertEqual(filed("No, she's a cooper.", value: "cooper"), .text("cooper"))
        XCTAssertEqual(filed("Wait. She's a cooper.", value: "cooper"), .text("cooper"))
    }

    /// A title's full stop doesn't hide the name after it.
    func testANameAfterATitleIsFiled() {
        XCTAssertNotNil(filed("Her teacher is Dr. Vance.", value: "Dr. Vance", field: "Teacher"))
    }

    /// "Al" isn't in "always": nothing is filed from a word inside another.
    func testNothingIsFiledFromInsideAWord() {
        XCTAssertNil(filed("She always works alone.", value: "Al", field: "Friend"))
    }
}
