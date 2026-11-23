import XCTest
@testable import Guardrails

final class PageQuestionsTests: XCTestCase {
    let page = PageQuestions(authorText: "Mara keeps the lighthouse alone. She never leaves the island, even when her brother Tomas writes.")

    func testKeepsQuestionsAboutTheAuthorsOwnWords() {
        let q = "Why does Mara never leave the island?"
        XCTAssertEqual(page.accepted([q]), [q])
    }

    func testDropsSuggestionsInventionsAndStatements() {
        XCTAssertEqual(page.accepted([
            "What if Tomas visits the lighthouse?",        // a suggestion dressed as a question
            "Is the lighthouse haunted?",                  // a detail the author never wrote
            "Why does Elena write to Mara?",               // a name the author never wrote
            "Mara seems lonely.",                          // not a question
        ]), [])
    }

    func testTidiesNumberingAndDropsRepeats() {
        let q = "Why does Mara never leave the island?"
        XCTAssertEqual(page.accepted(["1. " + q, "- " + q, "  \(q)  "]), [q])
    }

    func testStopsAtTheCount() {
        let qs = ["Why does Mara never leave the island?",
                  "What does Tomas want when he writes?",
                  "Why does Mara keep the lighthouse alone?",
                  "What does the island mean to Mara?"]
        XCTAssertEqual(page.accepted(qs).count, PageQuestions.count)
    }

    func testFillsUpWithSafeFallbacks() {
        let kept = ["Why does Mara never leave the island?"]
        let all = page.filled(kept, topic: "Mara")
        XCTAssertEqual(all.count, PageQuestions.count)
        XCTAssertEqual(all.first, kept.first)
        XCTAssertEqual(Set(all).count, all.count)                  // no repeats
        for q in all { XCTAssertTrue(page.guardrail.isAcceptable(q, authorText: page.authorText + " Mara"), q) }
    }

    func testFillsWithGeneralQuestionsWithoutATopic() {
        XCTAssertEqual(page.filled([], topic: nil).count, PageQuestions.count)
    }
}
