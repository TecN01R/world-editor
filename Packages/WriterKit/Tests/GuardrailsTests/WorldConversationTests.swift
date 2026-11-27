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

    /// With no page open, each page's filled fields show beside its name.
    func testTheWorldFilingPromptShowsFilledFields() {
        let age = FieldDefinition(name: "Age", kind: .text)
        let character = PageType(name: "Character", fields: [age.id])
        var mara = Document(title: "Mara", paragraphs: [Paragraph(text: "")])
        mara.type = character.id
        mara.values[age.id] = .text("61")
        let prompt = FilingPrompt(world: [mara, Document(title: "Verran", paragraphs: [Paragraph(text: "")])],
                                  schema: Schema(fields: [age], types: [character]), asked: nil, message: "Mara is 62.")
        XCTAssertTrue(prompt.message.contains("Their pages: Mara (Age: 61), Verran"))
    }

    func testTheFilingPromptHasNoOpenPage() {
        let pages = [Document(title: "Ilsa", paragraphs: [Paragraph(text: "")])]
        let prompt = FilingPrompt(world: pages, schema: Schema(), asked: nil, message: "Ilsa is from Verran.")
        XCTAssertTrue(prompt.message.hasPrefix("No page is open: they're talking about their world as a whole."))
        XCTAssertTrue(prompt.message.contains("Their pages: Ilsa"))
    }

    /// Filed from the world's conversation: facts land on the pages they name; with nobody
    /// in focus "she" has no page to mean, and nothing is renamed.
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

    /// The same message with Ilsa in focus: "she" is Ilsa, so her age is filed too; still
    /// nothing is renamed.
    func testTheSameWithHerInFocus() throws {
        let ilsa = Document(title: "Ilsa", paragraphs: [Paragraph(text: "")])
        var pages = [ilsa], schema = Schema()
        let record = file(Filings(facts: [.init(page: "Ilsa", field: "Home", value: "Port Vell"),
                                          .init(page: "she", field: "Age", value: "34"),
                                          .init(page: "Ilsa", field: "Name", value: "Florica")],
                                  pages: [.init(title: "Ilsa", type: "Character")]),
                          "Ilsa lives in Port Vell. She's 34. Her name is Florica.", focus: [ilsa], pages: &pages, schema: &schema)
        let her = try XCTUnwrap(pages.first { $0.id == ilsa.id })
        let age = try XCTUnwrap(schema.fields.first { $0.name == "Age" })
        XCTAssertEqual(her.values[age.id], .text("34"))
        XCTAssertEqual(her.title, "Ilsa")
        XCTAssertFalse(renamed(record))
        XCTAssertEqual(schema.fields.map(\.name).sorted(), ["Age", "Home", "Name"])
        XCTAssertEqual(her.paragraphs.map(\.text), ["Ilsa lives in Port Vell. She's 34."])
    }

    // MARK: Who "she" and "the guild" are: the subject in focus (the correction, 2026-11-27)

    private let trade = FieldDefinition(name: "Trade", kind: .text)
    private let members = FieldDefinition(name: "Members", kind: .text)
    private lazy var character = PageType(name: "Character", fields: [trade.id])
    private lazy var organization = PageType(name: "Organization", fields: [members.id])
    private lazy var schema = Schema(fields: [trade, members], types: [character, organization])
    /// Old Tamsin, a clockmaker; and her guild, with nothing on it yet.
    private lazy var tamsin = Document(title: "Old Tamsin", paragraphs: [Paragraph(text: "")], type: character.id,
                                       values: [trade.id: .text("clockmaker")])
    private lazy var guild = Document(title: "The Clockmakers' Guild", paragraphs: [Paragraph(text: "")], type: organization.id)
    private let expelled = "She was expelled for mending clocks for free."

    /// Files `filings` from `message`, said in the world's conversation with `focus` (the subject first).
    private func file(_ filings: Filings, _ message: String, focus: [Document], pages: inout [Document],
                      schema: inout Schema) -> FilingRecord {
        Filer.file(filings, message: message, open: UUID(), pages: &pages, schema: &schema, focus: focus.map(\.id))
    }

    private func replaced(_ record: FilingRecord) -> Bool { record.actions.contains { $0.was != nil } }
    private func renamed(_ record: FilingRecord) -> Bool {
        record.actions.contains { if case .renamed = $0 { true } else { false } }
    }

    /// The fault found in the phone's log (2026-11-27): after "Old Tamsin is a clockmaker", "She
    /// was expelled for mending clocks for free." never reached her page. Whether the model writes
    /// "she" or the title the prompt gave it, it goes on her page, the sentence exactly as written.
    func testSheIsThePageTheyWereLastTalkingAbout() throws {
        for name in ["she", "She", "her", "Old Tamsin"] {
            var pages = [tamsin, guild], schema = self.schema
            let record = file(Filings(facts: [.init(page: name, field: "Expelled for", value: "mending clocks for free")]),
                              expelled, focus: [tamsin, guild], pages: &pages, schema: &schema)
            let reason = try XCTUnwrap(schema.fields.first { $0.name == "Expelled for" }, name)
            XCTAssertEqual(pages[0].values, [trade.id: .text("clockmaker"), reason.id: .text("mending clocks for free")], name)
            XCTAssertEqual(pages[0].paragraphs.map(\.text), [expelled], name)   // "She" stays "She"
            XCTAssertEqual(pages[1], guild, name)
            XCTAssertEqual(record.actions.count, 2, name)   // the field and the sentence, each with its Undo
        }
    }

    /// Nobody in focus: "she" isn't filed, as it never was. Nor does the "She" her sentence
    /// begins with become a page (it did, until 2026-11-27, when the model listed "she" as
    /// one: a page every later "she" would have gone to, by its title).
    func testWithNobodyInFocusSheIsNotFiled() {
        for listed in [[], [Filings.Page(title: "she", type: "Character")]] {
            var pages = [tamsin, guild], schema = self.schema
            let record = file(Filings(facts: [.init(page: "she", field: "Expelled for", value: "mending clocks for free")],
                                      pages: listed),
                              expelled, focus: [], pages: &pages, schema: &schema)
            XCTAssertTrue(record.entries.isEmpty)
            XCTAssertEqual(pages, [tamsin, guild])
            XCTAssertEqual(schema, self.schema)
        }
        // "It" and "They" neither; a name a sentence begins with still is one.
        var pages = [tamsin], schema = self.schema
        _ = file(Filings(pages: [.init(title: "It", type: "Place"), .init(title: "they", type: "Organization"),
                                 .init(title: "Brasswick", type: "Place")]),
                 "It rains there. They never mind. Brasswick is grey.", focus: [], pages: &pages, schema: &schema)
        XCTAssertEqual(pages.map(\.title), ["Old Tamsin", "Brasswick"])
    }

    /// "The guild" is the one page in focus whose title begins or ends with it, and "Tamsin"
    /// is Old Tamsin: no second page is made for either.
    func testPartOfANameIsTheOnePageInFocusItFits() throws {
        var untyped = guild
        untyped.type = nil
        var pages = [tamsin, untyped], schema = self.schema
        _ = file(Filings(facts: [.init(page: "the guild", field: "Members", value: "forty"),
                                 .init(page: "Tamsin", field: "Joined at", value: "sixteen")],
                         pages: [.init(title: "the guild", type: "Organization"), .init(title: "Tamsin", type: "Character")]),
                 "Now the guild has forty members. Tamsin joined at sixteen.", focus: [tamsin, guild],
                 pages: &pages, schema: &schema)
        XCTAssertEqual(pages.map(\.title), ["Old Tamsin", "The Clockmakers' Guild"])
        XCTAssertEqual(pages[1].type, organization.id)   // typed, as it had no type
        XCTAssertEqual(pages[1].values[members.id], .text("forty"))
        XCTAssertEqual(pages[1].paragraphs.map(\.text), ["Now the guild has forty members."])
        let joined = try XCTUnwrap(schema.fields.first { $0.name == "Joined at" })
        XCTAssertEqual(pages[0].values[joined.id], .text("sixteen"))
        XCTAssertEqual(pages[0].paragraphs.map(\.text), ["Tamsin joined at sixteen."])
        // A title's words are told apart without the punctuation around them, or a leading "the".
        XCTAssertEqual(Filer.nameWords("The Clockmakers' Guild"), ["clockmakers", "guild"])
        XCTAssertEqual(Filer.nameWords("the guild."), ["guild"])
    }

    /// Two pages in focus that "the guild" could be: it means neither.
    func testPartOfANameTwoPagesFitMeansNeither() {
        let bakers = Document(title: "The Bakers' Guild", paragraphs: [Paragraph(text: "")], type: organization.id)
        var pages = [tamsin, guild, bakers], schema = self.schema
        let record = file(Filings(facts: [.init(page: "the guild", field: "Members", value: "forty")]),
                          "Now the guild has forty members.", focus: [guild, bakers, tamsin], pages: &pages, schema: &schema)
        XCTAssertTrue(record.entries.isEmpty)
        XCTAssertEqual(pages, [tamsin, guild, bakers])
        // "The Clockmakers" is only one of them.
        _ = file(Filings(facts: [.init(page: "the Clockmakers", field: "Members", value: "forty")]),
                 "Now the Clockmakers have forty members.", focus: [guild, bakers, tamsin], pages: &pages, schema: &schema)
        XCTAssertEqual(pages[1].values[members.id], .text("forty"))
        XCTAssertTrue(pages[2].values.isEmpty)
    }

    /// A page they weren't just talking about isn't meant by part of its name.
    func testPartOfANameOutsideFocusMeansNothing() {
        var pages = [tamsin, guild], schema = self.schema
        let record = file(Filings(facts: [.init(page: "the guild", field: "Members", value: "forty")]),
                          "Now the guild has forty members.", focus: [tamsin], pages: &pages, schema: &schema)
        XCTAssertTrue(record.entries.isEmpty)
        XCTAssertEqual(pages, [tamsin, guild])
    }

    /// A page called just that is the one meant, whoever is in focus; and named in the
    /// message, it's corrected as ever.
    func testAnExactTitleAlwaysWins() {
        var theGuild = Document(title: "The Guild", paragraphs: [Paragraph(text: "")], type: organization.id)
        theGuild.values[members.id] = .text("thirty")
        var pages = [tamsin, guild, theGuild], schema = self.schema
        let record = file(Filings(facts: [.init(page: "the guild", field: "Members", value: "forty")]),
                          "Actually the guild has forty members.", focus: [guild, tamsin], pages: &pages, schema: &schema)
        XCTAssertEqual(pages[2].values[members.id], .text("forty"))
        XCTAssertTrue(replaced(record))
        XCTAssertEqual(pages[1], guild)
    }

    /// A value is only ever linked by a page's whole title: "the guild" as a value stays their words.
    func testAValueIsNeverLinkedByPartOfAName() throws {
        var pages = [tamsin, guild], schema = self.schema
        _ = file(Filings(facts: [.init(page: "Old Tamsin", field: "Expelled by", value: "the guild")]),
                 "Old Tamsin was expelled by the guild.", focus: [guild, tamsin], pages: &pages, schema: &schema)
        let by = try XCTUnwrap(schema.fields.first { $0.name == "Expelled by" })
        XCTAssertEqual(by.kind, .text)
        XCTAssertEqual(pages[0].values[by.id], .text("the guild"))
        XCTAssertFalse(pages[0].mentions(guild.id))
        XCTAssertEqual(pages.count, 2)
    }

    /// Naming the subject by guess never renames her page.
    func testAGuessNeverRenames() {
        var pages = [tamsin, guild], schema = self.schema
        let record = file(Filings(facts: [.init(page: "she", field: "Name", value: "Tamsin Vale")]),
                          "Her name is Tamsin Vale.", focus: [tamsin], pages: &pages, schema: &schema)
        XCTAssertEqual(pages.first { $0.id == tamsin.id }?.title, "Old Tamsin")
        XCTAssertFalse(renamed(record))
    }

    /// A guess never replaces what a field holds, even said as a correction: by "she", or by
    /// a title the message doesn't have. Her sentence still goes on her page. Named in the
    /// message, her field is corrected as ever, with Undo.
    func testAGuessNeverReplacesAValue() throws {
        for name in ["she", "Old Tamsin"] {
            var pages = [tamsin, guild], schema = self.schema
            let record = file(Filings(facts: [.init(page: name, field: "Trade", value: "tinker")]),
                              "Actually she's a tinker.", focus: [tamsin], pages: &pages, schema: &schema)
            XCTAssertEqual(pages[0].values, tamsin.values, name)
            XCTAssertFalse(replaced(record), name)
            XCTAssertEqual(pages[0].paragraphs.map(\.text), ["Actually she's a tinker."], name)
        }
        var pages = [tamsin, guild], schema = self.schema
        var record = file(Filings(facts: [.init(page: "Old Tamsin", field: "Trade", value: "tinker")]),
                          "Actually Old Tamsin is a tinker.", focus: [tamsin], pages: &pages, schema: &schema)
        XCTAssertEqual(pages[0].values[trade.id], .text("tinker"))
        let correction = try XCTUnwrap(record.actions.first { $0.was != nil })
        _ = record.undo(correction, pages: &pages, schema: &schema)
        XCTAssertEqual(pages[0].values, tamsin.values)
    }

    /// What they said just before is quoted to the model, but nothing is filed from it:
    /// `Filer` is only given this message, so a value that's only in the earlier one is dropped.
    func testAValueFromTheEarlierMessageIsDropped() {
        var pages = [tamsin, guild], schema = self.schema
        let before = "Old Tamsin is a clockmaker in Brasswick."
        let prompt = FilingPrompt(world: pages, schema: schema, asked: nil, message: expelled, focus: [tamsin.id], saidBefore: before)
        XCTAssertTrue(prompt.message.contains("Brasswick"))   // the model sees it
        _ = file(Filings(facts: [.init(page: "she", field: "Home", value: "Brasswick"),
                                 .init(page: "she", field: "Expelled for", value: "mending clocks for free")],
                         pages: [.init(title: "Brasswick", type: "Place", about: "a clockmaker")]),
                 expelled, focus: [tamsin], pages: &pages, schema: &schema)
        XCTAssertEqual(pages.map(\.title), ["Old Tamsin", "The Clockmakers' Guild"])   // no Brasswick
        XCTAssertEqual(schema.fields.map(\.name), ["Trade", "Members", "Expelled for"])   // no Home
        XCTAssertEqual(pages[0].paragraphs.map(\.text), [expelled])
    }

    /// With a page open, that page is who they mean: the pages in focus change nothing.
    func testWithAPageOpenFocusIsNotUsed() {
        let mara = Document(title: "Mara", paragraphs: [Paragraph(text: "")], type: character.id)
        var pages = [mara, tamsin, guild], schema = self.schema
        _ = Filer.file(Filings(facts: [.init(page: "she", field: "Trade", value: "tinker"),
                                       .init(page: "the guild", field: "Members", value: "forty")]),
                       message: "She's a tinker. Now the guild has forty members.", open: mara.id,
                       pages: &pages, schema: &schema, focus: [tamsin.id, guild.id])
        XCTAssertEqual(pages[0].values[trade.id], .text("tinker"))   // Mara, the open page
        XCTAssertEqual(Array(pages[1...]), [tamsin, guild])
    }

    /// The world's prompt says who they were last talking about, and quotes what they said
    /// just before; with nobody in focus it has neither line.
    func testTheFilingPromptNamesTheSubjectAndQuotesWhatTheySaidBefore() {
        let pages = [tamsin, guild, Document(title: "Mara", paragraphs: [Paragraph(text: "")])]
        let before = "Old Tamsin is a clockmaker."
        let prompt = FilingPrompt(world: pages, schema: schema, asked: "A clockmaker!", message: expelled,
                                  focus: [tamsin.id, guild.id], saidBefore: before)
        XCTAssertTrue(prompt.message.hasPrefix("""
            No page is open: they're talking about their world as a whole. They were last talking about “Old Tamsin” \
            (type: Character): when they say “she”, “he”, “it” or “they” without saying who, they mean that page, \
            as they would the open page.

            The world's types:
            """))
        XCTAssertTrue(prompt.message.hasSuffix("""
            Their pages: Old Tamsin (Trade: clockmaker), The Clockmakers' Guild, Mara

            Just before, they said (only to show who and what they mean; file nothing from it): “Old Tamsin is a clockmaker.”

            Their friend said: “A clockmaker!”

            Their message: “She was expelled for mending clocks for free.”
            """))
        XCTAssertEqual(prompt.system, FilingPrompt.instructions)

        // A subject with no type yet, and nothing the companion said.
        let untyped = FilingPrompt(world: pages, schema: schema, asked: nil, message: expelled, focus: [pages[2].id], saidBefore: before)
        XCTAssertTrue(untyped.message.contains("They were last talking about “Mara” (no type yet): when they say"))
        XCTAssertTrue(untyped.message.contains("file nothing from it): “Old Tamsin is a clockmaker.”\n\nTheir message: “"))

        // Nobody in focus, or a subject that's gone: neither line, whatever they said before.
        let plain = FilingPrompt(world: pages, schema: schema, asked: "A clockmaker!", message: expelled)
        for focus in [[], [UUID()], [UUID(), tamsin.id]] {
            XCTAssertEqual(FilingPrompt(world: pages, schema: schema, asked: "A clockmaker!", message: expelled,
                                        focus: focus, saidBefore: before), plain)
        }
        XCTAssertFalse(plain.message.contains("They were last talking about"))
        XCTAssertFalse(plain.message.contains("Just before, they said"))

        // A subject, but nothing said before (or only white space): just the first line.
        for nothing in [nil, "", " \n"] {
            let alone = FilingPrompt(world: pages, schema: schema, asked: nil, message: expelled, focus: [tamsin.id], saidBefore: nothing)
            XCTAssertTrue(alone.message.contains("They were last talking about “Old Tamsin”"))
            XCTAssertFalse(alone.message.contains("Just before, they said"))
        }

        // A long message before is quoted by how it opens and its latest part.
        let long = "Old Tamsin is a clockmaker. " + String(repeating: "She mends clocks. ", count: 400) + "She never charges."
        let quoted = FilingPrompt(world: pages, schema: schema, asked: nil, message: expelled, focus: [tamsin.id], saidBefore: long)
        XCTAssertLessThan(quoted.message.count, plain.message.count + FilingPrompt.maxSaidBefore + 600)
        XCTAssertTrue(quoted.message.contains("“Old Tamsin is a clockmaker. She mends clocks."))
        XCTAssertTrue(quoted.message.contains("[\u{2026}]"))
        XCTAssertTrue(quoted.message.contains("She never charges.”"))
    }
}
