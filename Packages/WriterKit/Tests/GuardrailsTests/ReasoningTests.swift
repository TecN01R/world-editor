import XCTest
@testable import Guardrails

final class ReasoningTests: XCTestCase {
    func testWithoutThinkingItIsAllReply() {
        XCTAssertEqual(Reasoned.gemma(" Got it, a rower. "), Reasoned(reply: "Got it, a rower."))
    }

    func testThinkingThenReply() {
        let output = "<|channel>thought\nThey said she rows.\nAsk about that.<channel|>So she rows for a living?"
        XCTAssertEqual(Reasoned.gemma(output),
                       Reasoned(reasoning: "They said she rows.\nAsk about that.", reply: "So she rows for a living?"))
    }

    func testWhileStillThinkingThereIsNoReplyYet() {
        XCTAssertEqual(Reasoned.gemma("<|channel>thought\nThey said she ro"), Reasoned(reasoning: "They said she ro", reply: ""))
        XCTAssertEqual(Reasoned.gemma("<|channel>"), Reasoned(reasoning: "", reply: ""))
    }

    func testAnEmptyThoughtLeavesTheReply() {
        XCTAssertEqual(Reasoned.gemma("<|channel>thought\n<channel|>Hello"), Reasoned(reasoning: "", reply: "Hello"))
    }
}
