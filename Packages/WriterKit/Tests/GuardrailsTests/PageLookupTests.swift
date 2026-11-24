import XCTest
@testable import Guardrails
import WriterCore

/// The companion's search of the author's pages (its search_pages tool, and the passages the
/// prompt gets for what they just said). The pages are invented for these tests.
final class PageLookupTests: XCTestCase {
    private struct World {
        var pages: [Document]
        var schema: Schema
        var conversations: [Conversation] = []
        var lookup: PageLookup { PageLookup(pages: pages, schema: schema, conversations: conversations) }
        func page(_ title: String) -> Document { pages.first { $0.title == title }! }
    }

    private func page(_ title: String, _ writing: String..., type: UUID? = nil, at time: Double,
                      values: [UUID: FieldValue] = [:]) -> Document {
        Document(title: title, paragraphs: writing.map { Paragraph(text: $0) }, modified: Date(timeIntervalSince1970: time),
                 type: type, values: values)
    }

    private func world() -> World {
        let owner = FieldDefinition(name: "Owner", kind: .page), builtBy = FieldDefinition(name: "Built by", kind: .text)
        let ship = PageType(name: "Ship", fields: [owner.id, builtBy.id]), character = PageType(name: "Character"),
            place = PageType(name: "Place"), organization = PageType(name: "Organization"), event = PageType(name: "Event")
        let draven = page("Draven", "Captain of the Kestrel. Owes money to half of Port Vell.", type: character.id, at: 5)
        return World(pages: [
            draven,
            page("Ilsa", "A rower on the Kestrel. Grew up in Port Vell.", type: character.id, at: 4),
            page("The Kestrel", "Fast, narrow, always leaking. Twenty oars a side.", "Draven had her caulked twice last winter.",
                 type: ship.id, at: 6, values: [owner.id: .page(draven.id), builtBy.id: .text("Tomas Reyes")]),
            page("Port Vell", "A harbour town on the salt coast.", type: place.id, at: 3),
            page("The Guild of Lamps", "Every ship that passes a lit lamp pays the Guild a toll.", type: organization.id, at: 2),
            page("The Salt Wars", "Three summers of raids along the coast, Verran against the salt towns of the south.",
                 type: event.id, at: 1),
            page("Éloise", "Keeps the lamp at the harbour mouth with Ana and Kai.", type: character.id, at: 0.5),
            page("Kai", "Mends nets on the quay.", type: character.id, at: 0.2),
            page("Portraits", "Sketches of the crew.", at: 0.1),
        ], schema: Schema(fields: [owner, builtBy], types: [ship, character, place, organization, event]))
    }

    // MARK: A name returns its page

    /// A name returns that page: its fields, then its writing, then the other pages that
    /// mention it (shape (a)).
    func testANameReturnsItsPage() {
        XCTAssertEqual(world().lookup.results(for: "Kestrel"), """
            \u{201C}The Kestrel\u{201D}, a ship page:
            Owner: Draven
            Built by: Tomas Reyes
            Fast, narrow, always leaking. Twenty oars a side.
            Draven had her caulked twice last winter.
            Also on their pages:
            - Draven (Character): \u{201C}Captain of the Kestrel. Owes money to half of Port Vell.\u{201D}
            - Ilsa (Character): \u{201C}A rower on the Kestrel. Grew up in Port Vell.\u{201D}
            """)
    }

    /// A title match ignores case, accents, quotes and a leading "The".
    func testANameMatchesIgnoringCaseAccentsAndThe() {
        let lookup = world().lookup
        for query in ["kestrel", "the KESTREL", "  The Kestrel ", "\u{201C}The Kestrel\u{201D}", "Kestrel?"] {
            XCTAssertTrue(lookup.results(for: query).hasPrefix("\u{201C}The Kestrel\u{201D}, a ship page:\n"), query)
        }
        for query in ["Eloise", "ÉLOISE", "the eloise"] {
            XCTAssertTrue(lookup.results(for: query).hasPrefix("\u{201C}\u{00C9}loise\u{201D}, a character page:\n"), query)
        }
        // A page titled without "The" is named with it too.
        XCTAssertTrue(lookup.results(for: "The Port Vell").hasPrefix("\u{201C}Port Vell\u{201D}, a place page:\n"))
    }

    // MARK: Words return passages

    /// Words return the pages with the most matching passages, each cut around what matched
    /// (shape (b)). "tolls" finds "toll"; a title match goes before a paragraph's, and
    /// passages that tie go newer page first.
    func testWordsReturnPassages() {
        XCTAssertEqual(world().lookup.results(for: "salt tolls"), """
            Their pages, for \u{201C}salt tolls\u{201D}:
            - The Guild of Lamps (Organization): \u{201C}Every ship that passes a lit lamp pays the Guild a toll.\u{201D}
            - The Salt Wars (Event): \u{201C}Three summers of raids along the coast, Verran against the salt towns of the south.\u{201D}
            - Port Vell (Place): \u{201C}A harbour town on the salt coast.\u{201D}
            """)
    }

    /// "Port" isn't the name "Port Vell", but finds it first, by its title; a word it only
    /// begins ("Portraits") comes after whole words.
    func testPortFindsPortVell() {
        XCTAssertEqual(world().lookup.results(for: "Port"), """
            Their pages, for \u{201C}Port\u{201D}:
            - Port Vell (Place): \u{201C}A harbour town on the salt coast.\u{201D}
            - Draven (Character): \u{201C}Captain of the Kestrel. Owes money to half of Port Vell.\u{201D}
            - Ilsa (Character): \u{201C}A rower on the Kestrel. Grew up in Port Vell.\u{201D}
            - Portraits: \u{201C}Sketches of the crew.\u{201D}
            """)
    }

    /// Short names aren't dropped as short words, and a word finds the longer ones it begins.
    func testShortNamesAndWordBeginnings() {
        let lookup = world().lookup
        XCTAssertEqual(lookup.results(for: "Kai"), """
            \u{201C}Kai\u{201D}, a character page:
            Mends nets on the quay.
            Also on their pages:
            - \u{00C9}loise (Character): \u{201C}Keeps the lamp at the harbour mouth with Ana and Kai.\u{201D}
            """)
        XCTAssertEqual(lookup.results(for: "Ana"), """
            Their pages, for \u{201C}Ana\u{201D}:
            - \u{00C9}loise (Character): \u{201C}Keeps the lamp at the harbour mouth with Ana and Kai.\u{201D}
            """)
        XCTAssertEqual(lookup.results(for: "oar"), """
            Their pages, for \u{201C}oar\u{201D}:
            - The Kestrel (Ship): \u{201C}Fast, narrow, always leaking. Twenty oars a side.\u{201D}
            """)
    }

    /// A question finds the field that answers it: the page's name counts on its other passages.
    func testAQuestionFindsTheFieldThatAnswersIt() {
        XCTAssertTrue(world().lookup.results(for: "who built the Kestrel").hasPrefix("""
            Their pages, for \u{201C}who built the Kestrel\u{201D}:
            - The Kestrel (Ship): Built by: Tomas Reyes
            """))
    }

    /// A quoted phrase is found only with its words together, in order.
    func testAQuotedPhraseStaysWhole() {
        let lookup = world().lookup
        XCTAssertTrue(lookup.results(for: "\"harbour mouth\"").contains("- \u{00C9}loise (Character)"))
        XCTAssertFalse(lookup.results(for: "\"harbour mouth\"").contains("Port Vell"))
        XCTAssertEqual(lookup.results(for: "\"mouth harbour\""), PageLookup.nothingFound("\"mouth harbour\""))
    }

    // MARK: Nothing, no query

    func testNothingFoundAndNoQuery() {
        let lookup = world().lookup
        XCTAssertEqual(lookup.results(for: "Long Accord"),
                       "Nothing on their pages or in what they've told you mentions \u{201C}Long Accord\u{201D}.")
        XCTAssertEqual(lookup.results(for: "  \n"), "search_pages needs a name or a few words to look for.")
        XCTAssertEqual(PageLookup(pages: []).results(for: "Kestrel"),
                       "Nothing on their pages or in what they've told you mentions \u{201C}Kestrel\u{201D}.")
    }

    // MARK: Within 1,500 characters

    /// However long a page or big a world, a search returns at most 1,500 characters; a long
    /// named page shows how it opens and its latest part, within 900.
    func testTheCapHoldsForAVeryLongPage() throws {
        var world = world()
        var entries: [String] = [], length = 0
        while length < 20_000 {
            let entry = "Entry \(entries.count + 1): paid the harbour toll in salt and rope, and wrote it down."
            entries.append(entry)
            length += entry.count + 1
        }
        let oneParagraph = String(repeating: "The harbour toll went up again and nobody knew why. ", count: 400)
        world.pages += [page("The Ledger", entries.joined(separator: "\n"), at: 7), page("Logbook", oneParagraph, at: 8)]
        world.pages += (1...300).map { page("Harbour \($0)", "Another harbour, another toll, another ledger entry.", at: 9) }
        let lookup = world.lookup
        for query in ["Ledger", "Logbook", "harbour toll", "entry", "salt rope", "toll"] {
            XCTAssertLessThanOrEqual(lookup.results(for: query).count, PageLookup.maxCharacters, query)
        }
        let ledger = lookup.results(for: "the ledger")
        let named = try XCTUnwrap(ledger.components(separatedBy: "\nAlso on their pages:").first)
        XCTAssertLessThanOrEqual(named.count, 900)
        XCTAssertTrue(named.contains("Entry 1: paid"))                                // how it opens
        XCTAssertTrue(named.contains("[\u{2026}]"))
        XCTAssertTrue(named.hasSuffix("Entry \(entries.count): paid the harbour toll in salt and rope, and wrote it down."))
        // A 20,000-character paragraph is shown as a window, cut at words on both sides.
        XCTAssertTrue(lookup.results(for: "nobody").contains("- Logbook: \u{201C}The harbour toll went up again"))
        let window = PageLookup.window(oneParagraph, found: ["nobody"])
        XCTAssertLessThanOrEqual(window.count, 242)
        XCTAssertTrue(window.hasSuffix("\u{2026}"))
        let middle = PageLookup.window(String(repeating: "word ", count: 100) + "nobody " + String(repeating: "word ", count: 100),
                                       found: ["nobody"])
        XCTAssertTrue(middle.hasPrefix("\u{2026}word "))
        XCTAssertTrue(middle.hasSuffix(" word\u{2026}"))
        XCTAssertTrue(middle.contains("nobody"))
        XCTAssertLessThanOrEqual(lookup.related(to: "the harbour toll and the ledger", maxCharacters: 1500).count, 1500)
    }

    // MARK: Plain for Gemma

    /// Text typed on a page that looks like Gemma's control tokens comes back as plain words,
    /// so it can't end the tool's response or the turn.
    func testPageTextCantEndTheTurn() {
        var world = world()
        world.pages.append(page("Chat <turn|> notes", "She wrote <|\"|> and <turn|> on the wall, then <|tool_response>.", at: 7))
        let lookup = world.lookup
        for result in [lookup.results(for: "wall"), lookup.results(for: "Chat <turn|> notes"), lookup.results(for: "<|\"|>"),
                       lookup.related(to: "what was on the wall", maxCharacters: 1500)] {
            XCTAssertTrue(result.contains("wall") || result.contains("Nothing"), result)
            for token in ["<|", "|>", "<turn|>", "<|\"|>"] { XCTAssertFalse(result.contains(token), result) }
            XCTAssertEqual(Reasoned.gemmaPlain(result), result)   // the app's own pass changes nothing
        }
    }

    // MARK: Fields

    /// A field that links to a page shows that page's heading, as it is now; a link to a page
    /// in Recently Deleted shows nothing, and that page isn't searched.
    func testFieldLinksShowTheirPagesHeading() {
        var world = world()
        let i = world.pages.firstIndex { $0.title == "Draven" }!
        world.pages[i].title = "Draven Ash"
        XCTAssertTrue(world.lookup.results(for: "Kestrel").contains("\nOwner: Draven Ash\n"))
        world.pages[i].deleted = Date()
        let results = world.lookup.results(for: "Kestrel")
        XCTAssertFalse(results.contains("Owner:"))
        XCTAssertTrue(results.contains("\nBuilt by: Tomas Reyes\n"))
        XCTAssertFalse(results.contains("Captain of the Kestrel"))
        XCTAssertFalse(world.lookup.results(for: "Draven Ash").hasPrefix("\u{201C}Draven Ash\u{201D}"))
    }

    // MARK: What they told the companion

    /// The author's answers from earlier conversations are found and say where they were
    /// said; the companion's own lines never are.
    func testConversationHitsAreLabelled() {
        var world = world()
        var ilsa = Conversation(page: world.page("Ilsa").id)
        ilsa.ask("Is the debt why she rows?")
        ilsa.answer("She owes him money. That's the only reason she's on his ship")
        var whole = Conversation(page: UUID(), aboutWorld: true)
        whole.answer("The lamps burned whale oil before the Guild")
        var gone = Conversation(page: UUID())
        gone.ask("What is this?")
        gone.answer("A draft about whale oil I deleted")
        world.conversations = [ilsa, whole, gone]
        let lookup = world.lookup
        XCTAssertEqual(lookup.results(for: "money"), """
            Their pages, for \u{201C}money\u{201D}:
            - Draven (Character): \u{201C}Captain of the Kestrel. Owes money to half of Port Vell.\u{201D}
            They told you, in the conversation on \u{201C}Ilsa\u{201D}: \u{201C}She owes him money. That's the only reason she's on his ship\u{201D}
            """)
        XCTAssertEqual(lookup.results(for: "whale oil"),
                       "They told you, in a conversation about their whole world: \u{201C}The lamps burned whale oil before the Guild\u{201D}")
        XCTAssertEqual(lookup.results(for: "debt"), PageLookup.nothingFound("debt"))   // only the companion said it
        // What they said about a page comes with that page.
        XCTAssertTrue(lookup.results(for: "Ilsa").hasSuffix(
            "\nThey told you, in the conversation on \u{201C}Ilsa\u{201D}: \u{201C}She owes him money. That's the only reason she's on his ship\u{201D}"))
    }

    // MARK: Spotlight's ranking

    /// Spotlight's ids come first, each once, then the lexical hits; ids of pages or
    /// paragraphs no longer there are dropped.
    func testSpotlightIdsComeFirstThenWords() {
        var world = world()
        let draft = page("Old Draft", "The harbour before the flood.", at: 9)
        world.pages.append(draft)
        world.pages[world.pages.count - 1].deleted = Date()
        let kestrel = world.page("The Kestrel"), eloise = world.page("Éloise"), ilsa = world.page("Ilsa")
        let ranked = [
            "\(draft.id.uuidString)/title", "\(draft.id.uuidString)/\(draft.paragraphs[0].id.uuidString)",   // deleted
            "\(UUID().uuidString)/fields", "not an id", "\(ilsa.id.uuidString)/\(UUID().uuidString)",             // gone
            "\(kestrel.id.uuidString)/\(kestrel.paragraphs[1].id.uuidString)",
            "\(eloise.id.uuidString)/\(eloise.paragraphs[0].id.uuidString)",
            "\(kestrel.id.uuidString)/\(kestrel.paragraphs[1].id.uuidString)",
        ]
        let results = world.lookup.results(for: "harbour", ranked: ranked)
        XCTAssertEqual(results, """
            Their pages, for \u{201C}harbour\u{201D}:
            - The Kestrel (Ship): \u{201C}Draven had her caulked twice last winter.\u{201D}
            - \u{00C9}loise (Character): \u{201C}Keeps the lamp at the harbour mouth with Ana and Kai.\u{201D}
            - Port Vell (Place): \u{201C}A harbour town on the salt coast.\u{201D}
            """)
        // Without Spotlight, the same words rank by themselves: the newer page first.
        XCTAssertEqual(world.lookup.results(for: "harbour"), """
            Their pages, for \u{201C}harbour\u{201D}:
            - Port Vell (Place): \u{201C}A harbour town on the salt coast.\u{201D}
            - \u{00C9}loise (Character): \u{201C}Keeps the lamp at the harbour mouth with Ana and Kai.\u{201D}
            """)
        // A page Spotlight found by its title alone shows its fields.
        XCTAssertTrue(world.lookup.results(for: "vessel", ranked: ["\(kestrel.id.uuidString)/title"])
            .hasSuffix("\n- The Kestrel (Ship): Owner: Draven; Built by: Tomas Reyes"))
    }

    /// The ids are Spotlight's: what the app indexes and what the search reads back.
    func testItemIdsRoundTrip() {
        let paragraph = Paragraph(text: "A rower."), page = Document(title: " Ilsa ", paragraphs: [paragraph, Paragraph(text: "  ")])
        let passages = Search.passages(of: page, fields: "Species: Human")
        XCTAssertEqual(passages.map(\.item.id), [
            "\(page.id.uuidString)/title", "\(page.id.uuidString)/fields", "\(page.id.uuidString)/\(paragraph.id.uuidString)",
        ])
        XCTAssertEqual(passages.map(\.text), ["Ilsa", "Species: Human", "A rower."])
        for passage in passages { XCTAssertEqual(Search.Item(id: passage.item.id), passage.item) }
        XCTAssertEqual(Search.Item(id: "\(page.id.uuidString)/title")?.part, .title)
        for id in ["", "title", "\(page.id.uuidString)", "\(page.id.uuidString)/other", "x/title", "\(page.id.uuidString)/title/x"] {
            XCTAssertNil(Search.Item(id: id), id)
        }
        XCTAssertEqual(Search.passages(of: Document(), fields: "").count, 0)
    }

    // MARK: For the prompt

    /// What the pages say about what the author just said: its everyday words left out,
    /// and the open page, already shown, too.
    func testRelatedToWhatTheyJustSaid() {
        let world = world(), lookup = world.lookup
        let related = lookup.related(to: "I think Draven should sell the Kestrel", maxCharacters: 1500)
        XCTAssertTrue(related.hasPrefix("- The Kestrel (Ship): "), related)
        XCTAssertTrue(related.contains("\n- Draven (Character): "), related)
        XCTAssertFalse(lookup.related(to: "I think Draven should sell the Kestrel", maxCharacters: 1500,
                                      excluding: world.page("The Kestrel").id).contains("The Kestrel (Ship)"))
        XCTAssertEqual(lookup.related(to: "ok thanks, that really helps", maxCharacters: 1500), "")
        XCTAssertLessThanOrEqual(lookup.related(to: "Draven, Ilsa, Kai and the Kestrel in Port Vell", maxCharacters: 300).count, 300)
    }

    /// The list of every page, those bearing on the focus first; cut, it says how many more there are.
    func testTheDirectory() {
        let pages = [CompanionPrompt.Page(name: "Verran", type: "Place", writing: "A seafaring nation"),
                     CompanionPrompt.Page(name: "", writing: ""),
                     CompanionPrompt.Page(name: "Ilsa", type: "Character", writing: "A rower from Verran")]
        XCTAssertEqual(PageLookup.directory(pages, focus: "Ilsa rows", maxCharacters: 1000),
                       "- Ilsa (Character)\n- Verran (Place)")
        let many = (1...100).map { CompanionPrompt.Page(name: "Page \($0)", writing: "") }
        let cut = PageLookup.directory(many, focus: "", maxCharacters: 100)
        XCTAssertLessThanOrEqual(cut.count, 100)
        let lines = cut.components(separatedBy: "\n")
        XCTAssertEqual(lines.last, "\u{2026}and \(100 - (lines.count - 1)) more.")
        XCTAssertEqual(lines.first, "- Page 1")
        XCTAssertEqual(PageLookup.directory(many, focus: "", maxCharacters: 5), "")
    }
}
