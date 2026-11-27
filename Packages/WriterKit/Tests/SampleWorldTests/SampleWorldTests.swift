import XCTest
import SampleWorld
import WriterCore

/// The sample world holds together: it's the same every time, every id in it leads somewhere,
/// what its conversations say they filed is what's in its pages, and the app's stores give it
/// back as written.
final class SampleWorldTests: XCTestCase {
    private typealias ID = SampleWorld.ID

    private let now = Date(timeIntervalSince1970: 1_800_000_000.25)
    private lazy var sample = SampleWorld.contents(now: now)
    private var today: Conversation { sample.conversations[0] }
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sample-\(UUID())", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func page(_ id: UUID) throws -> Document {
        try XCTUnwrap((sample.pages + sample.deleted).first { $0.id == id })
    }

    private func written(_ page: Document) -> [Paragraph] {
        page.paragraphs.filter { !$0.text.allSatisfy(\.isWhitespace) }
    }

    /// Every record filed in `conversations`, with the turn it's on.
    private func records(in conversations: [Conversation]) -> [(turn: Conversation.Turn, record: FilingRecord)] {
        conversations.flatMap(\.turns).compactMap { turn in turn.filed.map { (turn, $0) } }
    }

    /// A text's words alone: its letters and digits, whatever their case, punctuation and spacing.
    private func words(_ text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    // MARK: The same every time

    func testTwoCallsWithTheSameNowAreEqual() {
        XCTAssertEqual(SampleWorld.contents(now: now), SampleWorld.contents(now: now))
        XCTAssertEqual(SampleWorld.empty(), SampleWorld.empty())
    }

    func testEverythingIsDatedBackFromNow() {
        let day: TimeInterval = 86_400
        let later = SampleWorld.contents(now: now.addingTimeInterval(day))
        XCTAssertEqual(later.pages.map(\.id), sample.pages.map(\.id))
        for (page, moved) in zip(sample.pages + sample.deleted, later.pages + later.deleted) {
            XCTAssertLessThan(page.modified, now)
            XCTAssertEqual(moved.modified.timeIntervalSince(page.modified), day, accuracy: 0.001)
            // What the author wrote and filled in is the same whenever it's made: a field's date isn't moved.
            XCTAssertEqual(moved.paragraphs, page.paragraphs)
            XCTAssertEqual(moved.values, page.values)
        }
        for (talk, moved) in zip(sample.conversations, later.conversations) {
            XCTAssertEqual(moved.lastActive!.timeIntervalSince(talk.lastActive!), day, accuracy: 0.001)
            XCTAssertEqual(moved.turns.map(\.answer), talk.turns.map(\.answer))
        }
    }

    func testPagesAreMostRecentlyEditedFirst() {
        let dates = sample.pages.map(\.modified)
        XCTAssertEqual(dates, dates.sorted(by: >))
        XCTAssertEqual(Set(dates).count, dates.count)   // no two at once, so the order is the same from disk
    }

    func testConversationsRunInOrderNewestFirst() throws {
        let last = try sample.conversations.map { try XCTUnwrap($0.lastActive) }
        XCTAssertEqual(last, last.sorted(by: >))
        for talk in sample.conversations {
            XCTAssertTrue(talk.aboutWorld)
            XCTAssertEqual(talk.turns.first?.question, "")   // the author began
            XCTAssertNotNil(talk.title)
            var before = Date.distantPast
            for turn in talk.turns {
                XCTAssertGreaterThanOrEqual(turn.asked, before)
                before = turn.asked
                XCTAssertEqual(turn.answer == nil, turn.answered == nil)
                if let answered = turn.answered {
                    XCTAssertGreaterThanOrEqual(answered, before)
                    before = answered
                }
                // What they said is read after they said it.
                if let filed = turn.filed?.date {
                    XCTAssertGreaterThan(filed, before)
                    XCTAssertLessThan(filed, now)
                }
            }
            XCTAssertLessThan(before, now)
        }
        // Today, yesterday, last week and last month.
        let ago = last.map { now.timeIntervalSince($0) / 86_400 }
        XCTAssertLessThan(ago[0], 0.5)
        XCTAssertTrue((1..<1.5).contains(ago[1]))
        XCTAssertTrue((7..<11).contains(ago[2]))
        XCTAssertTrue((29..<50).contains(ago[3]))
    }

    // MARK: The world

    func testFourKindsWithAFieldOfEveryKindFilledSomewhere() {
        XCTAssertEqual(Set(sample.schema.types.map(\.name)), ["Character", "Place", "Group", "Chapter"])
        let used = sample.schema.types.flatMap { sample.schema.fields(of: $0) }
        XCTAssertEqual(Set(used.map(\.id)), Set(sample.schema.fields.map(\.id)))   // every field is some kind's
        XCTAssertEqual(Set(used.map(\.kind)), Set(FieldDefinition.Kind.allCases))
        let filled = used.filter { field in sample.pages.contains { $0.values[field.id] != nil } }
        XCTAssertEqual(Set(filled.map(\.kind)), Set(FieldDefinition.Kind.allCases))
        XCTAssertEqual(sample.schema.fields(of: sample.schema.type(ID.Kind.character)).prefix(5).map(\.name),
                       ["Species", "Age", "Home", "First seen", "Keeps a secret"])
    }

    func testEveryIdLeadsSomewhere() throws {
        let live = Set(sample.pages.map(\.id)), deleted = Set(sample.deleted.map(\.id))
        let types = Set(sample.schema.types.map(\.id)), fields = Set(sample.schema.fields.map(\.id))
        XCTAssertEqual(live.count, sample.pages.count)
        XCTAssertTrue(live.isDisjoint(with: deleted))
        let paragraphs = (sample.pages + sample.deleted).flatMap(\.paragraphs).map(\.id)
        XCTAssertEqual(Set(paragraphs).count, paragraphs.count)
        XCTAssertTrue(sample.pages.allSatisfy { $0.deleted == nil })
        XCTAssertEqual(sample.deleted.map(\.id), [ID.captainHale])
        XCTAssertTrue(sample.deleted.allSatisfy { $0.deleted != nil })

        var links: Set<[UUID]> = []   // each `@` link: the page it's on, and the page it's to
        for page in sample.pages + sample.deleted {
            if let type = page.type { XCTAssertTrue(types.contains(type), page.displayName) }
            let own = Set(sample.schema.fields(of: sample.schema.type(page.type)).map(\.id))
            for (field, value) in page.values {
                XCTAssertTrue(own.contains(field), "\(page.displayName) has a value its kind has no field for")
                if case .page(let id) = value { XCTAssertTrue(live.contains(id), page.displayName) }
                // A field that takes only one kind of page holds one of that kind.
                if case .page(let id) = value, let only = sample.schema.fields.first(where: { $0.id == field })?.pageType {
                    XCTAssertEqual(try self.page(id).type, only, page.displayName)
                }
            }
            for paragraph in page.paragraphs {
                for link in paragraph.links {
                    links.insert([page.id, link.page])
                    // An `@` link's words are its page's title, as the app keeps them.
                    let words = Array(paragraph.text.utf16)[link.location..<(link.location + link.length)]
                    XCTAssertEqual(String(decoding: words, as: UTF16.self), try self.page(link.page).title)
                    XCTAssertTrue(live.contains(link.page))
                }
            }
        }
        XCTAssertEqual(links, [[ID.harbourNotes, ID.oldTamsin], [ID.harbourNotes, ID.mara],
                               [ID.breakwater, ID.clockmakersGuild], [ID.mapOfTheCoast, ID.lighthouse]])

        XCTAssertEqual(sample.unseen.count, 2)
        XCTAssertTrue(sample.unseen.isSubset(of: live))
        XCTAssertEqual(sample.lastConversation, ID.conversationToday)
        XCTAssertEqual(sample.conversations.map(\.page), [ID.conversationToday, ID.conversationYesterday,
                                                          ID.conversationLastWeek, ID.conversationLastMonth])
        XCTAssertTrue(Set(sample.conversations.map(\.page)).isDisjoint(with: live.union(deleted)))

        for (_, record) in records(in: sample.conversations) {
            for entry in record.entries {
                if let page = entry.page { XCTAssertTrue(live.contains(page) || deleted.contains(page)) }
                if let field = entry.field { XCTAssertTrue(fields.contains(field)) }
                if let linked = entry.linked { XCTAssertTrue(live.contains(linked)) }
                switch entry {
                case .typed(_, let type), .newType(let type): XCTAssertTrue(types.contains(type))
                case .newField(let field): XCTAssertTrue(fields.contains(field))
                case .fieldAdded(let type, let field):
                    XCTAssertEqual(sample.schema.type(type)?.fields.contains(field), true)
                case .created, .value, .replaced, .renamed, .described, .placed: break
                }
            }
        }
        // One record's page is in Recently Deleted, as the app still names it there.
        let made = records(in: [sample.conversations[3]]).flatMap(\.record.entries)
        XCTAssertEqual(made.compactMap(\.page), [ID.captainHale])
    }

    func testThePagesTheAppHasToShow() throws {
        XCTAssertEqual(sample.pages.count, 13)

        let notes = try page(ID.harbourNotes)
        XCTAssertNil(notes.type)
        XCTAssertEqual(notes.paragraphs[0].runs, [StyleRun(location: 17, length: 6, style: .italic)])   // "faster"
        XCTAssertEqual(notes.paragraphs[4].runs, [StyleRun(location: 10, length: 5, style: .bold)])     // "north"
        XCTAssertEqual(notes.paragraphs[5].links, [PageLink(location: 4, length: 4, page: ID.mara)])
        XCTAssertEqual(notes.paragraphs.map(\.kind), [.body, .bullet, .bullet, .bullet, .numbered, .numbered])

        let long = try page(ID.chapterTwo)
        XCTAssertTrue((85...95).contains(long.title.count), "\(long.title.count)")

        let untitled = try page(ID.untitled)
        XCTAssertEqual(untitled.title, "")
        XCTAssertEqual(untitled.paragraphs.count, 1)
        XCTAssertEqual(untitled.displayName.count, 80)   // named by its one line, as far as lists show it

        let jory = try page(ID.jory)
        XCTAssertEqual(jory.type, ID.Kind.character)
        XCTAssertTrue(written(jory).isEmpty)
        XCTAssertFalse(jory.values.isEmpty)

        // Several people and places with a few paragraphs and their fields filled.
        for id in [ID.mara, ID.oldTamsin, ID.breakwater, ID.lighthouse, ID.ironAbbey] {
            let page = try page(id)
            XCTAssertGreaterThanOrEqual(written(page).count, 3, page.title)
            XCTAssertGreaterThanOrEqual(page.values.count, 2, page.title)
        }
        XCTAssertEqual(try page(ID.mara).values.count, 5)
    }

    func testTheRumourIsOneByTheMapsRuleAndIsNamedElsewhere() throws {
        let rumour = try page(ID.masterCorwen)
        let map = WorldMap(pages: sample.pages, schema: sample.schema)
        XCTAssertEqual(map.cards.count, sample.pages.count)
        XCTAssertEqual(map.cards.filter(\.isRumour).map(\.id), [rumour.id])
        XCTAssertTrue(map.lines.contains([rumour.id, ID.oldTamsin]))
        let mentions = WikiEntry.mentions(of: rumour, in: sample.pages, schema: sample.schema)
        XCTAssertEqual(mentions.map(\.page), [ID.oldTamsin])
        XCTAssertEqual(mentions.first?.quote, "She learned the trade from Master Corwen.")
        XCTAssertTrue(sample.unseen.contains(rumour.id))
    }

    func testPagesNameEachOther() throws {
        let mentioned = sample.pages.filter { !WikiEntry.mentions(of: $0, in: sample.pages, schema: sample.schema).isEmpty }
        XCTAssertGreaterThanOrEqual(mentioned.count, 3)
        // A name in the writing, with no `@` link, is linked as a wiki links it.
        let abbey = try page(ID.ironAbbey)
        let named = abbey.paragraphs.flatMap { WikiEntry.pieces(of: $0.text, linking: sample.pages, except: abbey.id) }
            .compactMap(\.page)
        XCTAssertEqual(named, [ID.lighthouse, ID.clockmakersGuild, ID.oldTamsin])
        XCTAssertTrue(abbey.paragraphs.allSatisfy(\.links.isEmpty))
        // Mara is named in writing, linked with `@`, and held by a field.
        let mara = WikiEntry.mentions(of: try page(ID.mara), in: sample.pages, schema: sample.schema)
        XCTAssertTrue(mara.contains { $0.page == ID.harbourNotes && $0.quote == "Ask Mara about the bell" })
        XCTAssertTrue(mara.contains { $0.page == ID.lighthouse && $0.quote == "Mara keeps it." })
        XCTAssertTrue(mara.contains { $0.page == ID.nightTheBellRang })
    }

    func testTheChapterIsLongAndTypedPlainly() throws {
        let chapter = try page(ID.nightTheBellRang)
        XCTAssertEqual(sample.schema.type(chapter.type)?.name, "Chapter")
        let text = chapter.paragraphs.map(\.text).joined(separator: "\n")
        let count = text.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) }.count
        XCTAssertTrue((1_100...1_300).contains(count), "\(count) words")
        // Paragraphs of every length, from a word to a long one.
        let lengths = chapter.paragraphs.map { $0.text.split(separator: " ").count }
        XCTAssertLessThanOrEqual(lengths.min()!, 2)
        XCTAssertGreaterThanOrEqual(lengths.max()!, 70)
        // Typed with straight quotes, hyphens and dots, which print sets every one of its ways.
        XCTAssertFalse(text.contains { "\u{201C}\u{201D}\u{2018}\u{2019}\u{2014}\u{2026}".contains($0) })
        let replacements = Set(Typeset.changes(in: text).map(\.replacement))
        XCTAssertEqual(replacements, ["\u{201C}", "\u{201D}", "\u{2019}", "\u{2014}", "\u{2026}"])
        XCTAssertGreaterThanOrEqual(text.components(separatedBy: "--").count - 1, 3)
        XCTAssertGreaterThanOrEqual(text.components(separatedBy: "...").count - 1, 3)
    }

    // MARK: The conversations

    private func name(_ entry: FilingRecord.Entry) -> String {
        switch entry {
        case .typed: "typed"
        case .created: "created"
        case .value: "value"
        case .replaced: "replaced"
        case .renamed: "renamed"
        case .described: "described"
        case .placed: "placed"
        case .newType: "newType"
        case .newField: "newField"
        case .fieldAdded: "fieldAdded"
        }
    }

    func testTodaysConversationFilesEveryKindOfThing() {
        XCTAssertTrue((8...10).contains(today.turns.count))
        let entries = today.turns.compactMap(\.filed).flatMap(\.entries)
        XCTAssertEqual(Set(entries.map(name)), ["typed", "created", "value", "replaced", "renamed", "described", "placed",
                                                 "newType", "newField", "fieldAdded"])
        XCTAssertEqual(Set(entries).count, entries.count)   // each its own line, with its own Undo
        // As the app files from the world's conversation: no page was open to see, and each is dated.
        for (turn, record) in records(in: sample.conversations) {
            XCTAssertEqual(record.seen, [:])
            XCTAssertNil(record.seenTitle)
            XCTAssertFalse(record.undid)
            XCTAssertNotNil(record.date)
            XCTAssertNotNil(turn.answer)
        }
    }

    func testTodaysConversationShowsEveryStateOfATurn() throws {
        let turns = today.turns
        // Read, and nothing found to file.
        XCTAssertEqual(turns.filter { $0.filed?.filedNothing == true }.count, 1)
        // Said, and not read yet: the last thing the author said.
        let unread = turns.filter { $0.answer != nil && $0.filed == nil }
        XCTAssertEqual(unread.map(\.id), [turns[turns.count - 2].id])
        XCTAssertTrue(unread[0].needsFiling)
        XCTAssertFalse(try XCTUnwrap(unread[0].answer).contains("?"))   // it states things
        // The reply waiting for the author is the latest of three tries.
        let waiting = try XCTUnwrap(today.waiting)
        XCTAssertEqual(waiting.id, turns.last?.id)
        XCTAssertEqual(waiting.versions?.count, 3)
        XCTAssertEqual(waiting.versions?.last, waiting.question)
        XCTAssertEqual(Set(waiting.versions ?? []).count, 3)
        // What a reply searched for, looked up and added is kept under that reply's own words.
        let searched = try XCTUnwrap(turns.first { $0.searches != nil })
        XCTAssertFalse(try XCTUnwrap(searched.searches?[searched.question]).isEmpty)
        let lookedUp = try XCTUnwrap(turns.first { $0.lookups != nil })
        let source = try XCTUnwrap(lookedUp.lookups?[lookedUp.question]?.first?.sources.first)
        XCTAssertEqual(source.url.host, "en.wikipedia.org")
        let instructed = try XCTUnwrap(turns.first { $0.instructions != nil })
        XCTAssertEqual(instructed.instructions?[instructed.question], sample.instructions.map { [$0] })
        let sent = try XCTUnwrap(turns.first { $0.attached != nil })
        let attached = try XCTUnwrap(sent.attached?.first)
        XCTAssertFalse(attached.text.isEmpty)
        XCTAssertNil(attached.picture)
        // Each on a turn of its own.
        XCTAssertEqual(Set([searched.id, lookedUp.id, instructed.id, sent.id, waiting.id]).count, 5)
    }

    func testTheOtherConversations() {
        let yesterday = sample.conversations[1], lastWeek = sample.conversations[2], lastMonth = sample.conversations[3]
        XCTAssertLessThanOrEqual(yesterday.turns.count, 4)
        XCTAssertNil(yesterday.waiting)                      // it ends on the author's words
        XCTAssertNotNil(yesterday.turns.last?.answer)
        XCTAssertEqual(lastWeek.turns.count, 1)
        XCTAssertNotNil(lastWeek.turns[0].answer)
        XCTAssertEqual(lastMonth.turns.count, 30)
        XCTAssertNotNil(lastMonth.waiting)
        // All of it was read, so opening it leaves nothing for the app to file.
        XCTAssertTrue(lastMonth.turns.allSatisfy { $0.answer == nil || $0.filed != nil })
        XCTAssertEqual(lastMonth.turns.filter { $0.filed?.isEmpty == false }.count, 1)
        XCTAssertLessThan(lastMonth.turns.compactMap(\.answer).map(\.count).max()!, 100)   // short ones
        XCTAssertEqual(Set(sample.conversations.flatMap(\.turns).map(\.id)).count, 9 + 3 + 1 + 30)
    }

    // MARK: What was filed is what's in the pages

    func testWhatWasFiledIsInThePages() throws {
        for talk in sample.conversations {
            for turn in talk.turns {
                for entry in turn.filed?.actions ?? [] {
                    let page = try page(try XCTUnwrap(entry.page))
                    // A value corrected since isn't the page's any more: the correction's is.
                    let changed = talk.changedLater(entry, in: turn.id, elsewhere: sample.conversations)
                    switch entry {
                    case .created(_, let modified):
                        // Made when the message was filed. Unopened, it's still dated then; the
                        // deleted one was written on first.
                        XCTAssertEqual(modified, turn.filed?.date)
                        XCTAssertEqual(page.modified == modified, page.deleted == nil)
                        XCTAssertGreaterThanOrEqual(page.modified, modified)
                    case .typed(_, let type):
                        XCTAssertEqual(page.type, type)
                    case .value(_, let field, let value), .replaced(_, let field, _, let value):
                        XCTAssertEqual(page.values[field] == value, !changed)
                    case .renamed(_, let was, let title):
                        XCTAssertEqual(page.title, title)
                        XCTAssertNotEqual(was, title)
                    case .described(_, let text):
                        XCTAssertEqual(page.paragraphs.first?.text, text)
                        XCTAssertEqual(page.paragraphs.first?.placed, [])
                    case .placed(let placement):
                        XCTAssertFalse(placement.paragraphs.isEmpty)
                        XCTAssertEqual(placement.texts.count, placement.paragraphs.count)
                        XCTAssertEqual(placement.appended.count, placement.paragraphs.count)
                        XCTAssertEqual(placement.date, turn.filed?.date)
                        // The author's own words from that message, changed only in case and punctuation.
                        let message = words(try XCTUnwrap(turn.answer))
                        for text in placement.texts {
                            XCTAssertTrue(message.contains(words(text)), text)
                            XCTAssertTrue(text.first?.isUppercase == true && text.hasSuffix("."), text)
                        }
                        // On the page exactly as placing leaves them: taking them back takes all of them, and nothing else.
                        var without = page
                        XCTAssertTrue(without.takeBack(placement), placement.texts.joined(separator: " "))
                        XCTAssertFalse(without.paragraphs.contains { $0.placed.contains { $0.placement == placement.id } })
                        let gone = words(page.paragraphs.map(\.text).joined(separator: " ")).count
                            - words(without.paragraphs.map(\.text).joined(separator: " ")).count
                        XCTAssertEqual(gone, placement.texts.map { words($0).count }.reduce(0, +))
                    case .newType, .newField, .fieldAdded:
                        XCTFail("not an action")
                    }
                }
            }
        }
        let placements = records(in: sample.conversations).flatMap(\.record.entries).compactMap { entry -> Placement? in
            if case .placed(let placement) = entry { placement } else { nil }
        }
        // Every mark on a page is some record's, and no two records share one.
        XCTAssertEqual(Set(placements.map(\.id)).count, placements.count)
        let marks = Set((sample.pages + sample.deleted).flatMap(\.paragraphs).flatMap(\.placed).map(\.placement))
        XCTAssertEqual(marks, Set(placements.map(\.id)))
        // Both ways of placing, and one placement that did both.
        XCTAssertTrue(placements.contains { $0.appended == [true] })
        XCTAssertTrue(placements.contains { $0.appended == [false] })
        XCTAssertTrue(placements.contains { $0.appended == [true, false] })
    }

    func testACorrectedValueShowsAsChangedSince() throws {
        // The field's own timeline: the value first filed, then the correction, which the page holds.
        let history = today.history(of: ID.Field.members, on: ID.clockmakersGuild)
        XCTAssertEqual(history.map(\.value), [.text("nine"), .text("seven")])
        XCTAssertEqual(try page(ID.clockmakersGuild).values[ID.Field.members], .text("seven"))
        // Undo goes newest first: the first value's waits for the correction's.
        XCTAssertTrue(today.changedLater(history[0].action, in: history[0].turn))
        XCTAssertFalse(today.changedLater(history[1].action, in: history[1].turn))
    }

    /// The strongest check that the records and the pages agree: the app's own Undo takes back
    /// everything today's conversation filed, newest first, and leaves the world as it was
    /// this morning.
    func testEverythingFiledTodayCanBeTakenBack() throws {
        var pages = sample.pages, schema = sample.schema
        let others = Array(sample.conversations.dropFirst())
        let chain = try XCTUnwrap(today.rewind(to: today.turns[0].id, elsewhere: others))
        XCTAssertEqual(chain.count, today.turns.compactMap(\.filed).flatMap(\.actions).count)
        var records = Dictionary(uniqueKeysWithValues: today.turns.compactMap { turn in turn.filed.map { (turn.id, $0) } })
        for filed in chain {
            _ = records[filed.turn]?.undo(filed.action, pages: &pages, schema: &schema, deleted: sample.deleted)
        }
        XCTAssertTrue(records.values.allSatisfy(\.isEmpty))
        func after(_ id: UUID) throws -> Document { try XCTUnwrap(pages.first { $0.id == id }) }

        // The page filing made is gone, with the field made to hold it.
        XCTAssertEqual(pages.count, sample.pages.count - 1)
        XCTAssertFalse(pages.contains { $0.id == ID.masterCorwen })
        XCTAssertNil(try after(ID.oldTamsin).values[ID.Field.teacher])
        // The kind and the fields filing made are gone, and the guild is a name again.
        XCTAssertEqual(schema.types.map(\.name), ["Character", "Place", "Chapter"])
        XCTAssertEqual(schema.fields.map(\.name),
                       sample.schema.fields.map(\.name).filter { !["Led by", "Members", "Teacher"].contains($0) })
        XCTAssertEqual(schema.type(ID.Kind.character)?.fields.count, 5)
        let guild = try after(ID.clockmakersGuild)
        XCTAssertNil(guild.type)
        XCTAssertTrue(guild.values.isEmpty)
        XCTAssertTrue(written(guild).isEmpty)
        XCTAssertTrue(WorldMap(pages: pages, schema: schema).cards.first { $0.id == guild.id }?.isRumour == true)
        // The page has the name it had, and every page only what the author typed.
        XCTAssertEqual(try after(ID.oldTamsin).title, "Tamsin")
        XCTAssertEqual(written(try after(ID.oldTamsin)).count, 2)
        XCTAssertEqual(written(try after(ID.mara)).count, 4)
        XCTAssertTrue(try after(ID.mara).paragraphs[2].text.hasSuffix("trusted to wind it."))
        XCTAssertEqual(written(try after(ID.lighthouse)).count, 3)
        XCTAssertTrue(try after(ID.lighthouse).paragraphs[2].text.hasSuffix("the floor of the lamp room."))
        // Only yesterday's words, from another conversation, are still marked as placed.
        let marked = pages.filter { $0.paragraphs.contains { !$0.placed.isEmpty } }
        XCTAssertEqual(marked.map(\.id), [ID.mapOfTheCoast])
    }

    // MARK: Written as the app's stores write it

    func testTheAppsStoresGiveItBackAsWritten() throws {
        try SampleWorld.write(sample, to: root)
        let worlds = try WorldStore(root: root)
        let id = sample.world.id
        XCTAssertEqual(worlds.all(), [sample.world])
        XCTAssertEqual(worlds.pageCount(id), sample.pages.count + sample.deleted.count)
        XCTAssertEqual(worlds.world(containing: ID.mara), id)

        // As the app loads a world: every page, most recently edited first, the deleted ones apart.
        let saved = try DocumentStore(directory: worlds.documents(id)).scan()
        XCTAssertEqual(saved.unreadable, [])
        XCTAssertEqual(saved.pages.filter { $0.deleted == nil }, sample.pages)
        XCTAssertEqual(saved.pages.filter { $0.deleted != nil }, sample.deleted)
        XCTAssertEqual(try SchemaStore(url: worlds.schema(id)).load(), sample.schema)

        // And as it lists the world's conversations: newest first.
        let talks = try ConversationStore(directory: worlds.conversations(id))
        XCTAssertEqual(talks.scan().unreadable, [])
        let listed = talks.all().filter { $0.aboutWorld && !$0.turns.isEmpty }
            .sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
        XCTAssertEqual(listed, sample.conversations)
        XCTAssertEqual(try talks.load(ID.conversationToday), today)
        XCTAssertTrue(talks.hasTalk(ID.conversationLastWeek))
    }

    func testWritingAgainLeavesNothingASceneChanged() throws {
        try SampleWorld.write(sample, to: root)
        let worlds = try WorldStore(root: root)
        let pages = try DocumentStore(directory: worlds.documents(sample.world.id))
        try pages.save(Document(title: "Made in a scene"))
        try pages.delete(ID.mara)
        try ConversationStore(directory: worlds.conversations(sample.world.id)).save(Conversation(page: UUID(), turns: [
            .init(question: "", answer: "Said in a scene"),
        ], aboutWorld: true))

        let later = SampleWorld.contents(now: now.addingTimeInterval(3_600))
        try SampleWorld.write(later, to: root)
        XCTAssertEqual(pages.all(), (later.pages + later.deleted).sorted { $0.modified > $1.modified })
        XCTAssertEqual(try ConversationStore(directory: worlds.conversations(sample.world.id)).all().count, 4)
    }

    func testTheEmptyWorldWritesAndLoadsBesideIt() throws {
        let empty = SampleWorld.empty()
        XCTAssertEqual(empty.world.name, World.defaultName)
        XCTAssertTrue(empty.pages.isEmpty && empty.deleted.isEmpty && empty.conversations.isEmpty && empty.unseen.isEmpty)
        XCTAssertEqual(empty.schema, Schema())
        XCTAssertNil(empty.lastConversation)
        XCTAssertNil(empty.instructions)

        try SampleWorld.write(empty, to: root)
        let worlds = try WorldStore(root: root)
        XCTAssertEqual(worlds.all(), [empty.world])
        XCTAssertEqual(worlds.pageCount(empty.world.id), 0)
        // As a world the app has just made: nothing saved for its types or conversations yet.
        XCTAssertFalse(FileManager.default.fileExists(atPath: worlds.schema(empty.world.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: worlds.conversations(empty.world.id).path))
        XCTAssertEqual(try DocumentStore(directory: worlds.documents(empty.world.id)).all(), [])
        XCTAssertEqual(try SchemaStore(url: worlds.schema(empty.world.id)).load(), Schema())
        XCTAssertEqual(try ConversationStore(directory: worlds.conversations(empty.world.id)).all(), [])

        try SampleWorld.write(sample, to: root)
        XCTAssertEqual(worlds.all(), [sample.world, empty.world])   // by name: Breakwater, My World
    }
}
