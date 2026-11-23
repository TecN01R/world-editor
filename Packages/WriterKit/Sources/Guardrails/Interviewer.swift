import Foundation
import WriterCore

/// The companion's side of the conversation: what the model is told, and
/// what of its reply may reach the author. It talks like a friend the author
/// bounces ideas off, not a novelist or an expert: it listens, reacts and
/// asks, but never supplies content of its own (docs/ai-charter.md).
/// Model-agnostic apart from `Prompt.chatML`, Qwen's format.
public enum Interviewer {
    public static let instructions = """
    You're a friend the writer bounces ideas off while they build the world in their head. \
    They know it far better than you do. You're here to listen, react and be curious, so they \
    can think out loud and get it out of their head.

    Talk like a friend in a chat: short, plain and warm, one to three sentences. Respond to \
    what they just said: react honestly, say what you're curious about, mention it when two \
    things don't seem to fit, and answer if they ask you something. Ask a question when you're \
    genuinely curious, one at a time; you don't have to ask one every time. Remember what \
    they've told you and build on it. If they correct you, take it.

    Don't act like the expert: don't grade their ideas ("solid start", "a bit vague"), don't \
    lecture, and don't tell them what their story needs.

    It's their world, and you never add to it: no imagery or mood, no themes or symbolism, no \
    suggestions ("what if", "maybe"), no guessing why someone does \
    something, and no names or details they haven't given. If you don't know someone's \
    gender, use their name.

    You'll see their other pages in this world, what they've told you before and the page \
    they're on (if it's blank, help them start). Stick to that page; bring in other pages only \
    where they clearly connect.
    """

    /// A conversation as the model sees it: who said what, in order.
    public struct Prompt: Equatable, Sendable {
        public enum Speaker: Sendable { case author, companion }
        public var system: String
        /// Opens with the author's side (the world and the page), and
        /// alternates; the model replies to the last, the author's.
        public var turns: [(speaker: Speaker, text: String)]

        public static func == (a: Prompt, b: Prompt) -> Bool {
            a.system == b.system && a.turns.elementsEqual(b.turns) { $0.speaker == $1.speaker && $0.text == $1.text }
        }

        /// Qwen's chat format, answering without its thinking step.
        public var chatML: String {
            "<|im_start|>system\n\(system)<|im_end|>\n" + turns.map {
                "<|im_start|>\($0.speaker == .author ? "user" : "assistant")\n\($0.text)<|im_end|>\n"
            }.joined() + "<|im_start|>assistant\n<think>\n\n</think>\n\n"
        }

        /// The turns as one message, for models that take a single prompt.
        public var flattened: String {
            guard turns.count > 1 else { return turns.first?.text ?? "" }
            return turns[0].text + "\n\nConversation so far:\n" + turns.dropFirst().map {
                ($0.speaker == .author ? "Them: " : "You: ") + $0.text
            }.joined(separator: "\n") + "\n\nReply to their last message."
        }
    }

    /// The world, the page (its newest writing when it's long) and every turn
    /// of the conversation so far, the last `maxTurns` of it.
    public static func prompt(title: String, type: String? = nil, fields: String, writing: String,
                              world: String = "", memory: String = "", conversation: Conversation,
                              maxCharacters: Int = 6000, maxTurns: Int = 12) -> Prompt {
        var parts: [String] = []
        if !world.isEmpty { parts.append("Other pages in this world:\n" + world) }
        if !memory.isEmpty { parts.append("What I've told you on other pages:\n" + memory) }
        // "A page titled": on its own, a bare name reads as a place ("we're in Ilsa").
        let page = (type.map { "a \($0) page" } ?? "a page") + (title.isEmpty ? " with no title yet" : " titled \u{201C}\(title)\u{201D}")
        parts.append("I'm on \(page).")
        if !fields.isEmpty { parts.append(fields) }
        let budget = max(0, maxCharacters - parts.joined().count)
        parts.append("What I've written there:\n" + (writing.isEmpty ? "(nothing yet)" : String(writing.suffix(budget))))
        var turns: [(speaker: Prompt.Speaker, text: String)] = [(.author, parts.joined(separator: "\n\n"))]
        for turn in conversation.turns.suffix(maxTurns) {
            turns.append((.companion, turn.question))
            if let answer = turn.answer { turns.append((.author, answer)) }
        }
        return Prompt(system: instructions, turns: turns)
    }

    /// The rest of the world as background for the page in `focus` (its
    /// title, writing and answers): pages that share words with it come
    /// first, with their opening; the others by name only, so unrelated
    /// pages don't pull the conversation away. Until `maxCharacters`.
    public static func worldSummary(_ pages: [(name: String, type: String?, writing: String)], focus: String,
                                    maxCharacters: Int = 2000) -> String {
        let topic = keywords(focus)
        let scored = pages.map { page in (page: page, shared: keywords(page.name + " " + page.writing).intersection(topic).count) }
        let ordered = scored.filter { $0.shared > 0 }.sorted { $0.shared > $1.shared } + scored.filter { $0.shared == 0 }
        var lines: [String] = [], used = 0
        for (page, shared) in ordered {
            let opening = page.writing.split(whereSeparator: \.isNewline).joined(separator: " ")
            guard !page.name.isEmpty || (shared > 0 && !opening.isEmpty) else { continue }
            let line = "- " + (page.name.isEmpty ? "Untitled" : page.name) + (page.type.map { " (\($0))" } ?? "")
                + (shared > 0 && !opening.isEmpty ? ": " + opening.prefix(160) : "")
            guard used + line.count <= maxCharacters else { break }
            lines.append(line)
            used += line.count + 1
        }
        return lines.joined(separator: "\n")
    }

    /// What the author has told the companion on other pages that bears on
    /// `focus` (shares a word with it), newest first, until `maxCharacters`:
    /// the companion's memory of the world, in the author's words.
    public static func memory(_ conversations: [(page: String, conversation: Conversation)], focus: String,
                              maxCharacters: Int = 1500) -> String {
        let topic = keywords(focus)
        let answered = conversations.flatMap { c in
            c.conversation.turns.compactMap { t in t.answer.map { (page: c.page, question: t.question, answer: $0, asked: t.asked) } }
        }.filter { !keywords($0.page + " " + $0.answer).isDisjoint(with: topic) }.sorted { $0.asked > $1.asked }
        var lines: [String] = [], used = 0
        for (page, question, answer, _) in answered {
            let line = "- On \(page.isEmpty ? "an untitled page" : page), you asked \"\(question)\" I said: \(answer)"
            guard used + line.count <= maxCharacters else { break }
            lines.append(line)
            used += line.count + 1
        }
        return lines.joined(separator: "\n")
    }

    /// The words that say what a text is about: not everyday ones.
    static func keywords(_ text: String) -> Set<String> {
        CompanionGuard.words(text).filter { $0.count > 3 && !CompanionGuard.openVocabulary.contains($0) }
    }

    /// The reply as the author may see it, or nil: tidied (no label, quotes
    /// or list mark), cut after its first question if it asks more than one,
    /// not a repeat of an earlier question, and passing
    /// `CompanionGuard.checkReply` against `authorText` (the page and the
    /// author's answers).
    public static func screen(_ reply: String, authorText: String, asked: [String] = [],
                              guardrail: CompanionGuard = CompanionGuard()) -> String? {
        var r = PageQuestions.tidy(reply)
        if let label = r.range(of: #"^(question|q|you|editor)\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) { r.removeSubrange(label) }
        let quotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]
        if r.count > 1, let first = r.first, let last = r.last, quotes.contains(first), quotes.contains(last) {
            r = String(r.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)   // the whole reply in quotes
        }
        // Small models ask two or three at once: keep the reply up to its first question.
        if let q = r.firstIndex(of: "?"), r[r.index(after: q)...].contains("?") { r = String(r[...q]) }
        guard !asked.contains(where: { similar($0, r) }) else { return nil }
        return guardrail.checkReply(r, authorText: authorText).isEmpty ? r : nil
    }

    /// Mostly the same words: a repeat, however reworded.
    static func similar(_ a: String, _ b: String) -> Bool {
        let wa = CompanionGuard.words(a), wb = CompanionGuard.words(b)
        return Double(wa.intersection(wb).count) / Double(max(1, wa.union(wb).count)) > 0.6
    }
}
