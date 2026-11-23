import XCTest
@testable import Guardrails
import WriterCore

final class InterviewerTests: XCTestCase {
    let page = "Ilsa\nA maritime adventurer"
    /// The page and the author's answers in the conversation Kevin judged (2026-11-22).
    let talk = "Ilsa\nA maritime adventurer\nI suppose she's less of an adventurer and more of just a rower for a trade trireme to start\nThat's a boat..."
    let mara = "Mara\nMara keeps the lighthouse alone. She never leaves the island, even when her brother Tomas writes."

    func testKeepsASimpleQuestionInTheAuthorsWords() {
        XCTAssertEqual(Interviewer.screen("What does Ilsa want?", authorText: page), "What does Ilsa want?")
    }

    func testTidiesLabelsAndQuotes() {
        XCTAssertEqual(Interviewer.screen("Question: \u{201C}What does Ilsa want?\u{201D}", authorText: page),
                       "What does Ilsa want?")
        // A quote that ends the reply is the author's word, not wrapping.
        XCTAssertEqual(Interviewer.screen("You called Ilsa \"a maritime adventurer\"", authorText: page),
                       "You called Ilsa \"a maritime adventurer\"")
    }

    /// Replies Kevin called fine: an editor reacting, reasoning and asking.
    func testKeepsWhatAnEditorWouldSay() {
        for reply in [
            "You stopped there because a boat cannot want anything, yet you asked what the trireme wants from her. Why should a vessel have needs at all?",
            "So she's starting as a hired rower rather than a captain or explorer. What does that mean for her long-term goals?",
            "Who commands the trireme?",
            "A rower doesn't choose where the trireme goes. Does that bother Ilsa?",
        ] {
            XCTAssertEqual(Interviewer.screen(reply, authorText: talk), reply)
        }
        XCTAssertNotNil(Interviewer.screen("Mara never leaves, even for Tomas. Something doesn't add up there; why does she stay?", authorText: mara))
    }

    /// Replies Kevin called not fine: prose, suggestions, choices, inventions.
    func testRejectsWhatANovelistWouldWrite() {
        for reply in [
            "It sounds like a cage she built for herself. Why does Mara stay?",
            "The silence there must be heavier than the water. What does Mara hear at night?",
            "Mara's loneliness feels almost physical. When did it start?",
            "What if Tomas comes to the island?",
            "Maybe Mara is afraid of the mainland. Is she?",
            "Does Mara's keeper, Elias, ever visit?",
        ] {
            XCTAssertNil(Interviewer.screen(reply, authorText: mara), reply)
        }
    }

    /// Kevin: too loaded to help; it should poke at the story, not its meaning.
    func testRejectsALiteraryReviewersQuestions() {
        for reply in [
            "What does the lighthouse symbolize for Mara?",
            "What themes are you exploring with Mara's isolation?",
            "The island seems to stand for her grief. Why does she stay?",
            "Is the lighthouse a metaphor for Mara herself?",
        ] {
            XCTAssertNil(Interviewer.screen(reply, authorText: mara), reply)
        }
    }

    /// Kevin: opinions are conversational, so long as they invent nothing.
    func testKeepsTheEditorsOwnOpinions() {
        for reply in [
            "I think the letters from Tomas are the most interesting part, because Mara never answers them. Why not?",
            "I feel the page wants to know what Mara does all day. What does keeping the lighthouse involve?",
            "I'm not sure a rower would call herself an adventurer. What made you write that first?",
        ] {
            XCTAssertNotNil(Interviewer.screen(reply, authorText: mara + "\n" + talk), reply)
        }
        XCTAssertNil(Interviewer.screen("I think Mara stays because of Elias.", authorText: mara))   // still no inventions
    }

    /// What the candidate models said in conversation (2026-11-22): everyday
    /// talk the check used to mistake for prose, suggestions or names.
    func testEverydayTalkPasses() {
        for reply in [
            "That sounds like a great start for a character in Verran! What kind of adventures has Ilsa been looking for?",
            "Got it, Ilsa sounds like a really cool name for a main character.",
            "Got it, I'll back off on the details. What does this adventurer feel most excited about?",
            "Got it, let me try again. What's the core of Ilsa's story?",
            "Ah, got it! Ilsa is the adventurer, not the place. That makes more sense. Where does Ilsa sail from?",
        ] {
            XCTAssertNotNil(Interviewer.screen(reply, authorText: talk + "\nVerran"), reply)
        }
        XCTAssertNil(Interviewer.screen("This feels like a blank canvas waiting for the first brushstroke.", authorText: talk))
        XCTAssertNil(Interviewer.screen("Ilsa rows like a ghost through the fog.", authorText: talk))
    }

    /// Kevin: open either-or questions up, flag them, and tighten later.
    func testChoicesPassButAreFlagged() {
        for reply in [
            "Does Ilsa have a captain, or does she row for someone else?",
            "What kind of water is it\u{2014}open sea, river, enclosed bay\u{2014}and how does that shape the trireme?",
        ] {
            XCTAssertEqual(Interviewer.screen(reply, authorText: talk), reply)
            XCTAssertTrue(CompanionGuard.offersChoices(reply), reply)
        }
        XCTAssertFalse(CompanionGuard.offersChoices("Who commands the trireme?"))
    }

    func testRejectsRefusals() {
        XCTAssertNil(Interviewer.screen("I'm sorry, but I can't write a story about Ilsa without knowing more. Who is she?", authorText: talk))
        XCTAssertNil(Interviewer.screen("I can\u{2019}t help with that.", authorText: talk))
    }

    func testTheAuthorsOwnImageMayBeTalkedAbout() {
        let caged = mara + "\nThe lighthouse is a cage."
        XCTAssertNotNil(Interviewer.screen("You called the lighthouse a cage. Who locked it?", authorText: caged))
    }

    func testRejectsAssumedGenderUnlessTheAuthorUsedIt() {
        XCTAssertNil(Interviewer.screen("What does she want?", authorText: page))
        XCTAssertEqual(Interviewer.screen("What does she want?", authorText: page + "\nShe sails alone."), "What does she want?")
    }

    /// Apple's model on the Duo (2026-11-22): a pile of questions.
    func testOneQuestionAtATime() {
        XCTAssertEqual(Interviewer.screen("You said triremes go on oceans. Where does the trireme start? What's the first thing they touch?", authorText: talk),
                       "You said triremes go on oceans. Where does the trireme start?")   // kept up to its first question
        XCTAssertNotNil(Interviewer.screen("Mostly, yes: triremes kept close to the coast. Where does Ilsa's trireme trade?", authorText: talk))
    }

    func testThreeShortSentencesAtMost() {
        XCTAssertNotNil(Interviewer.screen("Ilsa rows. That's work, not adventure. Why the change?", authorText: talk))
        XCTAssertNil(Interviewer.screen("Ilsa rows for a trade trireme. That is hard work every day. It is not much of an adventure. Why did you change it?", authorText: talk))
    }

    /// The conversation goes to the model as turns, so it knows who said
    /// what and what it's replying to.
    func testThePromptIsTheConversationTurnByTurn() {
        var talk = Conversation(page: UUID())
        talk.ask("What does Ilsa want?")
        talk.answer("To find the drowned city")
        let prompt = Interviewer.prompt(title: "Ilsa", type: "Character", fields: "", writing: "A maritime adventurer",
                                        conversation: talk)
        XCTAssertEqual(prompt.turns.map(\.speaker), [.author, .companion, .author])
        XCTAssertEqual(prompt.turns[0].text, "I\u{2019}m on a Character page titled \u{201C}Ilsa\u{201D}.\n\nWhat I\u{2019}ve written there:\nA maritime adventurer"
            .replacingOccurrences(of: "\u{2019}", with: "'"))
        XCTAssertEqual(prompt.turns.last?.text, "To find the drowned city")
        XCTAssertTrue(prompt.flattened.hasSuffix("You: What does Ilsa want?\nThem: To find the drowned city\n\nReply to their last message."))
        let long = Interviewer.prompt(title: "", fields: "", writing: String(repeating: "x", count: 10_000) + "END",
                                      conversation: Conversation(page: UUID()), maxCharacters: 500)
        XCTAssertTrue(long.flattened.hasSuffix("END"))                    // the newest writing is kept
        XCTAssertLessThan(long.flattened.count, 600)
    }

    func testThePromptHoldsTheRestOfTheWorld() {
        let world = Interviewer.worldSummary([
            (name: "My World", type: nil, writing: "The text scales to fill the screen in Focus mode"),
            (name: "", type: nil, writing: ""),                                    // nothing written: left out
            (name: "Verran", type: "Place", writing: "A seafaring nation\nof rowers and traders"),
        ], focus: "Ilsa\nA maritime adventurer\nShe's a rower from Verran")
        XCTAssertEqual(world, """
            - Verran (Place): A seafaring nation of rowers and traders
            - My World
            """)                                                            // related first; the rest by name
        let prompt = Interviewer.prompt(title: "Ilsa", fields: "", writing: "A maritime adventurer",
                                        world: world, conversation: Conversation(page: UUID()))
        XCTAssertTrue(prompt.flattened.hasPrefix("Other pages in this world:\n- Verran"))
        let long = Interviewer.worldSummary([(name: "Mara", type: nil, writing: String(repeating: "lighthouse ", count: 50))],
                                            focus: "lighthouse")
        XCTAssertLessThan(long.count, 180)                                    // openings are cut short
        XCTAssertTrue(Interviewer.worldSummary([(name: "A", type: nil, writing: "long")], focus: "", maxCharacters: 2).isEmpty)
    }

    func testRemembersWhatTheAuthorSaidElsewhere() {
        var mara = Conversation(page: UUID()), empty = Conversation(page: UUID())
        mara.ask("Why does Mara stay?")
        mara.answer("She promised her mother")
        empty.ask("What is this page about?")
        let memory = Interviewer.memory([(page: "Mara", conversation: mara), (page: "", conversation: empty)],
                                        focus: "Tomas writes to his sister Mara")
        XCTAssertEqual(Interviewer.memory([(page: "Mara", conversation: mara)], focus: "The trireme"), "")   // unrelated: left out
        XCTAssertEqual(memory, "- On Mara, you asked \"Why does Mara stay?\" I said: She promised her mother")
        let prompt = Interviewer.prompt(title: "", fields: "", writing: "", memory: memory, conversation: Conversation(page: UUID()))
        XCTAssertTrue(prompt.flattened.contains("What I've told you on other pages:\n- On Mara"))
        XCTAssertTrue(prompt.flattened.contains("I'm on a page with no title yet."))
        XCTAssertTrue(prompt.flattened.hasSuffix("(nothing yet)"))
    }

    func testNeverTheSameQuestionTwice() {
        let asked = ["What does Ilsa want?"]
        XCTAssertNil(Interviewer.screen("What does Ilsa really want?", authorText: page, asked: asked))
        XCTAssertNotNil(Interviewer.screen("Why is Ilsa a maritime adventurer?", authorText: page, asked: asked))
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
