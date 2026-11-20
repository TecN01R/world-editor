import Foundation

/// Deterministic checks on everything the writing companion says, applied in
/// code after the model generates and before anything reaches the screen.
///
/// The companion may reflect, question, critique, summarise and help the
/// author brainstorm by drawing ideas out of them. It may not author content:
/// no names, places, events, details or prose the author didn't write.
/// The model is instructed to behave; this is what makes the rule hold when it
/// doesn't. A reply that fails is never shown: the companion retries, then
/// falls back to a fixed question built only from the author's own words.
public struct CompanionGuard: Sendable {
    public enum Violation: Equatable, Sendable {
        case disguisedSuggestion(String)     // "what if…", "maybe she…", "have you considered…"
        case inventedName(String)            // a proper noun the author never wrote
        case inventedConcept(String)         // a content word that isn't the author's and isn't open-ended
        case tooLong
        case empty
    }

    /// Phrases that turn a question into a proposal.
    public static let suggestionPatterns: [String] = [
        "what if", "how about", "have you considered", "have you thought about", "consider ",
        "maybe ", "perhaps ", "you could", "you might", "could she", "could he", "could they",
        "could it", "might she", "might he", "might they", "wouldn't it", "would it be interesting",
        "imagine ", "suppose ", "one idea", "an idea", "for example", "e.g.", "such as", "like a ",
        "what about ", "try ", "add ", "introduce ",
    ]

    /// Open-ended words a question may use without them being the author's.
    /// They ask about the author's intent; they don't propose content.
    public static let openVocabulary: Set<String> = Set<String>([  // Set(array): duplicates are harmless
        // question & discourse
        "what", "why", "how", "when", "where", "who", "whom", "whose", "which", "does", "did", "do",
        "is", "are", "was", "were", "will", "would", "should", "can", "could", "has", "have", "had",
        "you", "your", "yours", "yourself", "this", "that", "these", "those", "there", "here", "it", "its",
        "they", "them", "their", "she", "her", "he", "him", "his", "the", "a", "an", "of", "to", "in", "on",
        "for", "with", "about", "from", "by", "at", "as", "and", "or", "but", "if", "not", "no", "yes",
        "than", "then", "so", "be", "been", "being", "more", "most", "less", "least", "very", "really",
        "already", "still", "yet", "ever", "never", "always", "again", "now", "before", "after", "earlier",
        "later", "first", "last", "both", "each", "other", "else", "same", "different", "own", "just", "only",
        "one", "any", "some", "all", "every", "much", "many", "make", "makes", "made", "say", "says", "said",
        "mean", "means", "meant", "seem", "seems", "feel", "feels", "felt", "think", "thinks", "thought",
        "know", "knows", "knew", "known", "want", "wants", "wanted", "need", "needs", "needed",
        "believe", "believes", "expect", "expects", "hope", "hopes", "fear", "fears", "choose", "chooses",
        "chose", "decide", "decides", "decided", "change", "changes", "changed", "matter", "matters",
        "happen", "happens", "happened", "stay", "stays", "leave", "leaves", "keep", "keeps", "give", "gives",
        "get", "gets", "go", "goes", "come", "comes", "see", "sees", "tell", "tells", "show", "shows",
        "true", "real", "certain", "sure", "clear", "unclear", "wrong", "right", "important", "possible",
        // craft & reflection
        "reader", "readers", "story", "scene", "chapter", "page", "passage", "sentence", "line", "word",
        "words", "character", "characters", "place", "world", "moment", "ending", "beginning", "middle",
        "draft", "note", "notes", "writing", "wrote", "write", "written", "describe", "described",
        "detail", "details", "reason", "reasons", "motive", "purpose", "intent", "intention", "goal",
        "assumption", "assume", "assuming", "contradiction", "contradict", "contradicts", "conflict",
        "consistent", "inconsistent", "tension", "question", "questions", "answer", "evidence", "point",
        "sense", "idea", "meaning", "feeling", "feelings", "belief", "beliefs", "choice", "choices",
        "cost", "costs", "risk", "stake", "stakes", "relationship", "between", "connect", "connects",
        "relate", "relates", "earlier", "elsewhere", "previously", "established", "stated", "unsaid",
        "left", "leave", "open", "surprise", "surprised", "expected", "unexpected", "work", "works",
        "sit", "sits", "down", "unsure", "decided", "haven't", "hasn't", "don't", "doesn't", "didn't",
        "isn't", "aren't", "wasn't", "weren't", "won't", "can't", "couldn't", "wouldn't", "shouldn't",
        "you've", "you're", "it's", "that's", "what's", "why's", "how's", "there's", "she's", "he's",
        // reflection, critique & brainstorming-as-facilitation (about the author's text, not new content)
        "notice", "noticed", "appears", "appear", "repeat", "repeats", "repeated", "vague", "specific",
        "pacing", "slow", "slower", "fast", "faster", "tone", "voice", "perspective", "structure", "order",
        "sequence", "conflicts", "reveal", "reveals", "withheld", "implied", "implies", "explicit", "mention",
        "mentions", "mentioned", "however", "although", "while", "because", "since", "also", "instead",
        "rather", "whether", "unless", "until", "either", "neither", "part", "parts", "section", "sections",
        "paragraph", "paragraphs", "list", "listed", "group", "together", "theme", "themes", "thread",
        "threads", "ideas", "options", "option", "directions", "direction", "possibilities", "brainstorm",
        "brainstorming", "explore", "exploring", "pull", "pulls", "drawn", "strongest", "weakest", "clearer",
        "earlier", "next", "previous", "missing", "gap", "gaps", "unresolved", "resolved", "repetition",
        "summary", "summarise", "summarize", "far", "wrote", "written", "say", "versus", "compared",
        "two", "three", "four", "several", "few", "met", "meet", "meets", "fit", "fits", "hold", "holds",
        "side", "sides", "place", "takes", "take", "took", "lead", "leads", "follow", "follows", "end", "ends",
        "start", "starts", "turn", "turns", "case", "kind", "way", "ways", "thing", "things", "something",
        "anything", "nothing", "everything", "someone", "anyone", "nobody", "everyone", "into", "out", "up",
        "over", "under", "through", "without", "within", "against", "around", "my", "me", "we", "our", "us",
    ])

    public var maxCharacters = 1200

    public init() {}

    /// - Parameters:
    ///   - reply: what the model produced
    ///   - authorText: everything the author has written that's in scope
    ///     (relevant notes + the author's turns in this conversation)
    public func check(_ reply: String, authorText: String) -> [Violation] {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [.empty] }
        var violations: [Violation] = []
        if trimmed.count > maxCharacters { violations.append(.tooLong) }

        let lower = " " + trimmed.lowercased() + " "
        for p in Self.suggestionPatterns where lower.contains(" " + p) || lower.contains("\n" + p) {
            violations.append(.disguisedSuggestion(p.trimmingCharacters(in: .whitespaces)))
        }

        let authorWords = Self.words(authorText)
        let sentences = Self.sentences(trimmed)

        // Proper nouns: capitalised words not at a sentence start that the author never wrote.
        let authorCased = Set(authorText.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init))
        for s in sentences {
            let tokens = s.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
            for (i, t) in tokens.enumerated() where i > 0 && t.first?.isUppercase == true && t != "I" {
                if !authorCased.contains(t) && !Self.openVocabulary.contains(t.lowercased()) {
                    violations.append(.inventedName(t))
                }
            }
        }

        // Content words must be the author's or open-ended.
        for w in Self.words(Self.removingQuotes(trimmed)) where w.count > 2 {
            if !authorWords.contains(w) && !Self.openVocabulary.contains(w) && !Self.isInflection(w, of: authorWords) {
                violations.append(.inventedConcept(w))
            }
        }
        return dedupe(violations)
    }

    public func isAcceptable(_ reply: String, authorText: String) -> Bool {
        check(reply, authorText: authorText).isEmpty
    }

    // MARK: helpers

    private func dedupe(_ v: [Violation]) -> [Violation] {
        var seen = Set<String>(), out: [Violation] = []
        for x in v where seen.insert("\(x)").inserted { out.append(x) }
        return out
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func words(_ s: String) -> Set<String> {
        Set(normalize(s).split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .map { $0.hasSuffix("'s") ? String($0.dropLast(2)) : $0 }
            .filter { !$0.isEmpty })
    }

    /// Plural/tense variants of the author's words count as the author's.
    static func isInflection(_ w: String, of vocab: Set<String>) -> Bool {
        for suffix in ["s", "es", "ed", "d", "ing", "ly", "er", "est"] where w.hasSuffix(suffix) {
            let stem = String(w.dropLast(suffix.count))
            if vocab.contains(stem) || vocab.contains(stem + "e") { return true }
        }
        return vocab.contains { $0.count > 3 && w.hasPrefix($0) && w.count - $0.count <= 3 }
    }

    static func sentences(_ s: String) -> [String] {
        var out: [String] = [], cur = "", inQuote = false
        for ch in s {
            cur.append(ch)
            if ch == "\"" || ch == "\u{201C}" || ch == "\u{201D}" { inQuote.toggle() }
            if !inQuote, ch == "?" || ch == "." || ch == "!" || ch == "\n" {
                let t = cur.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { out.append(t) }
                cur = ""
            }
        }
        let t = cur.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { out.append(t) }
        return out
    }

    static func quotedSpans(_ s: String) -> [String] {
        let pattern = "[\"\u{201C}]([^\"\u{201D}]+)[\"\u{201D}]"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    static func removingQuotes(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "[\"\u{201C}][^\"\u{201D}]*[\"\u{201D}]") else { return s }
        let ns = s as NSString
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
    }
}
