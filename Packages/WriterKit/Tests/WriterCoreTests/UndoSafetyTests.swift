import XCTest
@testable import WriterCore

/// What the second review of Undo found (2026-11-24): a page worked on since is kept,
/// newest first spans the world's conversations, and filing's types and fields go
/// once nothing uses them, whichever message made them.
final class UndoSafetyTests: XCTestCase {
    let ruler = UUID(), nation = UUID(), vessel = UUID()

    private func made(_ page: Document, with entries: [FilingRecord.Entry] = []) -> FilingRecord {
        FilingRecord(entries: [.created(page: page.id, modified: page.modified)] + entries)
    }

    /// A value this message filed on the page, changed by hand since: kept.
    func testAPageWhoseFiledValueWasChangedIsKept() throws {
        var myriddea = Document(title: "Myriddea", paragraphs: [Paragraph(text: "")])
        var record = made(myriddea, with: [.value(page: myriddea.id, field: ruler, value: .text("a council"))])
        myriddea.values[ruler] = .text("the Council of Five")   // the author's edit; `modified` unchanged
        var pages = [myriddea], schema = Schema()
        let undone = try XCTUnwrap(record.undo(record.actions[0], pages: &pages, schema: &schema))
        XCTAssertTrue(undone.edited)
        XCTAssertEqual(pages.count, 1)
    }

    /// Talked about in its own conversation: kept.
    func testAPageTalkedAboutIsKept() throws {
        let myriddea = Document(title: "Myriddea", paragraphs: [Paragraph(text: "")])
        var record = made(myriddea)
        var pages = [myriddea], schema = Schema()
        let undone = try XCTUnwrap(record.undo(record.actions[0], pages: &pages, schema: &schema, kept: { $0 == myriddea.id }))
        XCTAssertTrue(undone.edited)
    }

    /// A later correction away from a link to the page waits on its Undo.
    func testAPageWaitsForACorrectionAwayFromIt() {
        let myriddea = UUID(), portVell = UUID(), her = UUID()
        let first = FilingRecord(entries: [.created(page: myriddea, modified: Date()),
                                           .value(page: her, field: nation, value: .page(myriddea))])
        let second = FilingRecord(entries: [.replaced(page: her, field: nation, was: .page(myriddea), value: .page(portVell))])
        let talk = Conversation(page: her, turns: [first, second].map { Conversation.Turn(question: "?", answer: "!", filed: $0) })
        XCTAssertTrue(talk.changedLater(first.actions[0], in: talk.turns[0].id))
    }

    /// A correction filed from another page's conversation, after this one, waits on its Undo.
    func testNewestFirstSpansTheWorldsConversations() {
        let her = UUID(), elsewhere = UUID()
        let mine = Conversation(page: her, turns: [Conversation.Turn(
            question: "?", answer: "a trireme", asked: Date(timeIntervalSince1970: 100),
            filed: FilingRecord(entries: [.value(page: her, field: vessel, value: .text("trireme"))]))])
        var later = Conversation.Turn(question: "?", answer: "actually she sails a bireme", asked: Date(timeIntervalSince1970: 200),
                                      filed: FilingRecord(entries: [.replaced(page: her, field: vessel, was: .text("trireme"), value: .text("bireme"))]))
        let other = Conversation(page: elsewhere, turns: [later])
        let trireme = mine.turns[0].filed!.actions[0]
        XCTAssertTrue(mine.changedLater(trireme, in: mine.turns[0].id, elsewhere: [other]))
        later.asked = Date(timeIntervalSince1970: 50)   // filed before this one: no bearing
        XCTAssertFalse(mine.changedLater(trireme, in: mine.turns[0].id, elsewhere: [Conversation(page: elsewhere, turns: [later])]))
    }

    /// A field one message made, last used by another message's value: goes when that's undone.
    func testFilingsFieldsGoOnceNothingUsesThem() throws {
        let field = FieldDefinition(name: "Vessel", kind: .text)
        let character = PageType(name: "Character", fields: [field.id])
        var schema = Schema(fields: [field], types: [character])
        var mara = Document(title: "Mara", paragraphs: [Paragraph(text: "")])
        mara.type = character.id
        mara.values[field.id] = .text("galley")
        let first = FilingRecord(entries: [.newField(field.id), .fieldAdded(type: character.id, field: field.id)])
        var second = FilingRecord(entries: [.value(page: mara.id, field: field.id, value: .text("galley"))])
        var pages = [mara]
        _ = second.undo(second.actions[0], pages: &pages, schema: &schema)
        XCTAssertEqual(schema.fields.count, 1)   // its own record has no schema entries...
        FilingRecord.tidy(first.entries, pages: pages, schema: &schema)
        XCTAssertTrue(schema.fields.isEmpty)     // ...the world's tidy takes it
        XCTAssertTrue(schema.types[0].fields.isEmpty)
    }

    /// Undoing a page also takes the field its own message made to link to it.
    func testAPagesOwnLinkFieldGoesWithIt() throws {
        let field = FieldDefinition(name: "Nation", kind: .page)
        let character = PageType(name: "Character", fields: [field.id])
        var schema = Schema(fields: [field], types: [character])
        let myriddea = Document(title: "Myriddea", paragraphs: [Paragraph(text: "")])
        var her = Document(title: "Casperica", paragraphs: [Paragraph(text: "")])
        her.type = character.id
        her.values[field.id] = .page(myriddea.id)
        var record = FilingRecord(entries: [.created(page: myriddea.id, modified: myriddea.modified), .newField(field.id),
                                            .fieldAdded(type: character.id, field: field.id),
                                            .value(page: her.id, field: field.id, value: .page(myriddea.id))])
        var pages = [her, myriddea]
        _ = record.undo(record.actions[0], pages: &pages, schema: &schema)
        XCTAssertEqual(pages.map(\.title), ["Casperica"])
        XCTAssertTrue(schema.fields.isEmpty)
        XCTAssertTrue(record.isEmpty)
    }

    /// Across conversations, Undo goes by when things were filed, not when they were said.
    func testNewestFirstGoesByWhenFiled() {
        let her = UUID(), elsewhere = UUID()
        var mine = Conversation.Turn(question: "?", answer: "a trireme", asked: Date(timeIntervalSince1970: 100),
                                     filed: FilingRecord(entries: [.value(page: her, field: vessel, value: .text("trireme"))]))
        mine.filed?.date = Date(timeIntervalSince1970: 300)   // filed late (a reply that waited)
        var other = Conversation.Turn(question: "?", answer: "actually a bireme", asked: Date(timeIntervalSince1970: 200),
                                      filed: FilingRecord(entries: [.replaced(page: her, field: vessel, was: .text("trireme"), value: .text("bireme"))]))
        other.filed?.date = Date(timeIntervalSince1970: 250)
        let talk = Conversation(page: her, turns: [mine])
        XCTAssertFalse(talk.changedLater(mine.filed!.actions[0], in: mine.id, elsewhere: [Conversation(page: elsewhere, turns: [other])]))
    }

    /// A type filing made, whose only page is in Recently Deleted, stays.
    func testAPageInRecentlyDeletedStillUsesItsType() throws {
        let ship = PageType(name: "Ship")
        var schema = Schema(types: [ship])
        var gull = Document(title: "Gull", paragraphs: [Paragraph(text: "")])
        gull.type = ship.id
        FilingRecord.tidy([.newType(ship.id)], pages: [gull], schema: &schema)
        XCTAssertEqual(schema.types.count, 1)
        FilingRecord.tidy([.newType(ship.id)], pages: [], schema: &schema)
        XCTAssertTrue(schema.types.isEmpty)
    }
}
