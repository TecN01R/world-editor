import XCTest
@testable import WriterCore

final class TypesetTests: XCTestCase {
    func testDoubleQuotesOpenAndCloseByWhereTheyStand() {
        XCTAssertEqual(Typeset.printed(#""Go," she said. "Now.""#), "\u{201C}Go,\u{201D} she said. \u{201C}Now.\u{201D}")
        XCTAssertEqual(Typeset.printed(#"("quoted")"#), "(\u{201C}quoted\u{201D})")
        XCTAssertEqual(Typeset.printed(#"She said "hi"."#), "She said \u{201C}hi\u{201D}.")
    }

    func testSingleQuotesAndApostrophes() {
        XCTAssertEqual(Typeset.printed("Mira's road, don't"), "Mira\u{2019}s road, don\u{2019}t")
        XCTAssertEqual(Typeset.printed("the boys' ships"), "the boys\u{2019} ships")
        XCTAssertEqual(Typeset.printed("'Hello,' she said"), "\u{2018}Hello,\u{2019} she said")
        XCTAssertEqual(Typeset.printed("in the '90s"), "in the \u{2019}90s")
        XCTAssertEqual(Typeset.printed(#""'Tis so""#), "\u{201C}\u{2018}Tis so\u{201D}")
    }

    func testDashesAndEllipses() {
        XCTAssertEqual(Typeset.printed("wait--what"), "wait\u{2014}what")
        XCTAssertEqual(Typeset.printed("wait---what"), "wait\u{2014}what")
        XCTAssertEqual(Typeset.printed("well-known ----"), "well-known ----")   // a hyphen, and a rule, stay
        XCTAssertEqual(Typeset.printed("So... and. Then...."), "So\u{2026} and. Then\u{2026}.")
    }

    func testQuotesBesideADashOpenOrCloseByWhatFollows() {
        XCTAssertEqual(Typeset.printed(#""Wait--" He went--"Go!""#),
                       "\u{201C}Wait\u{2014}\u{201D} He went\u{2014}\u{201C}Go!\u{201D}")
    }

    func testChangesAreUTF16RangesOfTheTextAsTyped() {
        let text = "\u{1F30A} \"Sea\"--far..."   // an emoji takes two UTF-16 units
        XCTAssertEqual(Typeset.changes(in: text), [
            Typeset.Change(range: 3..<4, replacement: "\u{201C}"),
            Typeset.Change(range: 7..<8, replacement: "\u{201D}"),
            Typeset.Change(range: 8..<10, replacement: "\u{2014}"),
            Typeset.Change(range: 13..<16, replacement: "\u{2026}"),
        ])
        XCTAssertEqual(Typeset.printed(text), "\u{1F30A} \u{201C}Sea\u{201D}\u{2014}far\u{2026}")
    }

    func testPlainTextIsUnchanged() {
        XCTAssertEqual(Typeset.printed("Plain words, nothing to set."), "Plain words, nothing to set.")
        XCTAssertEqual(Typeset.changes(in: ""), [])
    }
}
