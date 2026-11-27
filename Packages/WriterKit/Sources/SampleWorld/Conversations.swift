import Foundation
import WriterCore

/// The world's four conversations. The author thinks out loud, in any order and without
/// tidying; the companion listens and asks what happened next, and never offers anything of
/// its own for the world. Each is about the whole world, so it goes by an id of its own.
extension SampleWorld {
    /// Today's, the one the app opens again: nine turns, the last of them the companion's
    /// reply (the third try at it) waiting for the author. What the author said was filed
    /// after each reply, and between them the records do everything filing can do
    /// (`FilingRecord.Entry`): one found nothing to file, and the author's last message hasn't
    /// been read yet. Replies also searched the pages, looked something up, and added an
    /// instruction, and one message came with a document.
    ///
    /// Each message is worded so that its record is what filing gives for it: "she" just
    /// after her page was filed on, and the guild named in full where its value is corrected.
    /// Two things are from older filing, kept for their lines and their Undo: the rename (a
    /// page is renamed only from its own conversation) and the guild's description.
    static func today(_ times: Times) -> Conversation {
        let id = ID.conversationToday
        func asked(_ turn: Int) -> Date { momentToday(times, minutes: todayAsked[turn]) }
        func answered(_ turn: Int) -> Date { momentToday(times, minutes: todayAnswered[turn]) }
        func filed(_ turn: Int, _ entries: [FilingRecord.Entry]) -> FilingRecord {
            record(entries, filed: filedToday(times, turn: turn))
        }
        func placed(_ placement: Int, on page: Document, from turn: Int) -> FilingRecord.Entry {
            Self.placed(ID.placement(placement), on: page, at: filedToday(times, turn: turn))
        }
        let guild = clockmakersGuild(times), tamsin = oldTamsin(times), corwen = masterCorwen(times)

        var turns = [
            turn(0, of: id, "", at: asked(0),
                 "ok so the bell again. the lighthouse bell rang by itself the night the Petrel went down. nobody "
                 + "pulled the rope. Mara was up in the lamp room and heard it through the storm", at: answered(0)),
            turn(1, of: id,
                 "So nobody touched the rope, and Mara heard it from the lamp room, right through the storm. Did "
                 + "anyone else in Breakwater hear it that night?", at: asked(1),
                 "not sure yet. maybe the whole quay did. oh, and everyone calls her Old Tamsin, I have to stop "
                 + "writing just Tamsin. Old Tamsin built the clockwork that turns the lamp and she has never once "
                 + "been out to see it run", at: answered(1)),
            turn(2, of: id,
                 "Old Tamsin, then. She built the clockwork that turns the lamp and has never seen it turn. Who "
                 + "taught her to build a thing like that?", at: asked(2),
                 "she learned the trade from Master Corwen. that's all I have on him so far", at: answered(2)),
            turn(3, of: id,
                 "Master Corwen: a name, and nothing more yet. Is he still alive? And was he one of the Clockmakers' "
                 + "Guild?", at: asked(3),
                 "don't know yet, either of those. the guild though. the Clockmakers' Guild is the oldest guild on the "
                 + "coast, older than the harbour wall. Old Tamsin leads it. there are nine of them. also from now on "
                 + "just ask me one thing at a time ok", at: answered(3)),
            turn(4, of: id,
                 "One thing at a time, I'll remember. Nine clockmakers, with Old Tamsin leading them. Do they look "
                 + "after her clockwork out at the lighthouse?", at: asked(4),
                 "good question, hang on. real question first: how did real lighthouses turn the lamp before "
                 + "electricity? I want her clockwork to be right", at: answered(4)),
            turn(5, of: id,
                 "They ran on clockwork too. A heavy weight hung on a chain inside the tower, and as it sank it turned "
                 + "the lens through a train of gears; the keeper wound it back up by hand every few hours. So her "
                 + "clockwork fits. Who winds it in your lighthouse?", at: asked(5),
                 "Mara winds the clockwork every four hours, all night. nobody else is allowed to touch it",
                 at: answered(5)),
            turn(6, of: id,
                 "Every four hours, all night, and only her. So does anyone from the guild ever come out to look it "
                 + "over?", at: asked(6),
                 "never. here's the roll of the guild, I wrote it out last night. wait, not nine. there are only seven "
                 + "in the Clockmakers' Guild now. two died the winter the Petrel was lost", at: answered(6)),
            turn(7, of: id,
                 "I read the roll: seven names, Old Tamsin's at the top, and two struck off this winter. Were those "
                 + "two aboard the Petrel?", at: asked(7),
                 "yes!! both of them. they'd gone out to mend the bell buoy off the point and never came back. that's "
                 + "why Old Tamsin won't go near the water", at: answered(7)),
            turn(8, of: id,
                 "That explains why she has never been out to the lighthouse. Two of her guild lost with the Petrel, "
                 + "mending a bell buoy. Who mends the buoy now?", at: asked(8)),
        ]

        // The author's words about the bell went into the two pages they're about.
        turns[0].filed = filed(0, [placed(1, on: mara(times), from: 0), placed(2, on: lighthouse(times), from: 0)])
        // The page was "Tamsin" until the author said what everyone calls her.
        turns[1].filed = filed(1, [.renamed(page: tamsin.id, was: "Tamsin", title: tamsin.title),
                                   placed(3, on: tamsin, from: 1)])
        // "She" is Old Tamsin, the page just talked about. A name not used before got a page
        // of its own, and a new field to hold it.
        turns[2].filed = filed(2, [
            .created(page: corwen.id, modified: corwen.modified),
            .newField(ID.Field.teacher),
            .fieldAdded(type: ID.Kind.character, field: ID.Field.teacher),
            .value(page: tamsin.id, field: ID.Field.teacher, value: .page(corwen.id)),
            placed(4, on: tamsin, from: 2),
        ])
        turns[3].searches = [turns[3].question: ["Master Corwen", "Clockmakers' Guild"]]
        // The guild's page had only its name: it got a kind (a new one), a description, two
        // new fields with their values, and the author's sentences.
        turns[3].filed = filed(3, [
            .newType(ID.Kind.group),
            .typed(page: guild.id, type: ID.Kind.group),
            .described(page: guild.id, text: guild.paragraphs[0].text),
            .newField(ID.Field.ledBy),
            .fieldAdded(type: ID.Kind.group, field: ID.Field.ledBy),
            .value(page: guild.id, field: ID.Field.ledBy, value: .page(tamsin.id)),
            .newField(ID.Field.members),
            .fieldAdded(type: ID.Kind.group, field: ID.Field.members),
            .value(page: guild.id, field: ID.Field.members, value: .text("nine")),
            placed(5, on: guild, from: 3),
        ])
        turns[4].instructions = [turns[4].question: [instruction]]
        // Read, and nothing found to file.
        turns[4].filed = filed(4, [])
        turns[5].lookups = [turns[5].question: [lookedUp("how lighthouse lamps were turned before electricity",
                                                         onWikipedia: ["Lighthouse", "Lighthouse keeper"])]]
        turns[5].filed = filed(5, [placed(6, on: mara(times), from: 5)])
        turns[6].attached = [Conversation.Attached(name: "Guild Roll.pdf", text: guildRoll)]
        // A correction, naming the page it corrects: the field takes the new word, and keeps
        // the old one for Undo.
        turns[6].filed = filed(6, [
            .replaced(page: guild.id, field: ID.Field.members, was: .text("nine"), value: .text("seven")),
            placed(7, on: guild, from: 6),
        ])
        // (Turn 7's answer states something, and is still to be filed.)
        // Try Again, twice: the reply showing is the latest of three.
        turns[8].versions = [
            "So that's why she has never been out to see her clockwork run. Two of her own guild went out to mend "
            + "the bell buoy and never came back. Does Mara know that's the reason?",
            "Both of them, out mending the bell buoy. And Old Tamsin has kept off the water ever since, which is why "
            + "she has never seen the lamp turn. Does Mara know?",
            turns[8].question,
        ]
        return Conversation(page: id, turns: turns, aboutWorld: true)
    }

    /// A moment of today's conversation, `minutes` after it began. It began 2 hours and 24
    /// minutes ago and ran for 48 minutes. iOS words anything from 1½ to 2½ hours back as "2
    /// hours ago", so every time shown from it reads that for six minutes after `now`,
    /// however long a screenshot takes.
    private static func momentToday(_ times: Times, minutes: Double) -> Date {
        times.ago(hours: 2, minutes: 24 - minutes)
    }

    /// When each reply of today's conversation came, and when the author answered it, in
    /// minutes from the conversation's start (they began it, so the first two are the same).
    private static let todayAsked: [Double] = [0, 0.7, 3.5, 5.7, 9.8, 14.4, 16.6, 24.8, 47.5]
    private static let todayAnswered: [Double] = [0, 2.8, 5.0, 9.3, 13.5, 16.0, 24.0, 44.5]

    /// When what the author said in `turn` of today's conversation was filed: a quarter of a
    /// minute after the reply to it.
    static func filedToday(_ times: Times, turn: Int) -> Date {
        momentToday(times, minutes: todayAsked[turn + 1] + 0.25)
    }

    /// What the reply in today's conversation added to the author's instructions, as asked.
    static let instruction = "Ask one thing at a time."

    /// The document attached in today's conversation: read by the companion, never filed.
    private static let guildRoll = """
        The Clockmakers' Guild of Breakwater. Roll of members, written out fair.
        Old Tamsin, master.
        Hollis Ferrow, warden of the town clock.
        Edda Marsh.
        Piet Lowry.
        Annet Vose.
        Will Garrow, journeyman.
        Sian Garrow, journeyman.
        Struck from the roll this winter: Dunstan Ferrow and Corin Aske, lost with the Petrel.
        """

    /// Yesterday's: short, and ending on the author's words, with no reply after them. Its
    /// first reply looked something up, and one sentence of the answer to it was filed onto
    /// the map.
    static func yesterday(_ times: Times) -> Conversation {
        let id = ID.conversationYesterday
        func at(_ minutes: Double) -> Date { times.ago(hours: 26, minutes: -minutes) }
        var turns = [
            turn(0, of: id, "", at: at(0),
                 "do seals come back to the same beach every year? or is that just something people say?", at: at(0)),
            turn(1, of: id,
                 "They do, mostly. Grey seals and harbour seals both tend to come back to the same beaches to rest "
                 + "and to breed, year after year. Is this for the south cove?", at: at(0.8),
                 "yes. the seals in the south cove are why the boats won't land there. nobody says it out loud though",
                 at: at(2.5)),
            turn(2, of: id,
                 "So the whole harbour knows, and nobody says it. Who was the last one to try landing there?", at: at(3.1),
                 "Mara's mother I think. need to sleep on it", at: at(5.2)),
        ]
        turns[1].lookups = [turns[1].question: [lookedUp("do seals return to the same beach every year",
                                                         onWikipedia: ["Grey seal", "Harbor seal"])]]
        turns[1].filed = record([placed(ID.placement(8), on: mapOfTheCoast(times), at: at(3.35))], filed: at(3.35))
        return Conversation(page: id, turns: turns, aboutWorld: true)
    }

    /// Last week's: one turn, the author's first words, which no reply ever followed.
    static func lastWeek(_ times: Times) -> Conversation {
        let id = ID.conversationLastWeek, began = times.ago(days: 8)
        return Conversation(page: id, turns: [
            turn(0, of: id, "", at: began,
                 "note to self before I forget: the bell has to ring one more time at the very end. don't know who "
                 + "for yet", at: began),
        ], aboutWorld: true)
    }

    /// Last month's: thirty short turns, for scrolling, the last a reply waiting. Everything
    /// the author said in it was read, and nothing found to file but once: a page was made,
    /// Captain Hale's, which the author has since deleted.
    static func lastMonth(_ times: Times) -> Conversation {
        let id = ID.conversationLastMonth, began = times.ago(days: 33)
        let said: [(reply: String, answer: String?)] = [
            ("", "quick ones tonight. just firing things at you"),
            ("Fire away.", "the town clock has never been wrong"),
            ("Never? Who checks it?", "the guild. every morning at six"),
            ("What do they check it against?", "huh. good question. the tide tables I guess"),
            ("So the tide is the real clock.", "oh I like that. don't let me forget that"),
            ("I won't. What else?", "nobody whistles on the quay"),
            ("Why not?", "it calls the wind. everybody knows that"),
            ("Does anybody break the rule?", "Jory. constantly"),
            ("And does the wind come?", "ha. sometimes"),
            ("What happens to him when it does?", "he gets blamed for every lost net that week"),
            ("That seems fair. What else?", "the herring come in on the same day every year"),
            ("Which day?", "haven't picked. early autumn"),
            ("Does the town do anything that day?",
             "they ring the lighthouse bell at dawn. one of the only times it's rung on purpose"),
            ("Who rings it?", "Mara. she hates it, the whole harbour stares up at her"),
            ("What are the other times it's rung on purpose?", "fog. and funerals"),
            ("Whose funerals?", "anyone lost at sea. one stroke for each year of their age"),
            ("That's a lot of strokes for an old sailor.", "that's the point. the whole town has to stand there and count"),
            ("Who counts for the ones nobody knew well?",
             "the harbourmaster. Captain Hale, the harbourmaster who signed the Petrel out that night"),
            ("So he signed her out, and then he has to count for her crew.", "yes. oh that's grim. I love it"),
            ("How many were aboard?", "six. no, five and the boy"),
            ("The boy?", "not Jory. another one. I don't know him yet"),
            ("Does Jory know him?", "they were friends. that's why Jory rows the oil out now, it was the other boy's job"),
            ("So Jory took over his friend's work.", "and nobody asked him if he wanted to"),
            ("Did he?", "I don't think he's decided"),
            ("What does Mara make of him?", "she lets him stay for tea. that's a lot, for her"),
            ("Does he know about the sealskin?", "no!! nobody does"),
            ("Not even Tamsin?", "especially not her. Tamsin would take it apart to see how it works"),
            ("Would she put it back together?", "better than before, probably. that's the scary part"),
            ("Anything else before you stop?", "no that's me done. good one tonight"),
            ("It was. The tide being the real clock is the one I'd hold on to.", nil),
        ]
        // A reply every 36 seconds, and the answer to it 20 seconds after (at once where the
        // author began).
        func asked(_ turn: Int) -> Date { began.addingTimeInterval(Double(turn) * 36) }
        var turns = said.enumerated().map { index, exchange in
            turn(index, of: id, exchange.reply, at: asked(index), exchange.answer,
                 at: exchange.answer == nil ? nil : asked(index).addingTimeInterval(index == 0 ? 0 : 20))
        }
        // Each answer was read ten seconds after the reply to it; the one naming Captain Hale
        // made his page.
        let namesHale = 17
        for index in turns.indices.dropLast() {
            let filed = asked(index + 1).addingTimeInterval(10)
            let made: [FilingRecord.Entry] = index == namesHale ? [.created(page: ID.captainHale, modified: filed)] : []
            turns[index].filed = record(made, filed: filed)
        }
        return Conversation(page: id, turns: turns, aboutWorld: true)
    }

    /// A turn of `conversation`: the companion's `reply` (none where the author began) and
    /// the author's `answer` to it (none while the reply waits).
    private static func turn(_ index: Int, of conversation: UUID, _ reply: String, at asked: Date,
                             _ answer: String? = nil, at answered: Date? = nil) -> Conversation.Turn {
        var turn = Conversation.Turn(id: ID.turn(index, of: conversation), question: reply, answer: answer, asked: asked)
        turn.answered = answered
        return turn
    }

    /// A record as the app leaves one filed from a conversation about the whole world: with
    /// no page open, it saw no page's fields or title.
    private static func record(_ entries: [FilingRecord.Entry], filed date: Date) -> FilingRecord {
        var record = FilingRecord(entries: entries, seen: [:])
        record.date = date
        return record
    }

    /// What placement `id` put on `page`, read back off the page's own marks, so the record and
    /// the page can't disagree: each paragraph it put words in, the words, and whether they
    /// went on at the end of the author's own.
    private static func placed(_ id: UUID, on page: Document, at date: Date) -> FilingRecord.Entry {
        var placement = Placement(id: id, page: page.id, paragraphs: [], texts: [], date: date)
        for paragraph in page.paragraphs {
            for run in paragraph.placed where run.placement == id {
                let words = Array(paragraph.text.utf16)[run.location..<(run.location + run.length)]
                placement.paragraphs.append(paragraph.id)
                placement.texts.append(String(decoding: words, as: UTF16.self))
                placement.appended.append(run.location > 0)
            }
        }
        return .placed(placement)
    }

    /// What a reply looked up: `query`, and the Wikipedia articles it read, each by its title.
    private static func lookedUp(_ query: String, onWikipedia titles: [String]) -> LookedUp {
        LookedUp(query: query, sources: titles.map { title in
            let article = title.replacingOccurrences(of: " ", with: "_")
            return LookedUp.Source(title: title, url: URL(string: "https://en.wikipedia.org/wiki/\(article)")!)
        })
    }
}
