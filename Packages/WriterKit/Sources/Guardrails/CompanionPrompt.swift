import Foundation
import WriterCore

/// What the companion's model is told before it replies: who it is, a few
/// example exchanges, what the app shows it of the author's world, and the
/// conversation so far. The companion is a friend the author talks to about
/// what they're writing, which may be an invented world, a story, notes or
/// real life: the prompt doesn't assume. What belongs in it comes from the
/// author (docs/ai-charter.md).
///
/// Its replies aren't checked or filtered afterwards (Kevin's ruling,
/// 2026-11-23): how it behaves comes from this text alone, so a change here
/// text is shaped as it is). Model-agnostic: each model puts the prompt into
/// its own chat format.
///
/// Since 2026-11-25 the app sends `plain`: the model stock (Kevin: "only run models stock from
/// now on"), given only the conversation, which page is open and the writer's own instructions
public struct CompanionPrompt: Equatable, Sendable {
    public enum Speaker: Sendable { case author, companion }

    public struct Turn: Equatable, Sendable {
        public var speaker: Speaker
        public var text: String

        public init(speaker: Speaker, text: String) {
            self.speaker = speaker
            self.text = text
        }
    }

    /// A page as the companion is shown it: the open one, or another in the world.
    public struct Page: Sendable {
        public var name: String
        public var type: String?
        /// "Name: value" lines.
        public var fields: String
        public var writing: String

        public init(name: String, type: String? = nil, fields: String = "", writing: String) {
            self.name = name
            self.type = type
            self.fields = fields
            self.writing = writing
        }
    }

    /// Who it is, the examples and the background, as one system turn. What
    /// stays the same from reply to reply comes first, so a model that keeps
    /// what it has already read re-reads only what changed.
    public var system: String
    /// The conversation: the author opening the page (or saying their first
    /// words, where the companion waits for them), then who said what, in
    /// order. It ends with the author's turn, which the model replies to.
    public var turns: [Turn]

    /// Who the companion is and how it replies. Short on purpose: a small
    /// model follows a few plain instructions, loses track of many, and
    /// carries each one to its extreme.
    public static let instructions = """
        You're the friend a writer talks to about what they're writing in a writing app. It may be \
        a world they're inventing, a story, notes, or something from real life: take the page for \
        what it is. Whatever it is, it's theirs; you know only what is on their pages and what \
        they've told you, so what belongs in it comes from them. What you bring is interest, \
        honesty, and what you know about the real world.

        Each time, reply to their last message:
        - If they asked about the real world (history, science, how something works), answer from \
        what you know, and say so if you aren't sure. If they doubt what you told them, don't \
        defend it: you may well be wrong, and say that.
        - If they asked what you think, or asked you to write or suggest something, do it, \
        briefly.
        - If they corrected you, take it: say what you now understand.
        - Otherwise respond the way an interested friend would, with a real reaction to what they \
        just said.

        You can ask one question when you need it to understand what they've already told you: \
        what they meant, or how two things they've said fit together. Don't ask them to come up \
        with more (what kind of person someone is, what they want, what happens next). They'll \
        tell you when they know.

        Keep it short and plain: no greeting, no praise, no lists of options. You're talking with \
        the writer ("you"); the names on their pages are the people and places they're writing \
        about.
        """

    /// A manner is shown better than described: these steer a small model
    /// more than any rule does. From another domain, so nothing in them can be
    /// mistaken for the author's own pages, and with different kinds of reply,
    /// so no one shape is copied every time.
    public static let examples = """
        Examples of the kind of reply, from a different writer's pages. Nothing in it belongs to \
        this one, and its wording isn't yours to reuse.

        The writer opens a page “Dolores” that says only “Runs the Regent.” Another of their pages \
        says the Regent is the last cinema in town.
        You: Dolores runs the Regent, the last cinema in town. Does “runs” mean it's hers?

        Writer: yeah it's hers. her husband built it
        You: Hers, and built by her husband. So she's looking after something he made.

        Writer: no, the Regent isn't the town, it's the cinema
        You: Ah, I had that backwards. The Regent is the cinema, and the town is just where it \
        stands.

        Writer: how long does a reel of film actually last?
        You: Roughly ten to twenty minutes for a standard 35mm reel, so a feature is several reels \
        and someone switches projectors partway. I'm not sure of the exact length, so check it if \
        it matters.

        Writer: lol she'd hate that
        You: Ha. I believe it.

        Writer: I'm Jo by the way
        You: Good to meet you, Jo.

        Writer: I'm stuck, I don't know where this goes
        You: That's allowed. So far you've told me about Dolores, the cinema her husband built, \
        and a town that has stopped coming. Which of those feels most alive to you?

        Writer: is it too much that she still vacuums the balcony nobody uses?
        You: Not to me. It's the detail I'd remember: she keeps cleaning a place no one sees.

        Writer: give me a few names for her dog
        You: A few to try: Reel, Usher, Marquee. Yours to keep or drop.

        Writer: ok that helps, thanks
        You: Glad it did. I'm here when you want to pick it up again.
        """

    /// The author's first turn: the companion speaks first when a page opens,
    /// and a chat model's conversation has to begin with the other side.
    public static let opened = "(I've just opened this page.)"

    /// The prompt for the companion's next reply about `page`: with the rest of
    /// the world (`others`) and what the author said in `earlier` conversations
    /// on other pages as background, cut to what bears on this page, then the
    /// last `maxTurns` exchanges of `conversation`. The background stays within
    /// `maxCharacters`, the turns within `maxTurnCharacters`.
    /// - Parameter lookup: what the companion can look up, which shows the other pages as
    ///   the few most like this one and the rest by name (nil: every page's opening, as before).
    public init(page: Page, others: [Page] = [], earlier: [(page: String, conversation: Conversation)] = [],
                conversation: Conversation, maxCharacters: Int = 6000, maxTurns: Int = 12,
                maxTurnCharacters: Int = 6000, lookup: Lookup? = nil, texts: Texts = Texts()) {
        let focus = [page.name, page.fields, page.writing, conversation.authorText].joined(separator: "\n")
        let memory = Self.memory(earlier, focus: focus, maxCharacters: maxCharacters / 4)
        var background = [Self.backgroundHeading(partial: lookup != nil)]
        let world: String
        var related = ""
        if let lookup {
            // The few most like the page with their openings, which keeps "how it sits with
            // their other pages"; the rest by name, for search_pages to find what's on them.
            let ordered = Self.ordered(others.filter { !$0.name.isEmpty || !$0.writing.isEmpty }, focus: focus)
            let like = Self.worldSummary(Array(ordered.prefix(3)), focus: "", maxCharacters: maxCharacters / 6)
            let names = PageLookup.directory(Array(ordered.dropFirst(3)), focus: "", maxCharacters: maxCharacters / 6)
            related = lookup.related(to: conversation, maxCharacters: maxCharacters / 5)
            if !like.isEmpty { background.append("Their other pages most like this one:\n" + like) }
            if !names.isEmpty { background.append("Their other pages, by name:\n" + names) }
            if !memory.isEmpty { background.append("From your earlier conversations:\n" + memory) }
            if !related.isEmpty { background.append(Self.relatedHeading + "\n" + related) }
            world = like + names
        } else {
            world = Self.worldSummary(others, focus: focus, maxCharacters: maxCharacters / 3)
            if !world.isEmpty { background.append("Their other pages:\n" + world) }
            if !memory.isEmpty { background.append("From your earlier conversations:\n" + memory) }
        }
        let used = world.count + related.count + memory.count + page.fields.count
        background.append("The page they have open now:\n" + Self.describe(page, maxCharacters: max(0, maxCharacters - used)))

        var system = Self.head(lookup: lookup, texts: texts) + [background.joined(separator: "\n\n")]
        // What to do first is said only when it applies: a small model follows
        // an instruction better than a condition.
        if conversation.turns.isEmpty { system.append(Self.opening(page, alone: world.isEmpty)) }
        self.system = system.joined(separator: "\n\n")
        turns = Self.authorFirst(Self.recent(conversation, maxTurns: maxTurns, maxTurnCharacters: maxTurnCharacters),
                                 opener: Self.opened)
    }

    /// The prompt for a conversation about the whole world, from the pages list (Kevin,
    /// 2026-11-24: "converse with it and not operate solely within a single page"): every
    /// page as background, the ones bearing on what's being said first, and no page open.
    /// - Parameter lookup: what the companion can look up, which adds its case to the
    ///   instructions. A world that fits whole is shown as without one; one that doesn't is,
    ///   in the same room, the pages bearing most on what's being said, the rest by name and
    ///   what the pages say about their last message, under a heading saying only part is
    ///   shown (nil: as before).
    public init(world: String, pages: [Page], earlier: [(page: String, conversation: Conversation)] = [],
                conversation: Conversation, maxCharacters: Int = 6000, maxTurns: Int = 12,
                maxTurnCharacters: Int = 6000, lookup: Lookup? = nil, texts: Texts = Texts()) {
        let focus = conversation.authorText
        // Much more of each page than beside an open one: here the pages are all it has
        let room = maxCharacters * 2 / 3, perPage = 800
        var summary = Self.summarized(pages, focus: focus, maxCharacters: room, perPage: perPage)
        // In a small world, page names and a few passages showed less than every page whole
        let partial = lookup != nil && !summary.whole
        var names = "", related = ""
        if let lookup, partial {
            related = lookup.related(to: conversation, maxCharacters: maxCharacters / 4)
            let left = room - related.count
            // Room is kept for every page's name, up to a quarter; the summary has the rest.
            let reserved = PageLookup.directory(pages, focus: "", maxCharacters: maxCharacters / 4).count
            summary = Self.summarized(pages, focus: focus, maxCharacters: left - reserved, perPage: perPage)
            names = PageLookup.directory(summary.rest, focus: "", maxCharacters: left - summary.text.count)
        }
        let memory = Self.memory(earlier, focus: focus, maxCharacters: maxCharacters / 4)
        var background = [Self.backgroundHeading(partial: partial)]
        background.append(summary.text.isEmpty ? "Their world, \u{201C}\(world)\u{201D}, has no pages yet."
                          : "Their world, \u{201C}\(world)\u{201D}, and its pages:\n" + summary.text)
        if !names.isEmpty { background.append("Their other pages, by name:\n" + names) }
        if !related.isEmpty { background.append(Self.relatedHeading + "\n" + related) }
        if !memory.isEmpty { background.append("From your earlier conversations:\n" + memory) }
        // It doesn't speak first here: it waits for the author (Kevin, 2026-11-24).
        system = (Self.head(lookup: lookup, texts: texts) + [background.joined(separator: "\n\n")])
            .joined(separator: "\n\n")
        turns = Self.authorFirst(Self.recent(conversation, maxTurns: maxTurns, maxTurnCharacters: maxTurnCharacters),
                                 opener: Self.openedWorld)
    }

    /// What the companion can look up in the author's pages (docs/companion-roadmap.md, its
    /// own tools for the writer's pages): the prompt then shows only part of their pages and
    /// adds what they say about the author's last message (`retrieving`), in a world
    /// conversation only when its pages don't fit whole; it offers `search_pages`
    /// (`searching`), and its instructions say what to do about what isn't shown
    /// (`instructions(lookup:)`).
    public struct Lookup: Sendable {
        public var pages: PageLookup
        /// Spotlight's item ids for the author's last message, best first (none on Linux).
        public var ranked: [String]
        /// The open page, shown whole already, so left out of what's found.
        public var open: UUID?
        /// What their pages say about the author's last message goes in the prompt.
        public var retrieving: Bool
        /// The model is offered `search_pages` and told to look with it.
        public var searching: Bool
        /// The model is offered `look_up` and told to look up the real world when unsure.
        public var lookingUp: Bool

        public init(pages: PageLookup, ranked: [String] = [], open: UUID? = nil, retrieving: Bool, searching: Bool,
                    lookingUp: Bool = false) {
            self.pages = pages
            self.ranked = ranked
            self.open = open
            self.retrieving = retrieving
            self.searching = searching
            self.lookingUp = lookingUp
        }

        /// What the pages say about the author's last message in `conversation`, if retrieving.
        func related(to conversation: Conversation, maxCharacters: Int) -> String {
            guard retrieving, let message = conversation.turns.last?.answer else { return "" }
            return pages.related(to: message, maxCharacters: maxCharacters, ranked: ranked, excluding: open)
        }
    }

    private static let relatedHeading = "What their pages say about what they just said:"

    private static func backgroundHeading(partial: Bool) -> String {
        "What the app shows you of the writer's pages (for reference; the writer didn't just say this"
            + (partial ? "; only part of their pages is shown here):" : "):")
    }

    /// The reply case added when the model can search the author's pages.
    public static let searchInstruction = """
        - If they ask about something of theirs that isn't shown to you here, look for it with \
        \(PageLookup.toolName) first, then answer from what it finds. If it finds nothing, say it isn't on \
        their pages: that part is theirs to tell you.
        """

    /// The reply case added when the model can look up the author's pages but not search them
    /// (retrieval alone): the search case's last sentence, worded for what it's been shown,
    /// invented on 13% of the questions about something on no page (the hybrid, which had the
    /// sentence, on 2%); "R+" measured it. R+'s wording also fired on answers it had to put
    /// together from two passages, and on a real-world question asked about their world; "R2"
    public static let notShownInstruction = """
        - If they ask about something of theirs that isn't anywhere in what you're shown of their \
        pages here, even with what several of them say put together, say plainly that you don't see \
        it: that part is theirs to tell you. A question about the real world is answered as above, \
        even when it comes up in their world.
        """

    /// The reply case added when the model can look up the real world (`WebLookup`), after the
    /// real-world one it narrows: what it isn't sure of, it looks up rather than guesses.
    public static let lookUpInstruction = """
        - If you aren't sure of something about the real world, look it up with \(WebLookup.toolName) first, then \
        answer from what it finds and say it's from Wikipedia. Look up only the real world: never their names or \
        anything they've made up.
        """

    /// `instructions`, with a case for the author's pages after the real-world one when the
    /// companion has a lookup: `searchInstruction` when it can search them, otherwise
    /// `notShownInstruction`, after `lookUpInstruction` when it can look up the real world.
    /// Without a lookup, as they are.
    public static func instructions(lookup: Lookup?) -> String {
        guard let lookup else { return instructions }
        return adding((lookup.lookingUp ? [lookUpInstruction] : []) + [lookup.searching ? searchInstruction : notShownInstruction])
    }

    /// The app's instructions for a companion that can, or can't, search the author's pages
    /// and look up the real world (`instructions(lookup:)` with search, or without a lookup):
    /// what the companion's settings showed and restored until 2026-11-25.
    public static func instructions(searching: Bool, lookingUp: Bool = false) -> String {
        adding((lookingUp ? [lookUpInstruction] : []) + (searching ? [searchInstruction] : []))
    }

    /// `instructions` with `replies` among its reply cases, after the real-world one.
    private static func adding(_ replies: [String]) -> String {
        guard !replies.isEmpty else { return instructions }
        let next = "- If they asked what you think"
        return instructions.replacingOccurrences(of: next, with: replies.joined(separator: "\n") + "\n" + next)
    }

    /// The author's own instructions and examples, from the companion's settings until it
    /// became the plain model (Kevin, 2026-11-25: "a settings panel for me to modify instructions
    /// myself"), in place of the app's: nil keeps the app's; empty examples leave them out.
    public struct Texts: Equatable, Sendable {
        public var instructions: String?
        public var examples: String?

        public init(instructions: String? = nil, examples: String? = nil) {
            self.instructions = instructions
            self.examples = examples
        }
    }

    /// What the system turn begins with: the instructions and the examples, the author's where
    /// they set their own, any left empty left out.
    private static func head(lookup: Lookup?, texts: Texts) -> [String] {
        [texts.instructions ?? instructions(lookup: lookup), texts.examples ?? examples]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The author's first turn in a world conversation the companion began (before it
    /// waited for the author).
    public static let openedWorld = "(I've just opened the companion for my whole world.)"

    /// `recent`, after `opener` when the companion spoke first: a chat model's
    /// conversation begins with the author.
    private static func authorFirst(_ recent: [Turn], opener: String) -> [Turn] {
        recent.first?.speaker == .author ? recent : [Turn(speaker: .author, text: opener)] + recent
    }

    /// The model on its own (Kevin's trial, 2026-11-24: "remove all your rules and context and
    /// prompts so I can see how this actually works as a model"): none of the full prompt's
    /// instructions, examples or pages, only the conversation, and since 2026-11-25 one line on
    /// which page is open (`page`, its title), or, about the whole world, which world (`world`),
    /// then the writer's standing `instructions`, if they have any (`Instructions`; none at first).
    /// The whole conversation, unless `maxTurns` or `maxTurnCharacters` (in all) say less: only
    /// when it outgrows the model's context (Kevin, 2026-11-25: "you WILL lift the limits").
    /// The opening line stays only before its first reply, which has to answer something.
    public static func plain(_ conversation: Conversation, page: String? = nil, world: String? = nil, instructions: String? = nil,
                             maxTurns: Int = .max, maxTurnCharacters: Int = .max) -> CompanionPrompt {
        let turns = recent(conversation, maxTurns: maxTurns, maxTurnCharacters: maxTurnCharacters)
        let open: String?
        if let page {
            open = page.isEmpty ? "The writer has an untitled page open."
                                : "The writer has their page \u{201C}\(oneLine(page, maxCharacters: 80))\u{201D} open."
        } else if let world {
            open = "The writer is talking about their world \u{201C}\(oneLine(world, maxCharacters: 80))\u{201D} as a whole."
        } else {
            open = nil
        }
        let system = [open, Instructions.shown(instructions)].compactMap { $0 }.joined(separator: "\n\n")
        return CompanionPrompt(system: system, turns: turns.isEmpty ? [Turn(speaker: .author, text: opened)] : turns)
    }

    private init(system: String, turns: [Turn]) {
        self.system = system
        self.turns = turns
    }

    /// The newest exchanges that fit; the last one always, cut down if it alone is too long.
    private static func recent(_ conversation: Conversation, maxTurns: Int, maxTurnCharacters: Int) -> [Turn] {
        var recent: [Conversation.Turn] = [], length = 0
        // The author's turn as the model reads it: their words and what they attached.
        func said(_ turn: Conversation.Turn) -> String? { turn.answer.map { Documents.turn($0, turn.attached ?? []) } }
        for turn in conversation.turns.suffix(maxTurns).reversed() {
            length += turn.question.count + (said(turn)?.count ?? 0)
            guard recent.isEmpty || length <= maxTurnCharacters else { break }
            recent.insert(turn, at: 0)
        }
        // Words that read as the model's control tokens stay words (`Reasoned.gemmaPlain`).
        func fitted(_ text: String) -> String { Reasoned.gemmaPlain(excerpt(text, maxCharacters: maxTurnCharacters) ?? text) }
        return recent.flatMap { turn in
            (turn.question.isEmpty ? [] : [Turn(speaker: .companion, text: fitted(turn.question))])   // the author began
                + (said(turn).map { [Turn(speaker: .author, text: fitted($0))] } ?? [])
        }
    }

    /// The conversation as one message, for models that take a single prompt.
    public var flattened: String {
        guard turns.count > 1 else { return turns.first?.text ?? "" }
        return "The conversation so far:\n" + turns.map {
            ($0.speaker == .author ? "Writer: " : "You: ") + $0.text
        }.joined(separator: "\n") + "\n\nReply to the writer's last message."
    }

    /// What the companion does first, when a page has just been opened. A thin
    /// page gets its take and, where the words could mean two things, a question;
    /// a page with a lot on it gets one thing picked out, since "what you make of
    /// it" there comes back as a summary. `alone`: the world has no other pages.
    static func opening(_ page: Page, alone: Bool) -> String {
        if page.writing.isEmpty && page.fields.isEmpty {
            return "Right now: the writer has just opened a blank page and hasn't said anything yet. "
                + "Make it easy to begin: ask what is in their head, however small or unfinished."
        }
        let opened = "Right now: the writer has just opened this page and hasn't said anything yet. "
        if page.writing.count > 400 {
            return opened + "There is a lot on it, so don't sum it up. Pick the one thing on it you'd most want to talk about, "
                + "most likely in the part they wrote last, and say plainly what it is and what you notice about it. "
                + "If it could be read two ways, ask which they mean."
        }
        return opened + "Tell them what you make of it" + (alone ? "." : " and how it sits with their other pages.")
            + " If something on it could be read two ways, ask which they mean."
    }

    /// The open page: what it is, its fields and its writing. A page longer
    /// than `maxCharacters` is shown as its opening and its latest part, which
    /// is where the author is working.
    static func describe(_ page: Page, maxCharacters: Int) -> String {
        // The title is the name of who or what the page is about, said outright:
        // given only "a Character page titled …", the model said the page gave no
        // name, and asked whether the character was a place (Kevin, 2026-11-23).
        let name = page.name
        var lines: [String]
        if let type = page.type {
            let a = article(type)
            if name.isEmpty {
                lines = ["\(a.capitalized) \(type) page with no title yet."]
            } else {
                lines = ["\u{201C}\(name)\u{201D}, \(a) \(lowercasedWord(type)): \(name) is who or what this page is about, "
                         + "and the title is \(name)'s name."]
            }
        } else {
            lines = [name.isEmpty ? "A page with no title yet."
                     : "\u{201C}\(name)\u{201D}: the title is the name of who or what this page is about."]
        }
        if !page.fields.isEmpty { lines += ["Its fields:", page.fields] }
        if page.writing.isEmpty {
            lines.append("Nothing is written on it yet.")
        } else if let excerpt = Self.excerpt(page.writing, maxCharacters: maxCharacters) {
            lines += ["What they've written on it so far (it's long: this is how it opens and, after [\u{2026}], its latest part):", excerpt]
        } else {
            lines += ["What they've written on it so far:", page.writing]
        }
        return lines.joined(separator: "\n")
    }

    /// "Character" as a common noun, "character"; "NPC" stays as written.
    static func lowercasedWord(_ word: String) -> String {
        guard let first = word.first, word.dropFirst().first?.isLowercase ?? true else { return word }
        return first.lowercased() + word.dropFirst()
    }

    /// "an" before a word that starts with a vowel, otherwise "a".
    static func article(_ word: String) -> String {
        (word.first.map { "aeiouAEIOU".contains($0) } ?? false) ? "an" : "a"
    }

    /// A text longer than `maxCharacters` as how it opens (a quarter of the
    /// room, 1000 characters at most) and its latest part, each cut at a word,
    /// with `[…]` between; nil if it fits whole.
    static func excerpt(_ text: String, maxCharacters: Int) -> String? {
        guard text.count > maxCharacters else { return nil }
        let opening = min(1000, maxCharacters / 4)
        var head = text.prefix(opening), tail = text.suffix(maxCharacters - opening)
        if let space = head.lastIndex(where: \.isWhitespace) { head = head[..<space] }
        if let space = tail.firstIndex(where: \.isWhitespace) { tail = tail[space...] }
        return [head, "[\u{2026}]", tail].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
    }

    /// The rest of the world, a line a page: its name, type, filled fields and opening.
    /// Pages that share words with `focus` (the open page and what the author
    /// has said about it) come first, most shared first, so those are what a
    /// big world is cut down to. Until `maxCharacters`.
    /// - Parameter perPage: how much of each page's opening it shows (the world's own
    ///   conversation, with no open page, shows more: it's all the companion has).
    static func worldSummary(_ pages: [Page], focus: String, maxCharacters: Int = 2000, perPage: Int = 160) -> String {
        summarized(pages, focus: focus, maxCharacters: maxCharacters, perPage: perPage).text
    }

    /// `worldSummary`, with whether it shows every page whole (all of its opening and fields)
    /// and the pages it has no room for, in its order.
    static func summarized(_ pages: [Page], focus: String, maxCharacters: Int, perPage: Int)
        -> (text: String, whole: Bool, rest: [Page]) {
        let kept = ordered(pages, focus: focus).filter { page in
            !page.name.isEmpty || page.writing.contains { !$0.isWhitespace }
        }
        var lines: [String] = [], used = 0, whole = true
        for (i, page) in kept.enumerated() {
            let opening = oneLine(page.writing)
            let allFields = oneLine(page.fields.replacingOccurrences(of: "\n", with: "; "))
            let fields = oneLine(allFields, maxCharacters: 200)
            let head = listed(page.name, type: page.type) + (page.fields.isEmpty ? "" : " [\(fields)]")
            // As much of its opening as fits, then less, then none: every page is named while there's room.
            let withOpening: [String] = opening.isEmpty ? [] : [perPage, 160].map { head + ": " + opening.prefix($0) }
            guard let line = (withOpening + [head]).first(where: { used + $0.count <= maxCharacters }) else {
                return (lines.joined(separator: "\n"), false, Array(kept[i...]))
            }
            whole = whole && fields == allFields && line == head + (opening.isEmpty ? "" : ": " + opening)
            lines.append(line)
            used += line.count + 1
        }
        return (lines.joined(separator: "\n"), whole, [])
    }

    /// A page as a line of a list: "- Name (Type)", "Untitled" when it has no name.
    static func listed(_ name: String, type: String?) -> String {
        "- " + (name.isEmpty ? "Untitled" : name) + (type.map { " (\($0))" } ?? "")
    }

    /// `pages`, those sharing the most words with `focus` first, then as they were.
    static func ordered(_ pages: [Page], focus: String) -> [Page] {
        let topic = keywords(focus)
        guard !topic.isEmpty else { return pages }
        return pages.enumerated()
            .map { (offset: $0.offset, page: $0.element, shared: keywords($0.element.name + " " + $0.element.writing).intersection(topic).count) }
            .sorted { ($1.shared, $0.offset) < ($0.shared, $1.offset) }
            .map(\.page)
    }

    /// What the author has told the companion on other pages that bears on
    /// `focus` (shares a word with it), newest first, until `maxCharacters`:
    /// the companion's memory of the world, in the author's words. What the
    /// companion had said is there only to place them, so it's cut short.
    static func memory(_ conversations: [(page: String, conversation: Conversation)], focus: String,
                       maxCharacters: Int = 1500) -> String {
        let topic = keywords(focus)
        let said = conversations.flatMap { c in
            c.conversation.turns.compactMap { t in
                t.answer.map { (page: c.page, world: c.conversation.aboutWorld, reply: t.question, answer: $0, asked: t.asked) }
            }
        }.filter { !keywords($0.page + " " + $0.answer).isDisjoint(with: topic) }.sorted { $0.asked > $1.asked }
        var lines: [String] = [], used = 0
        for (page, world, reply, answer, _) in said {
            let place = if world { "In a conversation about their whole world" }
                else if page.isEmpty { "On an untitled page of theirs" }
                else { "On their page \u{201C}\(page)\u{201D}" }
            // A turn the writer began (a world conversation's first) has nothing of the companion's before it.
            let line = reply.isEmpty
                ? "- \(place), the writer said: \u{201C}\(oneLine(answer))\u{201D}"
                : "- \(place), you said \u{201C}\(oneLine(reply, maxCharacters: 160))\u{201D} "
                    + "and the writer replied: \u{201C}\(oneLine(answer))\u{201D}"
            guard used + line.count <= maxCharacters else { break }
            lines.append(line)
            used += line.count + 1
        }
        return lines.joined(separator: "\n")
    }

    /// `text` on one line, cut to `maxCharacters` with an ellipsis.
    static func oneLine(_ text: String, maxCharacters: Int = .max) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > maxCharacters ? line.prefix(maxCharacters) + "\u{2026}" : line
    }

    /// The words that say what a text is about: not short or everyday ones.
    static func keywords(_ text: String) -> Set<String> {
        let words = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            .split { !$0.isLetter && $0 != "'" }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .map { $0.hasSuffix("'s") ? String($0.dropLast(2)) : $0 }
        return Set(words.filter { $0.count > 3 && !everyday.contains($0) })
    }

    /// Words too common to say what a page is about.
    private static let everyday: Set<String> = [
        "about", "actually", "afraid", "after", "again", "against", "agree", "agreed", "alone", "already", "also",
        "although", "always", "angry", "answer", "anyone", "anything", "appear", "appears", "aren't", "around",
        "ashamed", "assume", "assuming", "assumption", "became", "because", "become", "becomes", "been", "before",
        "began", "begin", "beginning", "begun", "being", "belief", "beliefs", "believe", "believes", "between",
        "both", "brainstorm", "brainstorming", "bring", "brought", "came", "can't", "care", "cared", "cares", "case",
        "certain", "change", "changed", "changes", "chapter", "character", "characters", "choice", "choices",
        "choose", "chooses", "chose", "clear", "clearer", "come", "comes", "compared", "conflict", "conflicts",
        "connect", "connects", "consistent", "contradict", "contradiction", "contradicts", "cost", "costs", "could",
        "couldn't", "days", "decide", "decided", "decides", "describe", "described", "detail", "details", "didn't",
        "different", "direction", "directions", "does", "doesn't", "don't", "down", "draft", "draw", "drawn", "draws",
        "drew", "drive", "drives", "drove", "each", "earlier", "either", "else", "elsewhere", "ending", "ends",
        "enough", "established", "even", "ever", "every", "everyone", "everything", "evidence", "expect", "expected",
        "expects", "explicit", "explore", "exploring", "express", "fast", "faster", "fear", "fears", "feel",
        "feeling", "feelings", "feels", "felt", "find", "first", "fits", "follow", "follows", "found", "four", "from",
        "gaps", "gets", "give", "gives", "goal", "goes", "grew", "group", "grow", "happen", "happened", "happens",
        "happy", "hasn't", "hate", "hates", "have", "haven't", "he's", "help", "helped", "helps", "here", "herself",
        "himself", "hold", "holds", "hope", "hoped", "hopes", "how's", "however", "idea", "ideas", "implied",
        "implies", "important", "inconsistent", "instead", "intent", "intention", "into", "isn't", "it's", "itself",
        "join", "joined", "just", "keep", "keeps", "kept", "kind", "knew", "know", "known", "knows", "last", "later",
        "lead", "leads", "learn", "learned", "learning", "least", "leave", "leaves", "left", "less", "life", "like",
        "line", "list", "listed", "lives", "living", "long", "lose", "lost", "love", "loved", "loves", "made", "make",
        "makes", "many", "matter", "matters", "mean", "meaning", "means", "meant", "meet", "meets", "mention",
        "mentioned", "mentions", "middle", "missing", "moment", "more", "most", "motive", "move", "moved", "moves",
        "much", "need", "needed", "needs", "neither", "never", "next", "nobody", "note", "notes", "nothing", "notice",
        "noticed", "only", "open", "option", "options", "order", "other", "otherwise", "over", "pacing", "page",
        "paragraph", "paragraphs", "part", "parts", "passage", "past", "people", "person", "perspective", "place",
        "point", "possibilities", "possible", "previous", "previously", "proud", "pull", "pulls", "purpose",
        "question", "questions", "rather", "reader", "readers", "real", "really", "reason", "reasons", "relate",
        "relates", "relationship", "repeat", "repeated", "repeats", "repetition", "resolved", "reveal", "reveals",
        "right", "risk", "said", "same", "says", "scene", "section", "sections", "seek", "seeks", "seem", "seems",
        "sees", "sense", "sentence", "sequence", "several", "she's", "should", "shouldn't", "show", "shows", "side",
        "sides", "since", "sits", "slow", "slower", "some", "someone", "someone's", "something", "sort", "sought",
        "specific", "stake", "stakes", "start", "starts", "stated", "stay", "stayed", "stays", "step", "steps",
        "still", "story", "strongest", "structure", "such", "summarise", "summarize", "summary", "sure", "surprise",
        "surprised", "take", "takes", "talk", "taught", "teach", "tell", "tells", "tension", "than", "that", "that's",
        "their", "them", "theme", "themes", "themselves", "then", "there", "there's", "these", "they", "thing",
        "things", "think", "thinks", "this", "those", "thought", "thread", "threads", "three", "through", "time",
        "times", "together", "tone", "took", "tried", "true", "trust", "trusted", "trusts", "turn", "turns",
        "unclear", "under", "unexpected", "unless", "unresolved", "unsaid", "unsure", "until", "vague", "versus",
        "very", "voice", "want", "wanted", "wants", "wasn't", "ways", "weakest", "were", "weren't", "what", "what's",
        "when", "where", "whether", "which", "while", "whom", "whose", "why's", "will", "with", "withheld", "within",
        "without", "won't", "word", "words", "work", "works", "world", "worries", "worry", "would", "wouldn't",
        "write", "writing", "written", "wrong", "wrote", "year", "years", "you're", "you've", "your", "yours",
        "yourself",
    ]
}
