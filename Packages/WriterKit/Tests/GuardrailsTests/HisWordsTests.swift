import Foundation
import XCTest
@testable import Guardrails

/// The author's words as they go into a page: capitalisation, punctuation and spacing
/// tidied, and nothing else (`HisWords`).
final class HisWordsTests: XCTestCase {
    func testOnlyCaseAndPunctuationAreTidied() {
        XCTAssertEqual(HisWords.tidied("she rows for the fleet"), "She rows for the fleet.")
        XCTAssertEqual(HisWords.tidied("no, she's free.  she's a professional rower"),
                       "No, she's free. She's a professional rower.")
        XCTAssertEqual(HisWords.tidied("i think i'm right , it's a bireme !"), "I think I'm right, it's a bireme!")
        XCTAssertEqual(HisWords.tidied("\"the sky split.\" then nothing"), "\"The sky split.\" Then nothing.")
        XCTAssertEqual(HisWords.tidied("is it a confederacy?"), "Is it a confederacy?")
        XCTAssertEqual(HisWords.tidied("Myriddea has no emperor (yet)"), "Myriddea has no emperor (yet)")
    }

    func testMisspellingsAndInventedNamesStayAsWritten() {
        XCTAssertEqual(HisWords.tidied("olfnark teh glassblower"), "Olfnark teh glassblower.")
    }

    func testEachLineIsAParagraphAndBlankLinesGo() {
        XCTAssertEqual(HisWords.paragraphs("she rows\n\nshe is free\n"), ["She rows.", "She is free."])
        XCTAssertEqual(HisWords.paragraphs("  \n"), [])
    }

    func testTheCheckAcceptsTidyingAndRefusesAnyOtherWord() {
        let message = "no, she's free. she's a professional rower"
        XCTAssertTrue(HisWords.sameWords(HisWords.paragraphs(message).joined(separator: "\n"), message))
        XCTAssertFalse(HisWords.sameWords("No, Casperica is free.", "no, she's free"))
        XCTAssertFalse(HisWords.sameWords("She is free.", "she's free"))
    }
}
