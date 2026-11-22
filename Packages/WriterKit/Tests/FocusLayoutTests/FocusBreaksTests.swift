import XCTest
@testable import FocusLayout

final class FocusBreaksTests: XCTestCase {
    func testLastWordIsTheOneAtTheEnd() {
        XCTAssertEqual(FocusBreaks.lastWordStart("Hey there"), 4)
        XCTAssertEqual(FocusBreaks.lastWordStart("Hey there  "), 4)   // trailing spaces: still "there"
        XCTAssertEqual(FocusBreaks.lastWordStart("Hey"), 0)
        XCTAssertEqual(FocusBreaks.lastWordStart(""), 0)
        XCTAssertEqual(FocusBreaks.lastWordStart("writer’s block."), 9)   // punctuation belongs to the word
    }

    func testCountsInUTF16LikeTextKit() {
        XCTAssertEqual(FocusBreaks.lastWordStart("🙂 hello"), 3)   // the emoji is two UTF-16 units
    }

    func testABreakInsideAnyTokenSplitsIt() {
        XCTAssertTrue(FocusBreaks.splitsWord("hyphenation", at: 6))
        XCTAssertTrue(FocusBreaks.splitsWord("18005551234567", at: 7))   // numbers too
        XCTAssertTrue(FocusBreaks.splitsWord("writer’s", at: 7))        // beside an apostrophe
        XCTAssertTrue(FocusBreaks.splitsWord("a🙂b", at: 3))             // after an emoji, counted whole
    }

    func testBreaksThatAreAllowedAnyway() {
        XCTAssertFalse(FocusBreaks.splitsWord("Hey there", at: 4))     // after the space
        XCTAssertFalse(FocusBreaks.splitsWord("self-made", at: 5))     // after its own hyphen
        XCTAssertFalse(FocusBreaks.splitsWord("either/or", at: 7))     // after a slash
        XCTAssertFalse(FocusBreaks.splitsWord("你好世界", at: 2))        // Chinese breaks anywhere
        XCTAssertFalse(FocusBreaks.splitsWord("こんにちは", at: 2))      // and Japanese
        XCTAssertFalse(FocusBreaks.splitsWord("Hey", at: 0))
        XCTAssertFalse(FocusBreaks.splitsWord("Hey", at: 3))
    }
}
