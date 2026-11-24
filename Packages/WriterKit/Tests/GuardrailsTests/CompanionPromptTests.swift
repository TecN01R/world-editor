import XCTest
@testable import Guardrails
import WriterCore

final class CompanionPromptTests: XCTestCase {
    let ilsa = CompanionPrompt.Page(name: "Ilsa", type: "Character", writing: "A maritime adventurer")
    let verran = CompanionPrompt.Page(name: "Verran", type: "Place", writing: "A seafaring nation\nof rowers and traders")

    private func talk(_ turns: (String, String?)...) -> Conversation {
        var talk = Conversation(page: UUID())
        for (reply, answer) in turns {
            talk.ask(reply)
            if let answer { talk.answer(answer) }
        }
        return talk
    }

    /// The system turn: who it is, the examples, the background, and (as the
    func testASystemTurnWithEverythingInOrder() {
        let prompt = CompanionPrompt(page: ilsa, others: [verran], conversation: Conversation(page: UUID()))
        XCTAssertEqual(prompt.system, [
            CompanionPrompt.instructions,
            CompanionPrompt.examples,
            """
            What the app shows you of the writer's pages (for reference; the writer didn't just say this):

            Their other pages:
            - Verran (Place): A seafaring nation of rowers and traders

            The page they have open now:
            \u{201C}Ilsa\u{201D}, a character: Ilsa is who or what this page is about, and the title is Ilsa's name.
            What they've written on it so far:
            A maritime adventurer
            """,
            "Right now: the writer has just opened this page and hasn't said anything yet. Tell them what you make of it "
                + "and how it sits with their other pages. If something on it could be read two ways, ask which they mean.",
        ].joined(separator: "\n\n"))
        XCTAssertEqual(prompt.turns, [.init(speaker: .author, text: "(I've just opened this page.)")])
    }

    /// The conversation goes to the model as turns, so it knows who said what
    /// and what it's replying to; once it's under way, nothing says what to do first.
    func testTheConversationTurnByTurn() {
        let prompt = CompanionPrompt(page: ilsa, conversation: talk(("Is \u{201C}maritime\u{201D} trade, or war?", "trade. she rows")))
        XCTAssertEqual(prompt.turns.map(\.speaker), [.author, .companion, .author])
        XCTAssertEqual(prompt.turns.map(\.text), ["(I've just opened this page.)", "Is \u{201C}maritime\u{201D} trade, or war?", "trade. she rows"])
        XCTAssertFalse(prompt.system.contains("Right now:"))
        XCTAssertTrue(prompt.system.hasSuffix("A maritime adventurer"))
        XCTAssertTrue(prompt.flattened.hasSuffix("You: Is \u{201C}maritime\u{201D} trade, or war?\nWriter: trade. she rows\n\nReply to the writer's last message."))
    }

    /// The plain model (Kevin's trial): only the conversation, nothing of the app's.
    func testThePlainModelGetsOnlyTheConversation() {
        let prompt = CompanionPrompt.plain(talk(("Is \u{201C}maritime\u{201D} trade, or war?", "trade. she rows")))
        XCTAssertEqual(prompt.system, "")
        XCTAssertEqual(prompt.turns.map(\.speaker), [.companion, .author])
        XCTAssertEqual(prompt.turns.map(\.text), ["Is \u{201C}maritime\u{201D} trade, or war?", "trade. she rows"])
        // Before its first reply it has to answer something.
        XCTAssertEqual(CompanionPrompt.plain(Conversation(page: UUID())).turns.map(\.text), [CompanionPrompt.opened])
    }

    func testWhatToDoFirstFitsThePage() {
        func first(_ page: CompanionPrompt.Page, others: [CompanionPrompt.Page] = []) -> String {
            let system = CompanionPrompt(page: page, others: others, conversation: Conversation(page: UUID())).system
            return String(system[system.range(of: "Right now:")!.lowerBound...])
        }
        XCTAssertTrue(first(.init(name: "", writing: "")).contains("opened a blank page"))
        XCTAssertTrue(first(.init(name: "Ilsa", writing: "")).contains("opened a blank page"))                 // a title alone is still blank
        XCTAssertTrue(first(.init(name: "Ilsa", fields: "Home: Verran", writing: "")).contains("what you make of it"))
        // The first page of a new world has no other pages to sit with.
        XCTAssertFalse(first(ilsa).contains("other pages"))
        XCTAssertTrue(first(ilsa, others: [verran]).contains("how it sits with their other pages"))
        // A page with a lot on it: one thing picked out, not a summary.
        let full = CompanionPrompt.Page(name: "Mara", writing: String(repeating: "She keeps the light. ", count: 30))
        XCTAssertTrue(first(full, others: [verran]).contains("don't sum it up. Pick the one thing"))
    }

    func testDescribesThePage() {
        XCTAssertEqual(CompanionPrompt.describe(.init(name: "", writing: ""), maxCharacters: 100),
                       "A page with no title yet.\nNothing is written on it yet.")
        XCTAssertEqual(CompanionPrompt.describe(.init(name: "The Storm", type: "Event", fields: "When: autumn", writing: "Four days."), maxCharacters: 100),
                       "\u{201C}The Storm\u{201D}, an event: The Storm is who or what this page is about, and the title is The Storm's name.\n"
                       + "Its fields:\nWhen: autumn\nWhat they've written on it so far:\nFour days.")
        XCTAssertTrue(CompanionPrompt.describe(.init(name: "Hal", type: "AI", writing: ""), maxCharacters: 100).hasPrefix("\u{201C}Hal\u{201D}, an AI:"))
        XCTAssertTrue(CompanionPrompt.describe(.init(name: "", type: "Place", writing: ""), maxCharacters: 100).hasPrefix("A Place page with no title yet."))
        XCTAssertTrue(CompanionPrompt.describe(.init(name: "App ideas", writing: "x"), maxCharacters: 100)
            .hasPrefix("\u{201C}App ideas\u{201D}: the title is the name of who or what this page is about."))
    }

    /// A page too long to show whole: how it opens and where the author is working.
    func testALongPageIsItsOpeningAndItsLatestPart() {
        let writing = "It began in Halen. " + String(repeating: "middle ", count: 2000) + "He stops counting at forty."
        let prompt = CompanionPrompt(page: .init(name: "The Night of Water", writing: writing),
                                     conversation: Conversation(page: UUID()), maxCharacters: 800)
        let page = String(prompt.system[prompt.system.range(of: "The page they have open now:")!.lowerBound...])
        XCTAssertTrue(page.contains("(it's long: this is how it opens and, after [\u{2026}], its latest part):\nIt began in Halen. middle"))
        XCTAssertTrue(page.contains("middle\n[\u{2026}]\nmiddle"))                         // cut at words, not through them
        XCTAssertTrue(page.contains("He stops counting at forty.\n\nRight now:"))
        XCTAssertLessThan(page.distance(from: page.startIndex, to: page.range(of: "\n\nRight now:")!.lowerBound), 1100)
        XCTAssertNil(CompanionPrompt.excerpt("short", maxCharacters: 5))
    }

    func testTheWorldIsItsRelatedPagesFirst() {
        let pages: [CompanionPrompt.Page] = [
            .init(name: "My World", writing: "The text scales to fill the screen in Focus mode"),
            .init(name: "", writing: ""),                                           // nothing to show: left out
            .init(name: "", writing: "Salt, rope and gossip"),
            .init(name: "Mara", type: "Character", writing: ""),
            verran,
        ]
        XCTAssertEqual(CompanionPrompt.worldSummary(pages, focus: "Ilsa\nA maritime adventurer\nShe's a rower from Verran"), """
            - Verran (Place): A seafaring nation of rowers and traders
            - My World: The text scales to fill the screen in Focus mode
            - Untitled: Salt, rope and gossip
            - Mara (Character)
            """)                                                                    // related first; the rest as they were
        let long = CompanionPrompt.worldSummary([.init(name: "Mara", writing: String(repeating: "lighthouse ", count: 50))], focus: "")
        XCTAssertLessThan(long.count, 180)                                          // openings are cut short
        // A big world is cut down to what fits, the related pages first; once openings don't
        // fit, pages are still named while there's room (a review, 2026-11-24: names were lost).
        XCTAssertEqual(CompanionPrompt.worldSummary(pages, focus: "Verran", maxCharacters: 70),
                       "- Verran (Place): A seafaring nation of rowers and traders\n- My World")
        XCTAssertEqual(CompanionPrompt.worldSummary(pages, focus: "", maxCharacters: 2), "")
    }

    /// Fields show beside a page's name in the world's list.
    func testTheWorldShowsFields() {
        let mara = CompanionPrompt.Page(name: "Mara", type: "Character", fields: "Species: Selkie\nAge: 61", writing: "Keeps the lighthouse.")
        XCTAssertEqual(CompanionPrompt.worldSummary([mara], focus: ""),
                       "- Mara (Character) [Species: Selkie; Age: 61]: Keeps the lighthouse.")
    }

    func testRemembersWhatTheAuthorSaidElsewhere() {
        let mara = talk(("Why does Mara stay?", "She promised her mother")), waiting = talk(("What is this page about?", nil))
        let earlier = [(page: "Mara", conversation: mara), (page: "", conversation: waiting)]
        XCTAssertEqual(CompanionPrompt.memory(earlier, focus: "Tomas writes to his sister Mara"),
                       "- On their page \u{201C}Mara\u{201D}, you said \u{201C}Why does Mara stay?\u{201D} and the writer replied: \u{201C}She promised her mother\u{201D}")
        XCTAssertEqual(CompanionPrompt.memory(earlier, focus: "The trireme"), "")   // unrelated: left out
        // Its own earlier words only place theirs: one line, cut short.
        let long = talk((String(repeating: "Hey! That sounds great.\n\n", count: 20), "Mara\nstays"))
        let line = CompanionPrompt.memory([(page: "Mara", conversation: long)], focus: "Mara")
        XCTAssertTrue(line.hasSuffix("\u{2026}\u{201D} and the writer replied: \u{201C}Mara stays\u{201D}"))
        XCTAssertFalse(line.contains("\n"))
        XCTAssertLessThan(line.count, 260)
        let prompt = CompanionPrompt(page: .init(name: "Tomas", writing: "He writes to his sister Mara."), earlier: earlier,
                                     conversation: Conversation(page: UUID()))
        XCTAssertTrue(prompt.system.contains("\n\nFrom your earlier conversations:\n- On their page \u{201C}Mara\u{201D}, you said"))
    }

    /// A world conversation remembered elsewhere: worded as one, and a turn the writer began
    /// has nothing of the companion's before it.
    func testMemoryOfAWorldConversationTheWriterBegan() {
        var world = Conversation(page: UUID(), aboutWorld: true)
        world.answer("Mara keeps the lighthouse at Verran")
        let memory = CompanionPrompt.memory([(page: "", conversation: world)], focus: "Mara")
        XCTAssertEqual(memory, "- In a conversation about their whole world, the writer said: \u{201C}Mara keeps the lighthouse at Verran\u{201D}")
    }

    /// A long conversation keeps its newest exchanges, within a count and a length.
    func testALongConversationKeepsItsNewestTurns() {
        var long = Conversation(page: UUID())
        for i in 1...20 { long.ask("reply \(i)"); long.answer("message \(i)") }
        let prompt = CompanionPrompt(page: ilsa, conversation: long)
        XCTAssertEqual(prompt.turns.count, 1 + 12 * 2)
        XCTAssertEqual(prompt.turns.first?.text, CompanionPrompt.opened)
        XCTAssertEqual(prompt.turns[1].text, "reply 9")
        XCTAssertEqual(prompt.turns.last, .init(speaker: .author, text: "message 20"))
        let tight = CompanionPrompt(page: ilsa, conversation: long, maxTurnCharacters: 40)
        XCTAssertEqual(tight.turns.map(\.text), [CompanionPrompt.opened, "reply 19", "message 19", "reply 20", "message 20"])
        // One message longer than everything allowed is still answered: its opening and its end.
        let pasted = talk(("Go on.", "It began. " + String(repeating: "word ", count: 500) + "The end."))
        let cut = CompanionPrompt(page: ilsa, conversation: pasted, maxTurnCharacters: 200).turns.last!.text
        XCTAssertTrue(cut.hasPrefix("It began.") && cut.hasSuffix("The end.") && cut.contains("\n[\u{2026}]\n"))
        XCTAssertLessThan(cut.count, 220)
    }

    func testKeywordsAreWhatATextIsAbout() {
        XCTAssertEqual(CompanionPrompt.keywords("She\u{2019}s a rower from Verran; what does Verran's navy want?"), ["rower", "verran", "navy"])
    }
}

final class ConversationTests: XCTestCase {
    func testOneWaitingQuestionAtATime() {
        var talk = Conversation(page: UUID())
        talk.ask("What does Ilsa want?")
        talk.ask("Why?")                                   // ignored: one is waiting
        XCTAssertEqual(talk.turns.count, 1)
        talk.answer("  ")                                  // blank answers don't count
        XCTAssertNotNil(talk.waiting)
        talk.answer("The drowned city")
        XCTAssertNil(talk.waiting)
        XCTAssertEqual(talk.authorText, "The drowned city")
    }

    func testListsEveryConversation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("talk-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ConversationStore(directory: dir)
        for _ in 0..<2 { try store.save(Conversation(page: UUID())) }
        XCTAssertEqual(store.all().count, 2)
    }

    func testSavesAndLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("talk-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ConversationStore(directory: dir)
        var talk = Conversation(page: UUID())
        talk.ask("What does Ilsa want?")
        try store.save(talk)
        XCTAssertEqual(store.load(talk.page), talk)
        XCTAssertEqual(store.load(UUID()).turns, [])
    }
}
