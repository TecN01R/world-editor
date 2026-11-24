import XCTest
@testable import Guardrails
import WriterCore

/// Naming the open page's subject renames the page (Kevin, 2026-11-24: "Her name is
/// Florica" made a new page Florica and a Name field instead).
final class RenameTests: XCTestCase {
    let casperica = Document(title: "Casperica", paragraphs: [Paragraph(text: "A rower.")])

    private func file(_ filings: Filings, _ message: String, open: Document? = nil,
                      pages: inout [Document], schema: inout Schema) -> FilingRecord {
        Filer.file(filings, message: message, open: (open ?? casperica).id, pages: &pages, schema: &schema)
    }

    /// What the phone's model wrote for it, word for word.
    func testHerNameIsFloricaRenamesThePage() throws {
        var pages = [casperica], schema = Schema()
        var record = file(Filings(facts: [.init(page: "Casperica", field: "Name", value: "Florica")],
                                  pages: [.init(title: "Casperica", type: "Character"), .init(title: "Florica", type: "Character")]),
                          "Her name is Florica", pages: &pages, schema: &schema)
        XCTAssertEqual(pages.map(\.title), ["Florica"])
        XCTAssertTrue(schema.fields.isEmpty)   // no Name field
        XCTAssertEqual(schema.type(pages[0].type)?.name, "Character")
        let rename = try XCTUnwrap(record.actions.first { if case .renamed = $0 { true } else { false } })
        XCTAssertEqual(rename, .renamed(page: casperica.id, was: "Casperica", title: "Florica"))

        _ = record.undo(rename, pages: &pages, schema: &schema)
        XCTAssertEqual(pages[0].title, "Casperica")
    }

    /// Facts about her by the new name land on the same page.
    func testFactsByTheNewNameFindThePage() {
        let age = FieldDefinition(name: "Age", kind: .text)
        let character = PageType(name: "Character", fields: [age.id])
        var schema = Schema(fields: [age], types: [character])
        var her = casperica
        her.type = character.id
        var pages = [her]
        _ = file(Filings(facts: [.init(page: "Casperica", field: "Name", value: "Florica"),
                                 .init(page: "Florica", field: "Age", value: "24")]),
                 "Her name is Florica. She's 24.", pages: &pages, schema: &schema)
        XCTAssertEqual(pages.map(\.title), ["Florica"])
        XCTAssertEqual(pages[0].values[age.id], .text("24"))
    }

    func testAnUntitledPageGetsItsName() {
        let untitled = Document(paragraphs: [Paragraph(text: "A girl who hears the tide.")])
        var pages = [untitled], schema = Schema()
        _ = file(Filings(facts: [.init(page: "she", field: "name", value: "Mara")]),
                 "Her name is Mara", open: untitled, pages: &pages, schema: &schema)
        XCTAssertEqual(pages[0].title, "Mara")

        var again = [untitled], schema2 = Schema()
        _ = file(Filings(facts: [.init(page: "Mara", field: "Name", value: "Mara")],
                         pages: [.init(title: "Mara", type: "Character")]),
                 "Her name is Mara", open: untitled, pages: &again, schema: &schema2)
        XCTAssertEqual(again.map(\.title), ["Mara"])
        XCTAssertTrue(schema2.fields.isEmpty)
    }

    /// Someone else's name, her name repeated, or a guess: no rename.
    func testOtherNamesAndGuessesDontRename() {
        var pages = [casperica], schema = Schema()
        _ = file(Filings(facts: [.init(page: "Casperica", field: "Mother's name", value: "Ilinca")],
                         pages: [.init(title: "Casperica", type: "Character")]),
                 "Her mother's name is Ilinca.", pages: &pages, schema: &schema)
        XCTAssertEqual(pages.first?.title, "Casperica")
        XCTAssertEqual(schema.fields.map(\.name), ["Mother's name"])

        for message in ["Her name is Casperica", "Maybe her name is Florica", "Is her name Florica?"] {
            var pages = [casperica], schema = Schema()
            let record = file(Filings(facts: [.init(page: "Casperica", field: "Name", value: message.contains("Florica") ? "Florica" : "Casperica")]),
                              message, pages: &pages, schema: &schema)
            XCTAssertEqual(pages.map(\.title), ["Casperica"], message)
            XCTAssertTrue(schema.fields.isEmpty, message)
            XCTAssertFalse(record.actions.contains { if case .renamed = $0 { true } else { false } }, message)
        }
    }

    /// The open page further down the list, and a new page made in the same message
    /// (new pages go in near the top): the right page is renamed, nothing else.
    func testTheOpenPageIsRenamedWhereverItIs() {
        let a = Document(title: "Verran", paragraphs: [Paragraph(text: "")])
        let b = Document(title: "Port Vell", paragraphs: [Paragraph(text: "")])
        var pages = [a, b, casperica], schema = Schema()
        _ = file(Filings(facts: [.init(page: "Casperica", field: "Name", value: "Florica"),
                                 .init(page: "Casperica", field: "Rows for", value: "Guild of Oars")],
                         pages: [.init(title: "Casperica", type: "Character"), .init(title: "Guild of Oars", type: "Organization")]),
                 "Her name is Florica. She rows for the Guild of Oars.", pages: &pages, schema: &schema)
        XCTAssertEqual(Set(pages.map(\.title)), ["Verran", "Port Vell", "Florica", "Guild of Oars"])
        XCTAssertEqual(pages.first { $0.id == casperica.id }?.title, "Florica")
        XCTAssertEqual(schema.fields.map(\.name), ["Rows for"])
    }

    /// Part of the name it has already: no rename ("Florica" on "Florica Dragan").
    func testPartOfItsNameIsntARename() {
        let full = Document(title: "Florica Dragan", paragraphs: [Paragraph(text: "")])
        var pages = [full], schema = Schema()
        let record = file(Filings(facts: [.init(page: "Florica Dragan", field: "Name", value: "Florica")]),
                          "Her name is Florica, after her grandmother.", open: full, pages: &pages, schema: &schema)
        XCTAssertEqual(pages[0].title, "Florica Dragan")
        XCTAssertTrue(record.isEmpty)
        XCTAssertTrue(schema.fields.isEmpty)
    }

    /// A later rename waits on Undo for the newer one (newest first).
    func testAnEarlierRenameWaitsForALaterOne() {
        let first = FilingRecord(entries: [.renamed(page: casperica.id, was: "Casperica", title: "Florica")])
        let second = FilingRecord(entries: [.renamed(page: casperica.id, was: "Florica", title: "Flora")])
        let talk = Conversation(page: casperica.id, turns: [first, second].map {
            Conversation.Turn(question: "?", answer: "!", filed: $0)
        })
        XCTAssertTrue(talk.changedLater(first.actions[0], in: talk.turns[0].id))
        XCTAssertFalse(talk.changedLater(second.actions[0], in: talk.turns[1].id))
    }
}

/// A description filed as a "Type" or "Description" field is the page's text when it has none
/// (Kevin, 2026-11-24: "Put that in the page content, not the type").
final class DescribedTests: XCTestCase {
    func testADescriptionBecomesAnEmptyPagesText() throws {
        let place = PageType(name: "Place")
        var isles = Document(title: "The Isles", paragraphs: [Paragraph(text: "")])
        isles.type = place.id
        var pages = [isles], schema = Schema(types: [place])
        var record = Filer.file(Filings(facts: [.init(page: "The Isles", field: "Type", value: "island republic of glassblowers")],
                                        pages: [.init(title: "The Isles", type: "Place")]),
                                message: "It's a island republic of glassblowers", open: isles.id,
                                pages: &pages, schema: &schema)
        XCTAssertEqual(pages[0].paragraphs.map(\.text), ["Island republic of glassblowers"])
        XCTAssertTrue(schema.fields.isEmpty)   // no "Type" field
        _ = record.undo(try XCTUnwrap(record.actions.first), pages: &pages, schema: &schema)
        XCTAssertEqual(pages[0].paragraphs.map(\.text), [""])
    }

    /// A page with writing keeps it, and no description field is made; one word is a type, not a description.
    func testWritingIsKeptAndOneWordIsntADescription() {
        let place = PageType(name: "Place")
        for (writing, field, value, message) in [("Islands of salt.", "Description", "an island republic", "It's an island republic"),
                                                 ("", "Kind", "nation", "It's a nation")] {
            var isles = Document(title: "The Isles", paragraphs: [Paragraph(text: writing)])
            isles.type = place.id
            var pages = [isles], schema = Schema(types: [place])
            let record = Filer.file(Filings(facts: [.init(page: "The Isles", field: field, value: value)]),
                                    message: message, open: isles.id, pages: &pages, schema: &schema)
            XCTAssertTrue(record.isEmpty, field)
            XCTAssertEqual(pages[0].paragraphs.map(\.text), [writing], field)
            XCTAssertTrue(schema.fields.isEmpty, field)
        }
    }
}
