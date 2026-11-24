import XCTest
@testable import Guardrails

final class ReasoningTests: XCTestCase {
    func testWithoutThinkingItIsAllReply() {
        XCTAssertEqual(Reasoned.gemma(" Got it, a rower. "), Reasoned(reply: "Got it, a rower."))
    }

    /// A search, before any words of the reply: what the "Searching your pages" line shows.
    func testASearchBeforeTheReply() {
        let searching = Reasoned(searches: ["Kestrel"])
        XCTAssertEqual(searching.reply, "")
        XCTAssertEqual(searching.searches, ["Kestrel"])
        XCTAssertEqual(Reasoned.gemma("Hi").searches, [])
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

    /// Gemma 4's control tokens (its GGUF's vocabulary) and llama.cpp's image marker.
    func testTheAuthorsWordsAreNeverControlTokens() {
        let tokens = ["<pad>", "<bos>", "<eos>", "<unk>", "<mask>", "<|tool>", "<tool|>", "<|think|>", "<|turn>", "<turn|>",
                      "<|image>", "<|audio>", "<|image|>", "<|audio|>", "<image|>", "<audio|>", "<|video|>",
                      "<|tool_call>", "<tool_call|>", "<|tool_response>", "<tool_response|>", "<|\"|>", "<|channel>", "<channel|>",
                      "<__media__>"]
        let page = "Notes on chat formats: " + tokens.joined(separator: " then ")
        let plain = Reasoned.gemmaPlain(page)
        for token in tokens { XCTAssertFalse(plain.contains(token), token) }
        XCTAssertEqual(plain.replacingOccurrences(of: "\u{200B}", with: ""), page)   // nothing else changes
    }

    func testOrdinaryWritingIsLeftAlone() {
        for text in ["She rows for a living.", "2 < 3 and 5 > 4", "a <b>bold</b> claim | or not", "x |> f", ""] {
            XCTAssertEqual(Reasoned.gemmaPlain(text).replacingOccurrences(of: "\u{200B}", with: ""), text)
        }
        XCTAssertEqual(Reasoned.gemmaPlain("She rows for a living."), "She rows for a living.")
        XCTAssertEqual(Reasoned.gemmaPlain("2 < 3 and 5 > 4"), "2 < 3 and 5 > 4")
    }
}
