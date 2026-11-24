import XCTest
@testable import Guardrails

/// What counts as stating something, for filing (and whether to ask the model at all).
final class StatesTests: XCTestCase {
    func testStatementsGuessesAndQuestions() {
        for stated in ["Her name is Florica", "I think it was actually a bireme", "Actually, I think it was a bireme"] {
            XCTAssertTrue(Filer.states(stated), stated)
        }
        for unsure in ["Is her name Florica?", "Maybe a bireme", "I think it was a bireme",
                       "I'm not really sure, actually it was a bireme", "Not 100% sure, a bireme",
                       "I guess a bireme", "Can't remember, a bireme"] {
            XCTAssertFalse(Filer.states(unsure), unsure)
        }
    }
}
