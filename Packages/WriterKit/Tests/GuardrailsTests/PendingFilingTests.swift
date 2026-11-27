import XCTest
@testable import Guardrails
import WriterCore

/// Which of the author's messages still wait to be read (`Filer.pending`), and which are
/// read late (`Filer.isLate`). What waited was kept only in memory, so closing the app lost
/// it (found 2026-11-27); here it's whatever the saved conversation shows was never read.
final class PendingFilingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// A turn the author answered with `message`, `minutes` after `start`.
    private func said(_ message: String, filed: FilingRecord? = nil, minutes: Double = 0) -> Conversation.Turn {
        var turn = Conversation.Turn(question: "Go on.", answer: message, asked: start.addingTimeInterval(minutes * 60 - 30),
                                     filed: filed)
        turn.answered = start.addingTimeInterval(minutes * 60)
        return turn
    }

    private func pending(_ turns: Conversation.Turn...) -> [String] {
        Filer.pending(in: Conversation(page: UUID(), turns: turns)).compactMap(\.answer)
    }

    /// Something filed from a message: a fact on some page.
    private var something: FilingRecord {
        FilingRecord(entries: [.value(page: UUID(), field: UUID(), value: .text("sixty"))])
    }

    /// `something`, with all of it undone.
    private func undone() throws -> FilingRecord {
        var record = something, pages: [Document] = [], schema = Schema()
        _ = record.undo(try XCTUnwrap(record.actions.first), pages: &pages, schema: &schema)
        return record
    }

    func testAMessageNeverReadIsPending() {
        XCTAssertEqual(pending(said("Old Tamsin is a clockmaker.")), ["Old Tamsin is a clockmaker."])
    }

    /// Read, with nothing found: it has its record, and isn't read again on its own (Try
    /// Again still may: `Turn.needsFiling`).
    func testAMessageReadWithNothingFoundIsNotPending() {
        let read = said("Old Tamsin is a clockmaker.", filed: FilingRecord())
        XCTAssertEqual(pending(read), [])
        XCTAssertTrue(read.needsFiling)
        XCTAssertEqual(pending(said("Old Tamsin is a clockmaker.", filed: something)), [])
    }

    /// Everything filed from it was undone: reading it again would bring back what they took back.
    func testAMessageWhoseFilingWasUndoneIsNotPending() throws {
        let record = try undone()
        XCTAssertTrue(record.entries.isEmpty)
        XCTAssertEqual(pending(said("Old Tamsin is a clockmaker.", filed: record)), [])
    }

    /// A message that states nothing is never asked of the model, so it never waits; nor
    /// does a reply still waiting for its answer, or an answer that's only an attachment.
    func testAQuestionIsNotPending() {
        XCTAssertEqual(pending(said("Is Old Tamsin a clockmaker?"), said("Maybe she's a tinker."),
                               Conversation.Turn(question: "Who is she?")), [])
        var talk = Conversation(page: UUID(), aboutWorld: true)
        talk.answer("", attached: [.init(name: "notes.txt", text: "Old Tamsin is a clockmaker.")])
        XCTAssertEqual(talk.turns.count, 1)
        XCTAssertEqual(Filer.pending(in: talk), [])
    }

    func testPendingMessagesComeOldestFirst() {
        XCTAssertEqual(pending(said("Old Tamsin is a clockmaker.", minutes: 1), said("What then?", minutes: 2),
                               said("Mara is twelve.", filed: something, minutes: 3),
                               said("She was expelled for mending clocks for free.", minutes: 4),
                               said("The guild has forty members.", minutes: 5)),
                       ["Old Tamsin is a clockmaker.", "She was expelled for mending clocks for free.",
                        "The guild has forty members."])
    }

    /// Late: something filed from a message sent after it still stands, here or in another
    /// of the world's conversations.
    func testAMessageIsLateOnceSomethingFiledFromALaterOneStands() throws {
        let waiting = said("Actually she's a tinker.", minutes: 10)
        func late(after later: Conversation.Turn..., elsewhere: [Conversation] = []) -> Bool {
            Filer.isLate(waiting.id, in: Conversation(page: UUID(), turns: [said("Old Tamsin is a clockmaker.", filed: something),
                                                                             waiting] + later),
                         elsewhere: elsewhere)
        }
        XCTAssertFalse(late())                                                   // only older ones were filed
        XCTAssertTrue(late(after: said("Mara is twelve.", filed: something, minutes: 11)))
        XCTAssertFalse(late(after: said("Mara is twelve.", minutes: 11)))         // not read yet
        XCTAssertFalse(late(after: said("Mara is twelve.", filed: FilingRecord(), minutes: 11)))   // read, nothing found
        XCTAssertFalse(late(after: said("Mara is twelve.", filed: try undone(), minutes: 11)))      // all taken back

        // Another conversation: by when each was sent.
        func other(minutes: Double, filed: FilingRecord?) -> Conversation {
            Conversation(page: UUID(), turns: [said("The guild has forty members.", filed: filed, minutes: minutes)])
        }
        XCTAssertTrue(late(elsewhere: [other(minutes: 9, filed: something), other(minutes: 12, filed: something)]))
        XCTAssertFalse(late(elsewhere: [other(minutes: 9, filed: something), other(minutes: 12, filed: nil)]))
        XCTAssertFalse(late(elsewhere: [other(minutes: 10, filed: something)]))   // the same moment isn't after

        // The conversation itself among the others (as saved, before this message) isn't another one.
        let talk = Conversation(page: UUID(), turns: [waiting])
        var saved = talk
        saved.turns.append(said("Mara is twelve.", filed: something, minutes: 11))
        XCTAssertFalse(Filer.isLate(waiting.id, in: talk, elsewhere: [saved]))
        XCTAssertTrue(Filer.isLate(waiting.id, in: saved))
        XCTAssertFalse(Filer.isLate(UUID(), in: saved))                           // a turn that isn't there
    }

    /// A late message only adds: its new field, page and sentences go in, but it corrects
    /// no value and renames nothing, though read in time it does both.
    func testALateMessageOnlyAdds() throws {
        let vessel = FieldDefinition(name: "Vessel", kind: .text)
        let character = PageType(name: "Character", fields: [vessel.id])
        let her = Document(title: "Casperica", paragraphs: [Paragraph(text: "A sailor.")], type: character.id,
                           values: [vessel.id: .text("trireme")])
        let filings = Filings(facts: [.init(page: "Casperica", field: "Vessel", value: "bireme"),
                                      .init(page: "Casperica", field: "Name", value: "Florica"),
                                      .init(page: "Casperica", field: "Home", value: "Port Vell")])
        let message = "Actually it's a bireme. Her name is Florica. She sails from Port Vell."
        func file(late: Bool) throws -> (her: Document, pages: [Document], record: FilingRecord) {
            var pages = [her], schema = Schema(fields: [vessel], types: [character])
            let record = Filer.file(filings, message: message, open: her.id, pages: &pages, schema: &schema, late: late)
            return (try XCTUnwrap(pages.first { $0.id == her.id }), pages, record)
        }

        let late = try file(late: true)
        XCTAssertEqual(late.her.title, "Casperica")
        XCTAssertEqual(late.her.values[vessel.id], .text("trireme"))
        XCTAssertFalse(late.record.actions.contains { $0.was != nil })
        XCTAssertFalse(late.record.actions.contains { if case .renamed = $0 { true } else { false } })
        XCTAssertEqual(late.pages.map(\.title), ["Casperica", "Port Vell"])   // a new page, and her Home links it
        XCTAssertTrue(late.her.mentions(late.pages[1].id))
        XCTAssertEqual(late.her.paragraphs.map(\.text), ["A sailor.", "Actually it's a bireme. She sails from Port Vell."])

        let inTime = try file(late: false)
        XCTAssertEqual(inTime.her.title, "Florica")
        XCTAssertEqual(inTime.her.values[vessel.id], .text("bireme"))
    }

    /// All of it together, as the app is to do it: each message of the world's conversation
    /// still to be read, oldest first, with who was in focus when it was sent, and its
    /// record kept whatever came of it. (What the phone's model would write is scripted.)
    func testAConversationIsReadInOrderEachMessageWithItsFocus() throws {
        let first = "Old Tamsin is a clockmaker in the Clockmakers' Guild."
        let second = "She was expelled for mending clocks for free."
        let third = "Now the guild has forty members."
        var talk = Conversation(page: UUID(), aboutWorld: true)
        for (message, reply) in [(first, "A clockmaker!"), (second, "Harsh."), ("What did the guild want from her?", "Money?"),
                                 (third, "That many?"), ("Hm.", "Take your time.")] {
            talk.answer(message)
            talk.ask(reply)
        }
        let read = [first: Filings(facts: [.init(page: "Old Tamsin", field: "Trade", value: "clockmaker"),
                                           .init(page: "Old Tamsin", field: "Guild", value: "Clockmakers' Guild")],
                                   pages: [.init(title: "Old Tamsin", type: "Character"),
                                           .init(title: "Clockmakers' Guild", type: "Organization")]),
                    second: Filings(facts: [.init(page: "she", field: "Expelled for", value: "mending clocks for free")]),
                    third: Filings(facts: [.init(page: "the guild", field: "Members", value: "forty")])]
        var pages: [Document] = [], schema = Schema(), subjects: [String] = []

        XCTAssertEqual(Filer.pending(in: talk).compactMap(\.answer), [first, second, third, "Hm."])   // not the question
        while let turn = Filer.pending(in: talk).first {
            let message = try XCTUnwrap(turn.answer)
            let focus = Filer.focus(before: turn.id, in: talk, pages: pages)
            let prompt = FilingPrompt(world: pages, schema: schema, asked: turn.question, message: message,
                                      focus: focus, saidBefore: Filer.said(before: turn.id, in: talk))
            subjects.append(pages.first { $0.id == focus.first }?.title ?? "nobody")
            XCTAssertEqual(prompt.message.contains("They were last talking about"), !focus.isEmpty, message)
            XCTAssertEqual(prompt.message.contains("Just before, they said"), !focus.isEmpty, message)
            let record = Filer.file(read[message] ?? Filings(), message: message, open: talk.page, pages: &pages, schema: &schema,
                                    late: Filer.isLate(turn.id, in: talk), focus: focus)
            talk.turns[try XCTUnwrap(talk.turns.firstIndex { $0.id == turn.id })].filed = record   // even when empty
        }
        XCTAssertEqual(subjects, ["nobody", "Old Tamsin", "Old Tamsin", "Clockmakers' Guild"])

        XCTAssertEqual(pages.map(\.title), ["Old Tamsin", "Clockmakers' Guild"])
        XCTAssertEqual(pages[0].paragraphs.map(\.text), [first, second])
        XCTAssertEqual(pages[1].paragraphs.map(\.text), [third])
        XCTAssertEqual(pages[0].fieldLines(schema.fields(of: schema.type(pages[0].type))) { id in pages.first { $0.id == id }?.title },
                       ["Trade: clockmaker", "Guild: Clockmakers' Guild", "Expelled for: mending clocks for free"])
        XCTAssertEqual(pages[1].fieldLines(schema.fields(of: schema.type(pages[1].type))) { _ in nil }, ["Members: forty"])
        XCTAssertNil(talk.turns[2].filed)                                // the question was never asked of the model
        XCTAssertEqual(talk.turns[4].filed?.filedNothing, true)          // "Hm." was read, and found nothing
    }
}
