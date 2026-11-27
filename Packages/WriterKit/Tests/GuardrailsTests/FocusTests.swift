import XCTest
@testable import Guardrails
import WriterCore

/// Who the author was last talking about in the world's conversation (`Filer.focus`): the
/// page "she", or part of a name, means when no page is open (the fault found in the
/// phone's log, 2026-11-27: after "Old Tamsin is a clockmaker", "She was expelled for
/// mending clocks for free." never reached her page).
final class FocusTests: XCTestCase {
    private let tamsin = Document(title: "Old Tamsin", paragraphs: [Paragraph(text: "")])
    private let guild = Document(title: "The Clockmakers' Guild", paragraphs: [Paragraph(text: "")])
    private let mara = Document(title: "Mara", paragraphs: [Paragraph(text: "")])
    private var pages: [Document] { [tamsin, guild, mara] }
    private let expelled = "She was expelled for mending clocks for free."

    /// The world's conversation: what the author said, each with what was filed from it,
    /// then the message being filed now, whose turn is returned.
    private func conversation(_ said: [(message: String, filed: FilingRecord?)]) -> (talk: Conversation, now: UUID) {
        var turns = said.map { Conversation.Turn(question: "Go on.", answer: $0.message, filed: $0.filed) }
        turns.append(Conversation.Turn(question: "Go on.", answer: expelled))
        return (Conversation(page: UUID(), turns: turns, aboutWorld: true), turns[turns.count - 1].id)
    }

    private func focus(_ said: [(message: String, filed: FilingRecord?)], pages: [Document]? = nil) -> [UUID] {
        let (talk, now) = conversation(said)
        return Filer.focus(before: now, in: talk, pages: pages ?? self.pages)
    }

    /// A fact filed on a page by a message that doesn't name it ("She is sixty.").
    private func filed(on page: Document) -> FilingRecord {
        FilingRecord(entries: [.value(page: page.id, field: UUID(), value: .text("sixty"))])
    }

    /// That example, start to finish: the first message is filed on Old Tamsin, so
    /// she is who the second one's "She" means, and its sentence reaches her page.
    func testTheSubjectIsThePageTheLastMessageWasFiledOn() throws {
        let world = UUID()
        var pages = self.pages, schema = Schema()
        let first = Filer.file(Filings(facts: [.init(page: "Old Tamsin", field: "Trade", value: "clockmaker")],
                                       pages: [.init(title: "Old Tamsin", type: "Character")]),
                               message: "Old Tamsin is a clockmaker.", open: world, pages: &pages, schema: &schema)
        let (talk, now) = conversation([("Old Tamsin is a clockmaker.", first)])
        let focus = Filer.focus(before: now, in: talk, pages: pages)
        XCTAssertEqual(focus, [tamsin.id])
        XCTAssertEqual(Filer.said(before: now, in: talk), "Old Tamsin is a clockmaker.")

        _ = Filer.file(Filings(facts: [.init(page: "she", field: "Expelled for", value: "mending clocks for free")]),
                       message: expelled, open: world, pages: &pages, schema: &schema, focus: focus)
        let her = try XCTUnwrap(pages.first { $0.id == tamsin.id })
        XCTAssertEqual(her.paragraphs.map(\.text), ["Old Tamsin is a clockmaker.", expelled])
        XCTAssertEqual(Set(her.values.values), [.text("clockmaker"), .text("mending clocks for free")])
    }

    /// From one message: the pages it was filed on, then the ones it made or linked, then
    /// the ones it only names.
    func testFiledOnComesBeforeMadeOrLinkedAndThenNamed() {
        let record = FilingRecord(entries: [
            .created(page: mara.id, modified: Date()),
            .value(page: tamsin.id, field: UUID(), value: .page(mara.id)),
            .placed(Placement(page: tamsin.id, paragraphs: [], texts: [])),
        ])
        XCTAssertEqual(focus([("She trained Mara before the Clockmakers' Guild took her in.", record)]),
                       [tamsin.id, mara.id, guild.id])
        // A page it only put a sentence on, or (before 2026-11-26) a description, was filed on too.
        XCTAssertEqual(focus([("It meets at midnight.", FilingRecord(entries: [.placed(Placement(page: guild.id, paragraphs: [], texts: []))]))]),
                       [guild.id])
        XCTAssertEqual(focus([("A tinker.", FilingRecord(entries: [.described(page: mara.id, text: "A tinker")]))]), [mara.id])
        // Giving a page a type files nothing on it.
        XCTAssertEqual(focus([("She's a person.", FilingRecord(entries: [.typed(page: mara.id, type: UUID())]))]), [])
    }

    /// Asking about a page is talking about it, though nothing is filed from a question;
    /// and the newest message comes first, whatever an older one was filed on.
    func testAQuestionNamingAPageCounts() {
        XCTAssertEqual(focus([("What do I have on the clockmakers' guild?", nil)]), [guild.id])
        XCTAssertEqual(focus([("Old Tamsin is sixty.", filed(on: tamsin)), ("What do I have on the Clockmakers' Guild?", nil)]),
                       [guild.id, tamsin.id])
        // A message read with nothing found, naming a page, counts the same.
        XCTAssertEqual(focus([("Tell me about Mara.", FilingRecord())]), [mara.id])
    }

    /// Their last three messages, and no further back.
    func testItLooksBackThreeMessages() {
        let nothing: [(message: String, filed: FilingRecord?)] = [("Go on.", nil), ("Yes.", nil)]
        XCTAssertEqual(focus([("She is sixty.", filed(on: tamsin))] + nothing), [tamsin.id])
        XCTAssertEqual(focus([("She is sixty.", filed(on: tamsin))] + nothing + [("Hm.", nil)]), [])
        // Each of the three adds its own, the newest first.
        XCTAssertEqual(focus([("Is Mara in it?", nil), ("She is sixty.", filed(on: tamsin)), ("And the Clockmakers' Guild?", nil)]),
                       [guild.id, tamsin.id, mara.id])
        // The first message of a conversation has nobody before it, nor has a turn that isn't in it.
        let (talk, now) = conversation([])
        XCTAssertEqual(Filer.focus(before: now, in: talk, pages: pages), [])
        XCTAssertNil(Filer.said(before: now, in: talk))
        let (other, _) = conversation([("Old Tamsin is sixty.", nil)])
        XCTAssertEqual(Filer.focus(before: UUID(), in: other, pages: pages), [])
    }

    /// A page that's gone can't be meant, nor one with no name; and what a message filed
    /// stops counting once any of it is undone, though the pages it names itself still do.
    func testPagesThatAreGoneAndUndoneFilingsAreLeftOut() throws {
        // Deleted since: filed on, and named.
        XCTAssertEqual(focus([("Mara is sixty.", filed(on: mara))], pages: [tamsin, guild]), [])
        // No title and nothing written: nothing to call it in the prompt.
        let nameless = Document(title: "", paragraphs: [Paragraph(text: "")])
        XCTAssertEqual(focus([("She is sixty.", filed(on: nameless))], pages: pages + [nameless]), [])

        var pages = self.pages, schema = Schema()
        var record = FilingRecord(entries: [.value(page: tamsin.id, field: UUID(), value: .text("sixty")),
                                            .placed(Placement(page: tamsin.id, paragraphs: [], texts: []))])
        XCTAssertEqual(focus([("She is sixty.", record)]), [tamsin.id])
        _ = record.undo(try XCTUnwrap(record.actions.first), pages: &pages, schema: &schema)
        XCTAssertFalse(record.isEmpty)   // her sentence is still there, but they took the fact back
        XCTAssertEqual(focus([("She is sixty.", record)]), [])
        XCTAssertEqual(focus([("Old Tamsin is sixty.", record)]), [tamsin.id])   // they did name her
        // An older message's filing still stands.
        XCTAssertEqual(focus([("Mara is twelve.", filed(on: mara)), ("She is sixty.", record)]), [mara.id])
    }

    /// Titles are named as whole words, whatever their case or apostrophes, with or without
    /// "The"; the longest wins its words; under three letters is never a name.
    func testWhichPagesAMessageNames() {
        let forge = Document(title: "Mara's Forge", paragraphs: [Paragraph(text: "")])
        let al = Document(title: "Al", paragraphs: [Paragraph(text: "")])
        let untitled = Document(paragraphs: [Paragraph(text: "A bell that rings at noon")])
        let pages = [tamsin, guild, mara, forge, al, untitled]
        func named(_ message: String) -> [UUID] { Filer.named(in: message, pages: pages) }
        XCTAssertEqual(named("old tamsin left the Clockmakers\u{2019} Guild."), [tamsin.id, guild.id])
        XCTAssertEqual(named("Clockmakers' Guild rules bind Old Tamsin."), [guild.id, tamsin.id])   // in the order named
        XCTAssertEqual(named("Mara's Forge is cold."), [forge.id])                                   // not Mara as well
        XCTAssertEqual(named("Mara's Forge is where Mara works."), [forge.id, mara.id])
        XCTAssertEqual(named("Tamara and Al left."), [])                                             // not inside a word; too short
        XCTAssertEqual(named("I love a bell that rings at noon."), [untitled.id])                    // an untitled page's first line
        // Two pages with one title: the first, as filing finds it.
        let twin = Document(title: "mara", paragraphs: [Paragraph(text: "")])
        XCTAssertEqual(Filer.named(in: "Mara and Mara.", pages: [mara, twin]), [mara.id])
    }

    /// What they said just before: the author's last message, whatever the companion replied.
    func testWhatTheySaidJustBefore() {
        let (talk, now) = conversation([("Old Tamsin is a clockmaker.", nil), ("What about Mara?", nil)])
        XCTAssertEqual(Filer.said(before: now, in: talk), "What about Mara?")
        XCTAssertEqual(Filer.said(before: talk.turns[1].id, in: talk), "Old Tamsin is a clockmaker.")
        XCTAssertNil(Filer.said(before: talk.turns[0].id, in: talk))
        XCTAssertNil(Filer.said(before: UUID(), in: talk))
    }
}
