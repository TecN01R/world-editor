import Foundation
import XCTest
@testable import Guardrails
import WriterCore

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

    func testTheCheckAcceptsTidyingAndRefusesAnyOtherWord() {
        let message = "no, she's free. she's a professional rower"
        XCTAssertTrue(HisWords.sameWords(HisWords.tidied(message), message))
        XCTAssertFalse(HisWords.sameWords("No, Casperica is free.", "no, she's free"))
        XCTAssertFalse(HisWords.sameWords("She is free.", "she's free"))
    }

    // MARK: Where a sentence fits

    private let bram = Document(title: "Bram", paragraphs: [
        Paragraph(text: "Bram grew up in Holm, by the sea."),
        Paragraph(text: "At twelve the Iron Abbey took him in."),
        Paragraph(text: "The Iron Abbey's bells", kind: .bullet),
    ])

    func testASentenceFitsTheParagraphAboutTheSameThing() {
        XCTAssertEqual(HisWords.fit("He trained at the Iron Abbey for years.", in: bram), bram.paragraphs[1].id)
        XCTAssertEqual(HisWords.fit("He went back to Holm.", in: bram), bram.paragraphs[0].id)   // a name
    }

    func testItTakesTwoWordsOrANameAndNotThePagesOwn() {
        XCTAssertNil(HisWords.fit("He loves the sea.", in: bram))   // one ordinary word
        XCTAssertNil(HisWords.fit("Bram is tall.", in: bram))   // the page's own name is everywhere
        XCTAssertNil(HisWords.fit("He has a dog.", in: bram))
    }

    func testListsAreLeftAlone() {
        let page = Document(title: "Bram", paragraphs: [Paragraph(text: "The Iron Abbey's bells", kind: .bullet)])
        XCTAssertNil(HisWords.fit("He rang the Iron Abbey's bells.", in: page))
    }

    func testStemsMeetAcrossForms() {
        XCTAssertEqual(HisWords.stems("trained training trains"), ["train", "train", "train"])
        XCTAssertEqual(HisWords.stems("Abbey's bells"), ["abbey", "bell"])
    }
}
