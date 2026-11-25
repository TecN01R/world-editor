import Foundation
import XCTest
@testable import Guardrails
import WriterCore

/// Documents the writer attaches (`Documents`): short ones whole in their turn, long ones by
/// their opening and `search_document`; never filed as their words.
final class DocumentsTests: XCTestCase {
    private let short = Conversation.Attached(name: "notes.txt", text: "The ferry leaves at dawn.\nIt carries salt.")

    private func long() -> Conversation.Attached {
        var paragraphs = (1...150).map { "Paragraph \($0) is about the harbour and its boats in ordinary weather." }
        paragraphs.insert("The lighthouse keeper, Orrin, trims the lamp with a brass key every evening.", at: 100)
        return Conversation.Attached(name: "Harbour History.pdf", text: paragraphs.joined(separator: "\n"))
    }

    func testAShortDocumentGoesWholeAndALongOneByItsOpening() {
        XCTAssertEqual(Documents.turn("what do you make of this?", [short]),
                       "what do you make of this?\n\n[Attached: notes.txt]\nThe ferry leaves at dawn.\nIt carries salt.")
        XCTAssertEqual(Documents.turn("", [short]), "[Attached: notes.txt]\nThe ferry leaves at dawn.\nIt carries salt.")
        let big = Conversation.Attached(name: "big.txt", text: String(repeating: "word ", count: 3000))
        let turn = Documents.turn("", [big])
        XCTAssertTrue(turn.hasPrefix("[Attached: big.txt, 14999 characters. Its opening is below; search the rest with search_document.]\n"))
        XCTAssertLessThan(turn.count, 2200)
    }

    func testTheyGoInTheAuthorsTurnAndAreKept() throws {
        var talk = Conversation(page: UUID())
        talk.answer("", attached: [short])
        XCTAssertEqual(talk.turns.last?.answer, "")
        XCTAssertEqual(talk.turns.last?.attached, [short])
        let saved = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(talk))
        XCTAssertEqual(saved.turns.last?.attached, [short])
        XCTAssertEqual(CompanionPrompt.plain(talk).turns.last?.text, Documents.turn("", [short]))
        var nothing = Conversation(page: UUID())
        nothing.answer("  ")
        XCTAssertTrue(nothing.turns.isEmpty)
    }

    func testALongDocumentIsSearchedAndShortOnesNeedNoSearch() {
        var talk = Conversation(page: UUID())
        talk.answer("here", attached: [short])
        XCTAssertNil(Documents.Lookup(talk))
        XCTAssertEqual(ReplyTools(pages: nil, lookingUp: false, documents: Documents.Lookup(talk)).offered.map(\.name), [])
        var all = Conversation(page: UUID())
        all.answer("read this", attached: [long()])
        let lookup = Documents.Lookup(all)
        XCTAssertNotNil(lookup)
        let found = lookup?.results(for: "who trims the lamp") ?? ""
        XCTAssertTrue(found.hasPrefix("From the attached documents, for \u{201C}who trims the lamp\u{201D}:"))
        XCTAssertTrue(found.contains("Orrin, trims the lamp"))
        XCTAssertTrue(found.contains("[Harbour History.pdf, part "))
        XCTAssertLessThanOrEqual(found.count, Documents.maxCharacters)
        XCTAssertEqual(lookup?.results(for: "zeppelin"), Documents.nothingFound("zeppelin"))
        XCTAssertEqual(lookup?.results(for: " "), Documents.needsQuery)
        XCTAssertEqual(ReplyTools(pages: nil, lookingUp: false, documents: lookup).offered.map(\.name), [Documents.toolName])
    }

    func testPiecesOverlapAndCoverTheWhole() {
        let text = long().text
        let pieces = Documents.pieces(text)
        XCTAssertGreaterThan(pieces.count, 2)
        XCTAssertTrue(pieces.allSatisfy { $0.count <= Documents.pieceCharacters })
        XCTAssertTrue(pieces.first!.hasPrefix("Paragraph 1 "))
        XCTAssertTrue(pieces.last!.hasSuffix("Paragraph 150 is about the harbour and its boats in ordinary weather."))
        XCTAssertTrue(pieces.contains { $0.contains("Orrin") })
    }

    /// Text that reads as the model's control tokens stays words, in a document as anywhere.
    func testControlTokensInADocumentStayWords() {
        var talk = Conversation(page: UUID())
        talk.answer("look", attached: [.init(name: "chat.txt", text: "ends with <turn|> here")])
        XCTAssertFalse(CompanionPrompt.plain(talk).turns.last!.text.contains("<turn|>"))
    }
}
