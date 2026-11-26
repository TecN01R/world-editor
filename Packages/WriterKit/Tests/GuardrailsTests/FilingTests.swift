import XCTest
@testable import Guardrails
import WriterCore

final class FilingTests: XCTestCase {
    let casperica = Document(title: "Casperica", paragraphs: [Paragraph(text: "A sailor.")])
    let message = "She's from a thalassocratic nation called Myriddea."
    let myriddea = Filings(facts: [.init(page: "Casperica", field: "Origin", value: "Myriddea")],
                           pages: [.init(title: "Casperica", type: "Character"),
                                   .init(title: "Myriddea", type: "place", about: "a thalassocratic nation")])

    private func file(_ filings: Filings, _ message: String, pages: inout [Document], schema: inout Schema) -> FilingRecord {
        Filer.file(filings, message: message, open: casperica.id, pages: &pages, schema: &schema)
    }

    /// What it filed in fields, types and pages, leaving out the sentences it placed in the
    /// pages' writing (`PlacedSentencesTests`).
    private func filed(_ record: FilingRecord) -> [FilingRecord.Entry] {
        record.actions.filter { if case .placed = $0 { false } else { true } }
    }

    /// Undoes everything left in `record`, oldest first.
    private func undoAll(_ record: FilingRecord, pages: inout [Document], schema: inout Schema) {
        var record = record
        while let action = record.actions.first { _ = record.undo(action, pages: &pages, schema: &schema) }
    }

    /// Kevin's example: a type for her, a new Place page in his words, and a linked Origin field.
    func testTheMyriddeaExample() throws {
        var pages = [casperica], schema = Schema()
        let record = file(myriddea, message, pages: &pages, schema: &schema)

        XCTAssertEqual(schema.types.map(\.name), ["Character", "Place"])
        let nation = try XCTUnwrap(pages.first { $0.title == "Myriddea" })
        XCTAssertEqual(nation.paragraphs.map(\.text), ["A thalassocratic nation"])
        XCTAssertEqual(schema.type(nation.type)?.name, "Place")
        let her = try XCTUnwrap(pages.first { $0.id == casperica.id })
        XCTAssertEqual(schema.type(her.type)?.name, "Character")
        let origin = try XCTUnwrap(schema.fields.first)
        XCTAssertEqual(origin.name, "Origin")
        XCTAssertEqual(origin.kind, .page)
        XCTAssertEqual(origin.pageType, nation.type)
        XCTAssertEqual(her.values[origin.id], .page(nation.id))
        XCTAssertTrue(her.mentions(nation.id))   // so Myriddea's Mentions shows her
        XCTAssertEqual(record.actions.count, 4)   // her type, the new page, her Origin, her sentence
        XCTAssertEqual(her.paragraphs.map(\.text), ["A sailor.", "She's from a thalassocratic nation called Myriddea."])
    }

    /// Each thing it did is undone on its own; undoing them all leaves nothing behind.
    func testEachActionUndoesOnItsOwn() throws {
        var pages = [casperica], schema = Schema()
        var record = file(myriddea, message, pages: &pages, schema: &schema)
        let origin = try XCTUnwrap(record.actions.first { if case .value = $0 { true } else { false } })
        XCTAssertNil(record.undo(origin, pages: &pages, schema: &schema))
        XCTAssertTrue(pages[0].values.isEmpty)
        XCTAssertEqual(pages.count, 2)                      // Myriddea stays
        XCTAssertEqual(schema.types[0].fields, [])          // Origin is off Character
        XCTAssertTrue(schema.fields.isEmpty)                // and gone: nothing uses it
        XCTAssertEqual(schema.types.map(\.name), ["Character", "Place"])

        let page = try XCTUnwrap(record.actions.first { if case .created = $0 { true } else { false } })
        let made = try XCTUnwrap(record.undo(page, pages: &pages, schema: &schema))
        XCTAssertFalse(made.edited)
        XCTAssertEqual(pages.map(\.title), ["Casperica"])
        XCTAssertEqual(schema.types.map(\.name), ["Character"])   // Place went with it

        while let action = record.actions.first { XCTAssertNil(record.undo(action, pages: &pages, schema: &schema)) }
        XCTAssertEqual(pages, [casperica])
        XCTAssertEqual(schema, Schema())
        XCTAssertTrue(record.isEmpty)
    }

    func testUndoingAPageTakesItsLinksAndTheirLines() throws {
        var pages = [casperica], schema = Schema()
        var record = file(myriddea, message, pages: &pages, schema: &schema)
        let page = try XCTUnwrap(record.actions.first { if case .created = $0 { true } else { false } })
        _ = record.undo(page, pages: &pages, schema: &schema)
        XCTAssertTrue(pages[0].values.isEmpty)
        XCTAssertEqual(record.actions.count, 2)   // her type and her sentence are left to undo
    }

    func testUndoKeepsWhatTheAuthorChangedSince() throws {
        var pages = [casperica], schema = Schema()
        var record = file(myriddea, message, pages: &pages, schema: &schema)
        let i = try XCTUnwrap(pages.firstIndex { $0.title == "Myriddea" })
        pages[i].setText("A thalassocratic nation of rowers.", at: 0)   // he wrote on it
        let origin = try XCTUnwrap(schema.fields.first)
        pages[0].values[origin.id] = .text("Verran")                    // and changed her Origin
        for action in record.actions {
            if let made = record.undo(action, pages: &pages, schema: &schema) { XCTAssertTrue(made.edited) }
        }
        XCTAssertEqual(pages.count, 2)                          // his to delete
        XCTAssertEqual(schema.types.map(\.name), ["Place"])   // still used by Myriddea; her type was undone
        XCTAssertEqual(pages[0].values[origin.id], .text("Verran"))
    }

    func testValuesMustBeTheAuthorsWords() {
        var pages = [casperica], schema = Schema()
        let reworded = Filings(facts: [.init(page: "Casperica", field: "Origin", value: "the sea empire of Myriddea")],
                               pages: [.init(title: "Casperica", type: "Character"),
                                       .init(title: "Myridea", type: "Place", about: "a sea empire")])
        let record = file(reworded, message, pages: &pages, schema: &schema)
        XCTAssertEqual(record.entries.count, 2)   // only her type: no new page, no value
        XCTAssertEqual(pages.count, 1)
        XCTAssertTrue(pages[0].values.isEmpty)
    }

    func testQuestionsAndHedgesAreNotFiled() {
        for said in ["Is she from a thalassocratic nation called Myriddea?",
                     "Maybe she's from a thalassocratic nation called Myriddea.",
                     "She's either from a thalassocratic nation called Myriddea or somewhere else.",
                     "What if she's from a thalassocratic nation called Myriddea"] {
            var pages = [casperica], schema = Schema()
            let record = file(myriddea, said, pages: &pages, schema: &schema)
            XCTAssertEqual(pages.count, 1, said)
            XCTAssertTrue(pages[0].values.isEmpty, said)
            XCTAssertFalse(record.entries.contains { if case .created = $0 { true } else { false } }, said)
        }
        // A question in another sentence doesn't hedge this one.
        var pages = [casperica], schema = Schema()
        _ = file(myriddea, message + " What do you think?", pages: &pages, schema: &schema)
        XCTAssertEqual(pages.count, 2)
    }

    func testNewPagesNeedANameAndTextThatIsntJustTheName() {
        var pages = [casperica], schema = Schema()
        _ = file(Filings(pages: [.init(title: "grandmother", type: "Character"),
                                 .init(title: "Tern Island", type: "Place", about: "Tern Island")]),
                 "She lives on Tern Island with her grandmother.", pages: &pages, schema: &schema)
        XCTAssertEqual(pages.map(\.title), ["Casperica", "Tern Island"])
        XCTAssertEqual(pages[1].paragraphs.map(\.text), [""])

        // Nor part of the name.
        _ = file(Filings(pages: [.init(title: "Lady Corvina", type: "Character", about: "Lady")]),
                 "Her sword was a gift from Lady Corvina.", pages: &pages, schema: &schema)
        XCTAssertEqual(pages.first { $0.title == "Lady Corvina" }?.paragraphs.map(\.text), [""])
    }

    func testAValueThatOnlyRepeatsItsFieldSaysNothing() {
        var pages = [casperica], schema = Schema()
        let record = file(Filings(facts: [.init(page: "she", field: "Grandmother", value: "grandmother"),
                                          .init(page: "she", field: "Lives with", value: "her grandmother")],
                                  pages: [.init(title: "Casperica", type: "Character")]),
                          "She lives with her grandmother.", pages: &pages, schema: &schema)
        XCTAssertEqual(schema.fields.map(\.name), ["Lives with"])
        XCTAssertEqual(record.actions.count, 3)   // her type, Lives with, and her sentence
    }

    func testExistingPagesTypesAndFieldsAreReused() {
        let place = PageType(name: "Place")
        let origin = FieldDefinition(name: "Origin", kind: .page)
        let character = PageType(name: "Character", fields: [origin.id])
        var schema = Schema(fields: [origin], types: [character, place])
        var nation = Document(title: "The Myriddea", paragraphs: [Paragraph(text: "Islands.")])
        nation.type = place.id
        var pages = [casperica, nation]
        _ = file(myriddea, message, pages: &pages, schema: &schema)
        XCTAssertEqual(schema.types.count, 2)
        XCTAssertEqual(schema.fields.count, 1)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[1].paragraphs.map(\.text), ["Islands."])   // its text isn't touched
        XCTAssertEqual(pages[0].type, character.id)
        XCTAssertEqual(pages[0].values[origin.id], .page(nation.id))
    }

    /// Kevin on the phone: "Actually it's a bireme" after Vessel: trireme. Her type stays.
    func testACorrectionReplacesAValueAndUndoPutsItBack() throws {
        let vessel = FieldDefinition(name: "Vessel", kind: .text)
        let character = PageType(name: "Character", fields: [vessel.id])
        var schema = Schema(fields: [vessel], types: [character])
        var her = casperica
        her.type = character.id
        her.values[vessel.id] = .text("trireme")
        var pages = [her]
        let record = file(Filings(facts: [.init(page: "Casperica", field: "vessel", value: "bireme"),
                                          .init(page: "Casperica", field: "vessel", value: "trireme")],
                                  pages: [.init(title: "Casperica", type: "Pirate")]),
                          "Actually it's a bireme, not a trireme", pages: &pages, schema: &schema)
        XCTAssertEqual(filed(record), [.replaced(page: her.id, field: vessel.id, was: .text("trireme"), value: .text("bireme"))])
        XCTAssertEqual(pages[0].type, character.id)

        undoAll(record, pages: &pages, schema: &schema)
        XCTAssertEqual(pages, [her])

        // A polite correction is one; a guess isn't.
        let polite = file(Filings(facts: [.init(page: "she", field: "Vessel", value: "bireme")]),
                          "I think it was actually a bireme", pages: &pages, schema: &schema)
        XCTAssertEqual(pages[0].values[vessel.id], .text("bireme"))
        undoAll(polite, pages: &pages, schema: &schema)
        XCTAssertEqual(pages, [her])
        for guess in ["I think it was a bireme", "I'm not actually sure, I think it was a bireme",
                      "I don't actually know, a bireme"] {
            XCTAssertTrue(file(Filings(facts: [.init(page: "she", field: "Vessel", value: "bireme")]),
                               guess, pages: &pages, schema: &schema).isEmpty, guess)
        }
        let before = file(Filings(facts: [.init(page: "she", field: "Vessel", value: "bireme")]),
                          "Actually, I think it was a bireme", pages: &pages, schema: &schema)
        XCTAssertFalse(filed(before).isEmpty)
        undoAll(before, pages: &pages, schema: &schema)
        XCTAssertEqual(pages, [her])

        // Read again (Try Again): a value the author changed since the first reading stays.
        let seen = pages[0].values
        pages[0].values[vessel.id] = .text("galley")   // their own edit
        let reread = Filer.file(Filings(facts: [.init(page: "she", field: "Vessel", value: "bireme")]),
                                message: "Actually it's a bireme", open: her.id, pages: &pages, schema: &schema) {
            page, field, was in page == her.id && seen[field] == was
        }
        XCTAssertTrue(filed(reread).isEmpty)
        XCTAssertEqual(pages[0].values[vessel.id], .text("galley"))
        undoAll(reread, pages: &pages, schema: &schema)
        pages[0].values[vessel.id] = .text("trireme")

        // What was true once isn't a correction, but it's still hers to have on the page.
        let then = file(Filings(facts: [.init(page: "she", field: "Vessel", value: "galley")]),
                        "She rowed on a galley when she was sixteen.", pages: &pages, schema: &schema)
        XCTAssertTrue(filed(then).isEmpty)
        XCTAssertEqual(pages[0].values, her.values)
        XCTAssertEqual(pages[0].paragraphs.last?.text, "She rowed on a galley when she was sixteen.")
        undoAll(then, pages: &pages, schema: &schema)
        XCTAssertEqual(pages, [her])
    }

    /// A correction that names a new page links it; undoing that page puts the old value back.
    func testUndoingAPageACorrectionMadeRestoresTheOldValue() throws {
        let origin = FieldDefinition(name: "Origin", kind: .page)
        let character = PageType(name: "Character", fields: [origin.id])
        let verran = Document(title: "Verran", paragraphs: [Paragraph(text: "")])
        var schema = Schema(fields: [origin], types: [character])
        var her = casperica
        her.type = character.id
        her.values[origin.id] = .page(verran.id)
        var pages = [her, verran]
        var record = file(Filings(facts: [.init(page: "she", field: "Origin", value: "Myriddea")]),
                          "No, she's from Myriddea.", pages: &pages, schema: &schema)
        let made = try XCTUnwrap(record.actions.first { if case .created = $0 { true } else { false } })
        XCTAssertNotEqual(pages.first { $0.id == her.id }?.values[origin.id], .page(verran.id))

        _ = record.undo(made, pages: &pages, schema: &schema)
        XCTAssertEqual(pages.first { $0.id == her.id }?.values, her.values)
        undoAll(record, pages: &pages, schema: &schema)   // her sentence
        XCTAssertEqual(pages.first { $0.id == her.id }, her)
    }

    func testTheAuthorsSpellingAndAnUntitledOpenPage() throws {
        let untitled = Document(paragraphs: [Paragraph(text: "Someone from the islands")])
        var pages = [untitled], schema = Schema()
        _ = Filer.file(Filings(facts: [.init(page: "she", field: "home", value: "port vell.")],
                               pages: [.init(title: "she", type: "character"), .init(title: "Nobody", type: "none")]),
                       message: "She lives in Port Vell", open: untitled.id, pages: &pages, schema: &schema)
        let home = try XCTUnwrap(schema.fields.first)
        XCTAssertEqual(home.name, "Home")
        XCTAssertEqual(schema.types.map(\.name), ["Character"])   // "none" isn't a type
        // A name the model didn't list as a page gets one, spelt as the author wrote it.
        XCTAssertEqual(pages.map(\.title), ["", "Port Vell"])
        XCTAssertEqual(pages[0].values[home.id], .page(pages[1].id))
    }

    func testOnlyNamesMidSentenceGetPages() {
        var pages = [casperica], schema = Schema()
        _ = file(Filings(facts: [.init(page: "she", field: "Age", value: "Nineteen"),
                                 .init(page: "she", field: "Carries", value: "her father's compass"),
                                 .init(page: "she", field: "Sword", value: "Mercy")],
                         pages: [.init(title: "Casperica", type: "Character")]),
                 "Nineteen. She carries her father's compass and a sword called Mercy.", pages: &pages, schema: &schema)
        XCTAssertEqual(pages.map(\.title), ["Casperica", "Mercy"])
    }

    func testOldConversationsLoadWithoutFilings() throws {
        let old = #"{"page":"\#(UUID())","turns":[{"id":"\#(UUID())","question":"Hi","asked":0}]}"#
        let talk = try JSONDecoder().decode(Conversation.self, from: Data(old.utf8))
        XCTAssertNil(talk.turns[0].filed)
    }

    func testThePromptShowsTheWorld() {
        let prompt = FilingPrompt(page: (title: "Casperica", type: nil, fields: ""),
                                  types: [(name: "Place", fields: ["Ruler"])], others: ["Myriddea"],
                                  asked: "Where is she from?", message: message)
        XCTAssertEqual(prompt.message, """
            The open page: “Casperica” (no type yet)

            The world's types:
            - Place: Ruler

            Other pages: Myriddea

            Their friend said: “Where is she from?”

            Their message: “\(message)”
            """)
    }

    /// The model's JSON, as it writes it: fenced, with parts missing, or cut off.
    func testReadingTheModelsJSON() {
        let fenced = """
            ```json
            {"facts": [{"page": "Casperica", "field": "Origin", "value": "Myriddea"}, {"page": "Casperica"}],
             "pages": [{"title": "Myriddea", "type": "Place"}]}
            ```
            """
        XCTAssertEqual(Filings.parse(fenced), Filings(facts: [.init(page: "Casperica", field: "Origin", value: "Myriddea")],
                                                      pages: [.init(title: "Myriddea", type: "Place")]))
        XCTAssertEqual(Filings.parse(#"{"pages": []}"#), Filings())
        XCTAssertEqual(Filings.parse(#"{"facts": [{"page": "Casp"#), Filings())
        // A stray brace between the lists, as Gemma once wrote; and a bracket inside a value.
        let stray = #"{"facts": [{"page": "Ilsa", "field": "Born", "value": "1211 [old count]"}]}, "pages": [{"title": "Ilsa"}]}"#
        XCTAssertEqual(Filings.parse(stray), Filings(facts: [.init(page: "Ilsa", field: "Born", value: "1211 [old count]")],
                                                     pages: [.init(title: "Ilsa")]))
    }

    /// A field the author took off a type isn't put back by filing.
    func testAFieldRemovedFromATypeStaysRemoved() {
        let age = FieldDefinition(name: "Age", kind: .text)
        let character = PageType(name: "Character", fields: [])   // Age taken off
        var schema = Schema(fields: [age], types: [character])
        var mara = Document(title: "Mara", paragraphs: [Paragraph(text: "")])
        mara.type = character.id
        mara.values[age.id] = .text("19")   // kept, unseen
        var her = casperica
        her.type = character.id
        var pages = [her, mara]
        let record = file(Filings(facts: [.init(page: "she", field: "Age", value: "twenty")]),
                          "She's twenty.", pages: &pages, schema: &schema)
        XCTAssertTrue(filed(record).isEmpty)
        XCTAssertTrue(schema.types[0].fields.isEmpty)
        XCTAssertNil(pages[0].values[age.id])
    }
}

/// The sentences filed facts came from go into their pages' writing, as the author wrote them,
/// marked as placed, each message's with its own Undo (Kevin, 2026-11-26: "fill in the
/// description based on things I said automatically").
final class PlacedSentencesTests: XCTestCase {
    let bram = Document(title: "Bram", paragraphs: [Paragraph(text: "A monk.")])

    private func placed(_ record: FilingRecord) -> [FilingRecord.Entry] {
        record.actions.filter { if case .placed = $0 { true } else { false } }
    }

    func testEachPageGetsTheSentencesAboutItAndNothingElse() throws {
        var pages = [bram], schema = Schema()
        let message = "he trained at the Iron Abbey. is he a monk? Maybe he's twenty. The Iron Abbey burned in 1102. I love him."
        let record = Filer.file(Filings(facts: [.init(page: "Bram", field: "Trained at", value: "Iron Abbey"),
                                                .init(page: "Bram", field: "Age", value: "twenty"),
                                                .init(page: "Iron Abbey", field: "Burned", value: "1102")],
                                        pages: [.init(title: "Bram", type: "Character"),
                                                .init(title: "Iron Abbey", type: "Place")]),
                                message: message, open: bram.id, pages: &pages, schema: &schema)
        let him = try XCTUnwrap(pages.first { $0.id == bram.id })
        let abbey = try XCTUnwrap(pages.first { $0.title == "Iron Abbey" })
        // Hedged and asked sentences, and what no fact came from, stay out.
        XCTAssertEqual(him.paragraphs.map(\.text), ["A monk.", "He trained at the Iron Abbey."])
        XCTAssertEqual(him.paragraphs[1].placed.map(\.length), [him.paragraphs[1].length])
        XCTAssertEqual(abbey.paragraphs.map(\.text), ["The Iron Abbey burned in 1102."])   // took its empty line
        XCTAssertEqual(placed(record).count, 2)
    }

    func testWhatsOnThePageAlreadyIsntPlacedAgainAndUndoKeepsTheAuthorsEdits() throws {
        var pages = [bram], schema = Schema()
        let filings = Filings(facts: [.init(page: "Bram", field: "Comes from", value: "Holm")])
        var record = Filer.file(filings, message: "He comes from Holm.", open: bram.id, pages: &pages, schema: &schema)
        let again = Filer.file(filings, message: "he comes from holm", open: bram.id, pages: &pages, schema: &schema)
        XCTAssertTrue(placed(again).isEmpty)
        XCTAssertEqual(pages[0].paragraphs.map(\.text), ["A monk.", "He comes from Holm."])

        let sentence = try XCTUnwrap(placed(record).first)
        pages[0].replace(0..<0, in: 1, with: "Yes. ")   // the author writes in it
        _ = record.undo(sentence, pages: &pages, schema: &schema)
        XCTAssertEqual(pages[0].paragraphs.map(\.text), ["A monk.", "Yes. He comes from Holm."])
    }
}
