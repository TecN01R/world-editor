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
public struct CompanionPrompt: Equatable, Sendable {
    public enum Speaker: Sendable { case author, companion }

    public struct Turn: Equatable, Sendable {
        public var speaker: Speaker
        public var text: String
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
    /// The conversation: the author opening the page, then who said what, in
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
    public init(page: Page, others: [Page] = [], earlier: [(page: String, conversation: Conversation)] = [],
                conversation: Conversation, maxCharacters: Int = 6000, maxTurns: Int = 12,
                maxTurnCharacters: Int = 6000) {
        let focus = [page.name, page.fields, page.writing, conversation.authorText].joined(separator: "\n")
        let world = Self.worldSummary(others, focus: focus, maxCharacters: maxCharacters / 3)
        let memory = Self.memory(earlier, focus: focus, maxCharacters: maxCharacters / 4)
        var background = ["What the app shows you of the writer's pages (for reference; the writer didn't just say this):"]
        if !world.isEmpty { background.append("Their other pages:\n" + world) }
        if !memory.isEmpty { background.append("From your earlier conversations:\n" + memory) }
        let used = world.count + memory.count + page.fields.count
        background.append("The page they have open now:\n" + Self.describe(page, maxCharacters: max(0, maxCharacters - used)))

        var system = [Self.instructions, Self.examples, background.joined(separator: "\n\n")]
        // What to do first is said only when it applies: a small model follows
        // an instruction better than a condition.
        if conversation.turns.isEmpty { system.append(Self.opening(page, alone: world.isEmpty)) }
        self.system = system.joined(separator: "\n\n")

        // The newest exchanges that fit; the last one always, cut down if it alone is too long.
        var recent: [Conversation.Turn] = [], length = 0
        for turn in conversation.turns.suffix(maxTurns).reversed() {
            length += turn.question.count + (turn.answer?.count ?? 0)
            guard recent.isEmpty || length <= maxTurnCharacters else { break }
            recent.insert(turn, at: 0)
        }
        func fitted(_ text: String) -> String { Self.excerpt(text, maxCharacters: maxTurnCharacters) ?? text }
        turns = [Turn(speaker: .author, text: Self.opened)]
        for turn in recent {
            turns.append(Turn(speaker: .companion, text: fitted(turn.question)))
            if let answer = turn.answer { turns.append(Turn(speaker: .author, text: fitted(answer))) }
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
        var kind = "A page"
        if let type = page.type {
            let vowel = type.first.map { "aeiouAEIOU".contains($0) } ?? false
            kind = (vowel ? "An " : "A ") + type + " page"
        }
        var lines = [page.name.isEmpty ? "\(kind) with no title yet." : "\(kind) titled \u{201C}\(page.name)\u{201D}."]
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

    /// The rest of the world, a line a page: its name, type and opening.
    /// Pages that share words with `focus` (the open page and what the author
    /// has said about it) come first, most shared first, so those are what a
    /// big world is cut down to. Until `maxCharacters`.
    static func worldSummary(_ pages: [Page], focus: String, maxCharacters: Int = 2000) -> String {
        let topic = keywords(focus)
        let scored = pages.enumerated().map { (offset: $0.offset, page: $0.element,
                                               shared: keywords($0.element.name + " " + $0.element.writing).intersection(topic).count) }
        let ordered = scored.sorted { ($1.shared, $0.offset) < ($0.shared, $1.offset) }   // most shared first, then as they were
        var lines: [String] = [], used = 0
        for (_, page, _) in ordered {
            let opening = oneLine(page.writing)
            guard !page.name.isEmpty || !opening.isEmpty else { continue }
            let line = "- " + (page.name.isEmpty ? "Untitled" : page.name) + (page.type.map { " (\($0))" } ?? "")
                + (opening.isEmpty ? "" : ": " + opening.prefix(160))
            guard used + line.count <= maxCharacters else { break }
            lines.append(line)
            used += line.count + 1
        }
        return lines.joined(separator: "\n")
    }

    /// What the author has told the companion on other pages that bears on
    /// `focus` (shares a word with it), newest first, until `maxCharacters`:
    /// the companion's memory of the world, in the author's words. What the
    /// companion had said is there only to place them, so it's cut short.
    static func memory(_ conversations: [(page: String, conversation: Conversation)], focus: String,
                       maxCharacters: Int = 1500) -> String {
        let topic = keywords(focus)
        let said = conversations.flatMap { c in
            c.conversation.turns.compactMap { t in t.answer.map { (page: c.page, reply: t.question, answer: $0, asked: t.asked) } }
        }.filter { !keywords($0.page + " " + $0.answer).isDisjoint(with: topic) }.sorted { $0.asked > $1.asked }
        var lines: [String] = [], used = 0
        for (page, reply, answer, _) in said {
            let place = page.isEmpty ? "an untitled page of theirs" : "their page \u{201C}\(page)\u{201D}"
            let line = "- On \(place), you said \u{201C}\(oneLine(reply, maxCharacters: 160))\u{201D} "
                + "and the writer replied: \u{201C}\(oneLine(answer))\u{201D}"
            guard used + line.count <= maxCharacters else { break }
            lines.append(line)
            used += line.count + 1
        }
        return lines.joined(separator: "\n")
    }

    /// `text` on one line, cut to `maxCharacters` with an ellipsis.
    private static func oneLine(_ text: String, maxCharacters: Int = .max) -> String {
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
