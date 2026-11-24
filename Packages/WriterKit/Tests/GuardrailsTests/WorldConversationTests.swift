import XCTest
@testable import Guardrails
import WriterCore

/// The world's own conversation (Kevin, 2026-11-24: "converse with it and not operate
/// solely within a single page"): every page as background, no page open.
final class WorldConversationTests: XCTestCase {
    let ilsa = CompanionPrompt.Page(name: "Ilsa", type: "Character", writing: "A maritime adventurer")
    let verran = CompanionPrompt.Page(name: "Verran", type: "Place", writing: "A seafaring nation of rowers and traders")

    func testThePromptShowsTheWorldAndNoOpenPage() {
        let prompt = CompanionPrompt(world: "Tidewater", pages: [ilsa, verran], conversation: Conversation(page: UUID()))
        XCTAssertTrue(prompt.system.hasPrefix(CompanionPrompt.instructions))
        XCTAssertTrue(prompt.system.contains("Their world, \u{201C}Tidewater\u{201D}, and its pages:\n- Ilsa (Character): A maritime adventurer\n- Verran (Place)"))
        XCTAssertFalse(prompt.system.contains("The page they have open now"))
        XCTAssertFalse(prompt.system.contains("Right now:"))   // it doesn't speak first here
    }

    /// The author begins: their words are the first turn, with nothing before them.
    func testTheAuthorBegins() {
        var talk = Conversation(page: UUID())
        talk.answer("How do Ilsa and Verran connect?")
        XCTAssertEqual(talk.turns.count, 1)
        XCTAssertEqual(talk.turns[0].question, "")
        XCTAssertNotNil(talk.turns[0].answered)
        talk.answer("ignored: nothing is waiting")
        XCTAssertEqual(talk.turns[0].answer, "How do Ilsa and Verran connect?")
        talk.ask("She sails from Verran's harbour.")
        talk.answer("yes")

        let prompt = CompanionPrompt(world: "Tidewater", pages: [ilsa, verran], conversation: talk)
        XCTAssertEqual(prompt.turns.map(\.speaker), [.author, .companion, .author])
        XCTAssertEqual(prompt.turns.map(\.text), ["How do Ilsa and Verran connect?", "She sails from Verran's harbour.", "yes"])
        XCTAssertEqual(CompanionPrompt.plain(talk).turns.first?.text, "How do Ilsa and Verran connect?")
    }

    /// A world conversation from before it waited (the companion spoke first) still opens with the author.
    func testAnOlderWorldConversationTheCompanionBegan() {
        var talk = Conversation(page: UUID())
        talk.ask("Ilsa and Draven both run cargo.")
        talk.answer("they do")
        let prompt = CompanionPrompt(world: "Tidewater", pages: [ilsa], conversation: talk)
        XCTAssertEqual(prompt.turns.map(\.text), [CompanionPrompt.openedWorld, "Ilsa and Draven both run cargo.", "they do"])
    }

    func testAnEmptyWorldAndAConversationUnderWay() {
        var talk = Conversation(page: UUID())
        talk.ask("What's in your head?")
        talk.answer("a drowned city")
        let prompt = CompanionPrompt(world: "New World", pages: [], conversation: talk)
        XCTAssertTrue(prompt.system.contains("Their world, \u{201C}New World\u{201D}, has no pages yet."))
        XCTAssertEqual(prompt.turns.map(\.text), [CompanionPrompt.openedWorld, "What's in your head?", "a drowned city"])
    }

    func testTheFilingPromptHasNoOpenPage() {
        let pages = [Document(title: "Ilsa", paragraphs: [Paragraph(text: "")])]
        let prompt = FilingPrompt(world: pages, schema: Schema(), asked: nil, message: "Ilsa is from Verran.")
        XCTAssertTrue(prompt.message.hasPrefix("No page is open: they're talking about their world as a whole."))
        XCTAssertTrue(prompt.message.contains("Their pages: Ilsa"))
    }

    /// Filed from the world's conversation: facts land on the pages they name; "she" has
    /// no page to mean, and nothing is renamed.
    func testFilingWithNoPageOpen() {
        let ilsa = Document(title: "Ilsa", paragraphs: [Paragraph(text: "")])
        let world = UUID()
        var pages = [ilsa], schema = Schema()
        _ = Filer.file(Filings(facts: [.init(page: "Ilsa", field: "Home", value: "Port Vell"),
                                       .init(page: "she", field: "Age", value: "34"),
                                       .init(page: "Ilsa", field: "Name", value: "Florica")],
                               pages: [.init(title: "Ilsa", type: "Character")]),
                       message: "Ilsa lives in Port Vell. She's 34. Her name is Florica.", open: world,
                       pages: &pages, schema: &schema)
        XCTAssertEqual(pages.first { $0.id == ilsa.id }?.title, "Ilsa")
        XCTAssertEqual(schema.fields.map(\.name).sorted(), ["Home", "Name"].sorted())   // a Name field: Ilsa isn't the open page
        XCTAssertFalse(schema.fields.contains { $0.name == "Age" })
    }
}
