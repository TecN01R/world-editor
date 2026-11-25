import Foundation
import XCTest
@testable import Guardrails

/// The companion's prompt as the phone renders it, against what llama.cpp renders with the model
final class GemmaChatTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Tool: Decodable {
            struct Parameters: Decodable {
                struct Query: Decodable { let description: String }
                let properties: [String: Query]
            }
            let name: String
            let description: String
            let parameters: Parameters
        }
        struct Message: Decodable {
            struct Call: Decodable {
                struct Function: Decodable { let arguments: String }
                let function: Function
            }
            let role: String
            let content: String
            let reasoning_content: String?
            let tool_calls: [Call]?
        }
        struct Case: Decodable {
            let name: String
            let system: String
            let messages: [Message]
            let tools: Bool
            let thinking: Bool
            let prompt: String
        }
        let tool: Tool
        let cases: [Case]
    }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "gemma4-chat", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// The fixture's messages as the app holds them: the conversation's turns, then the searches
    /// the reply being written has made (an assistant message with a call, and the tool's answer).
    private func render(_ c: Fixture.Case) throws -> String {
        var turns: [CompanionPrompt.Turn] = [], searches: [GemmaChat.Search] = []
        for (i, message) in c.messages.enumerated() {
            switch message.role {
            case "user": turns.append(.init(speaker: .author, text: message.content))
            case "assistant" where message.tool_calls == nil: turns.append(.init(speaker: .companion, text: message.content))
            case "assistant":
                let arguments = try XCTUnwrap(message.tool_calls?.first?.function.arguments)
                let query = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: String])["query"]
                searches.append(GemmaChat.Search(thought: message.reasoning_content ?? "", said: message.content,
                                                 query: query, found: c.messages[i + 1].content))
            default: break   // the tool's answer, taken with its call
            }
        }
        return GemmaChat.prompt(system: c.system, turns: turns, searches: searches, tools: c.tools, thinking: c.thinking)
    }

    func testEveryCaseRendersAsTheModelsTemplateDoes() throws {
        let fixture = try fixture()
        XCTAssertGreaterThan(fixture.cases.count, 8)
        for c in fixture.cases {
            XCTAssertEqual(try render(c), c.prompt, c.name)
        }
    }

    /// The fixture was rendered with search_pages' texts as they are: changing them means
    func testTheFixtureDeclaresSearchPagesAsTheAppDoes() throws {
        let tool = try fixture().tool
        XCTAssertEqual(tool.name, PageLookup.toolName)
        XCTAssertEqual(tool.description, PageLookup.toolDescription)
        XCTAssertEqual(tool.parameters.properties["query"]?.description, PageLookup.queryGuide)
    }

    func testASearchWithoutAQueryIsReplayedWithout() {
        let text = GemmaChat.prompt(system: "S", turns: [.init(speaker: .author, text: "hi")],
                                    searches: [.init(query: nil, found: PageLookup.needsQuery)], tools: true, thinking: true)
        XCTAssertTrue(text.contains("<|tool_call>call:search_pages{}<tool_call|><|tool_response>"))
    }

    // MARK: Reading

    func testAThoughtThenAReply() {
        let output = GemmaChat.read("<|channel>thought\nThey ask who built it.<channel|>Her husband did.")
        XCTAssertEqual(output.thought, "They ask who built it.")
        XCTAssertEqual(output.said, "Her husband did.")
        XCTAssertNil(output.call)
    }

    func testAThoughtSoFarIsAllThought() {
        let output = GemmaChat.read("<|channel>thought\nThey ask who bu")
        XCTAssertEqual(output.thought, "They ask who bu")
        XCTAssertEqual(output.said, "")
    }

    func testWithoutAThoughtItIsAllSaid() {
        XCTAssertEqual(GemmaChat.read(" Hers, then. ").said, "Hers, then.")
    }

    func testASearch() {
        let output = GemmaChat.read("<|channel>thought\nSearch.<channel|><|tool_call>call:search_pages{query:<|\"|>the Regent<|\"|>}<tool_call|>")
        XCTAssertEqual(output.thought, "Search.")
        XCTAssertEqual(output.said, "")
        XCTAssertEqual(output.call?.name, "search_pages")
        XCTAssertEqual(output.call?.query, "the Regent")
        XCTAssertFalse(output.calling)
    }

    /// llama.cpp's parser: a call can begin before the thought is closed.
    func testASearchStraightFromTheThought() {
        let output = GemmaChat.read("<|channel>thought\nLook it up<|tool_call>call:search_pages{query:<|\"|>Regent<|\"|>}<tool_call|>")
        XCTAssertEqual(output.thought, "Look it up")
        XCTAssertEqual(output.call?.query, "Regent")
    }

    func testWordsBeforeASearch() {
        let output = GemmaChat.read("Let me look.<|tool_call>call:search_pages{query:<|\"|>Regent<|\"|>}<tool_call|>")
        XCTAssertEqual(output.said, "Let me look.")
        XCTAssertEqual(output.call?.query, "Regent")
    }

    func testACallBeingWrittenIsNoCallYet() {
        let output = GemmaChat.read("Let me look.<|tool_call>call:search_pa")
        XCTAssertEqual(output.said, "Let me look.")
        XCTAssertNil(output.call)
        XCTAssertTrue(output.calling)
    }

    func testAnUnquotedOrMissingQuery() {
        XCTAssertEqual(GemmaChat.read("<|tool_call>call:search_pages{query:Regent}<tool_call|>").call?.query, "Regent")
        let none = GemmaChat.read("<|tool_call>call:search_pages{}<tool_call|>").call
        XCTAssertEqual(none?.name, "search_pages")
        XCTAssertNil(none?.query)
        XCTAssertEqual(GemmaChat.read("<|tool_call>call:look_up{query:<|\"|>x<|\"|>}<tool_call|>").call?.name, "look_up")
    }

    /// After a search the prompt opens its thought, so what it writes begins inside it.
    func testAfterASearchItBeginsInItsThought() {
        let output = GemmaChat.read("Found it: her husband.<channel|>Her husband built it.", thinking: true)
        XCTAssertEqual(output.thought, "Found it: her husband.")
        XCTAssertEqual(output.said, "Her husband built it.")
    }

    func testEmptyChannelsAndAStrayThoughtAreLeftOut() {
        XCTAssertEqual(GemmaChat.read("<|channel><|channel>thought\nHm.<channel|>Yes.").said, "Yes.")
        XCTAssertEqual(GemmaChat.read("<|channel>thought\nHm.<channel|>Yes.<|channel>thought\n<channel|>").said, "Yes.")
    }

    // MARK: The thinking budget

    private static let open: [Int32] = [100, 45518], close: Int32 = 101, call: Int32 = 48

    private func budget(_ n: Int) -> ThinkingBudget {
        ThinkingBudget(start: Self.open, ends: [[Self.close], [Self.call]], forced: [Self.close], budget: n)
    }

    private func think(_ budget: inout ThinkingBudget, _ tokens: Int, startingAt first: Int32 = 1000) {
        for t in 0..<Int32(tokens) { budget.accept(first + t, completesCharacter: true) }
    }

    func testItForcesTheEndOfAThoughtAfterItsBudget() {
        var b = budget(3)
        b.accept(7, completesCharacter: true)
        XCTAssertEqual(b.state, .idle)
        for token in Self.open { b.accept(token, completesCharacter: true) }
        XCTAssertEqual(b.state, .counting)
        think(&b, 2)
        XCTAssertNil(b.forcedToken)
        think(&b, 1)
        XCTAssertEqual(b.forcedToken, Self.close)
        b.accept(Self.close, completesCharacter: true)
        XCTAssertEqual(b.state, .done)
        XCTAssertNil(b.forcedToken)
    }

    func testAThoughtThatEndsInTimeIsLeftAlone() {
        var b = budget(5)
        for token in Self.open { b.accept(token, completesCharacter: true) }
        think(&b, 2)
        b.accept(Self.call, completesCharacter: true)   // a call can end it too
        XCTAssertEqual(b.state, .done)
        think(&b, 10)
        XCTAssertNil(b.forcedToken)
    }

    /// After a search the prompt ends with the thought opened (and its newline, which counts).
    func testEachThoughtGetsItsOwnBudgetAndThePromptsOpeningCounts() {
        var b = budget(3)
        b.prime(Self.open + [107])
        XCTAssertEqual(b.state, .counting)
        think(&b, 1)
        XCTAssertNil(b.forcedToken)
        think(&b, 1)
        XCTAssertEqual(b.forcedToken, Self.close)
        b.accept(Self.close, completesCharacter: true)
        for token in Self.open { b.accept(token, completesCharacter: true) }
        XCTAssertEqual(b.state, .counting)
        think(&b, 2)
        XCTAssertNil(b.forcedToken)
    }

    func testItFinishesACharacterBeforeForcing() {
        var b = budget(1)
        for token in Self.open { b.accept(token, completesCharacter: true) }
        b.accept(1000, completesCharacter: false)
        XCTAssertEqual(b.state, .finishingCharacter)
        XCTAssertNil(b.forcedToken)
        b.accept(1001, completesCharacter: true)
        XCTAssertEqual(b.forcedToken, Self.close)
    }

    func testWholeCharacters() {
        XCTAssertTrue(ThinkingBudget.completes(Array("abc".utf8)))
        XCTAssertTrue(ThinkingBudget.completes(Array("café".utf8)))
        XCTAssertFalse(ThinkingBudget.completes(Array(Array("é".utf8).prefix(1))))
        XCTAssertFalse(ThinkingBudget.completes(Array(Array("🙂".utf8).prefix(3))))
        XCTAssertTrue(ThinkingBudget.completes(Array("🙂".utf8)))
        XCTAssertTrue(ThinkingBudget.completes([]))
    }
}
