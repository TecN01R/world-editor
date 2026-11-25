import Foundation
import XCTest
@testable import Guardrails
import WriterCore

/// The writer's standing instructions (`Instructions`): blank at first, what the prompt shows,
/// and the model adding one with `add_instruction` when told how to reply from now on.
final class InstructionsTests: XCTestCase {
    func testTheyAreShownUnderWhoseTheyAreAndAddedALineAtATime() {
        XCTAssertNil(Instructions.shown(nil))
        XCTAssertNil(Instructions.shown(" \n"))
        XCTAssertEqual(Instructions.shown("Be brief.\n"), "The writer's instructions for you:\nBe brief.")
        XCTAssertEqual(Instructions.adding(["Don't suggest names."], to: nil), "Don't suggest names.")
        XCTAssertEqual(Instructions.adding(["Don't suggest names.", "No lists."], to: "Be brief.\n"),
                       "Be brief.\nDon't suggest names.\nNo lists.")
    }

    func testTheModelAddsThemWhenOffered() async {
        var tools = ReplyTools(pages: nil, lookingUp: false, instructing: true)
        XCTAssertEqual(tools.offered.map(\.name), [Instructions.toolName])
        let noLookUp: (String) async throws -> (text: String, found: LookedUp) = { _ in throw URLError(.badURL) }
        let empty = await tools.answer(Instructions.toolName, query: " ", lookUp: noLookUp)
        XCTAssertEqual(empty, Instructions.needsInstruction)
        let first = await tools.answer(Instructions.toolName, query: " Don't suggest names unless they ask. ", lookUp: noLookUp)
        XCTAssertEqual(first, Instructions.added)
        _ = await tools.answer(Instructions.toolName, query: "Keep it short.", lookUp: noLookUp)
        _ = await tools.answer(Instructions.toolName, query: "No lists.", lookUp: noLookUp)
        XCTAssertEqual(tools.instructions, ["Don't suggest names unless they ask.", "Keep it short.", "No lists."])
        var off = ReplyTools(pages: nil, lookingUp: false)
        let missing = await off.answer(Instructions.toolName, query: "Keep it short.", lookUp: noLookUp)
        XCTAssertEqual(missing, "Tool not found: \(Instructions.toolName)")
    }

    /// Declared with its own argument, read back whatever the argument is called, and replayed
    /// with it.
    func testItsCallIsDeclaredReadAndReplayedWithItsArgument() {
        XCTAssertTrue(GemmaChat.addInstruction.declaration.contains("properties:{instruction:{description:"))
        XCTAssertTrue(GemmaChat.searchPages.declaration.contains("properties:{query:{description:"))
        let raw = "<|tool_call>call:add_instruction{instruction:<|\"|>Keep it short.<|\"|>}<tool_call|>"
        let call = GemmaChat.read(raw, thinking: false).call
        XCTAssertEqual(call?.name, Instructions.toolName)
        XCTAssertEqual(call?.query, "Keep it short.")
        let prompt = GemmaChat.prompt(system: "", turns: [.init(speaker: .author, text: "keep it short from now on")],
                                      searches: [.init(tool: Instructions.toolName, query: "Keep it short.", found: Instructions.added)],
                                      tools: [GemmaChat.addInstruction], thinking: false)
        XCTAssertTrue(prompt.contains(raw + "<|tool_response>response:add_instruction{value:"))
    }
}
