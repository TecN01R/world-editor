import XCTest
@testable import WriterCore

/// Suggestions come only from the author's links and words, and never guess.
final class FieldSuggestionTests: XCTestCase {
    let place = PageType(name: "Place")
    let person = PageType(name: "Character")
    lazy var coast = Document(title: "Map of the Coast", type: place.id)
    lazy var kelloch = Document(title: "Kelloch", type: place.id)
    lazy var ines = Document(title: "Ines", type: person.id)
    let species = FieldDefinition(name: "Species", kind: .choice, options: ["Selkie", "Human"])
    lazy var home = FieldDefinition(name: "Home", kind: .page, pageType: place.id)

    func schema(_ fields: [FieldDefinition]) -> Schema {
        Schema(fields: fields, types: [place, PageType(id: person.id, name: "Character", fields: fields.map(\.id))])
    }

    /// Mara's page: each paragraph is text with an optional `@` link at its end.
    func mara(_ lines: [(String, Document?)], values: [UUID: FieldValue] = [:]) -> Document {
        let paragraphs = lines.map { text, target in
            let links = target.map { [PageLink(location: text.utf16.count - $0.title.utf16.count, length: $0.title.utf16.count, page: $0.id)] }
            return Paragraph(text: text, links: links ?? [])
        }
        return Document(title: "Mara", paragraphs: paragraphs, type: person.id, values: values)
    }

    func suggestions(_ page: Document, _ schema: Schema) -> [FieldSuggestion] {
        let pages = [coast, kelloch, ines]
        return page.fieldSuggestions(schema) { id in pages.first { $0.id == id }?.type }
    }

    func suggest(_ page: Document, _ schema: Schema) -> [FieldValue] { suggestions(page, schema).map(\.value) }

    func testALinkOrAChoiceInTheWritingSuggestsTheField() {
        let page = mara([("She lives at Map of the Coast", coast), ("A selkie from the north.", nil)])
        let found = suggestions(page, schema([species, home]))
        XCTAssertEqual(found.map(\.value), [.text("Selkie"), .page(coast.id)])   // in the type's field order
        XCTAssertEqual(found.map(\.paragraph), [page.paragraphs[1].id, page.paragraphs[0].id])
    }

    func testNothingWhenItWouldBeAGuess() {
        let both = schema([species, home])
        // Two different places, or two different choices: which one?
        XCTAssertEqual(suggest(mara([("Born at Kelloch", kelloch), ("Lives at Map of the Coast", coast)]), both), [])
        XCTAssertEqual(suggest(mara([("Half selkie, half human.", nil)]), both), [])
        // Two fields could take the place.
        let birthplace = FieldDefinition(name: "Birthplace", kind: .page, pageType: place.id)
        XCTAssertEqual(suggest(mara([("Born at Kelloch", kelloch)]), schema([home, birthplace])), [])
        // A page of another type, a word inside a word, a field already set.
        XCTAssertEqual(suggest(mara([("Friends with Ines", ines), ("She hunts selkies.", nil)]), both), [])
        XCTAssertEqual(suggest(mara([("A selkie.", nil)], values: [species.id: .text("Human")]), both), [])
    }

    func testWholeWordsIgnoringCaseAndAccents() {
        XCTAssertTrue(Document.names("Selkie", in: "SELKIE, at last"))
        XCTAssertTrue(Document.names("Eléa", in: "with elea"))
        XCTAssertFalse(Document.names("elk", in: "a selkie"))
        XCTAssertFalse(Document.names("", in: "anything"))
    }
}
