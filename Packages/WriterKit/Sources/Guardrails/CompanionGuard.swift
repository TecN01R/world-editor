import Foundation

/// Deterministic checks on everything the writing companion says, applied in
/// code after the model generates and before anything reaches the screen.
///
/// The companion may reflect, question, critique, summarise and help the
/// author brainstorm by drawing ideas out of them. It may not author content:
/// no names, places, events, details or prose the author didn't write.
/// The model is instructed to behave; this is what makes the rule hold when it
/// doesn't. A reply that fails is never shown: the companion retries, then
/// says nothing rather than something stock.
public struct CompanionGuard: Sendable {
    public enum Violation: Equatable, Sendable {
        case disguisedSuggestion(String)     // "what if…", "maybe she…", "have you considered…"
        case inventedName(String)            // a proper noun the author never wrote
        case inventedConcept(String)         // a content word that isn't the author's and isn't open-ended
        case assumedPronoun(String)          // "she"/"he" for someone the author never gendered
        case prose(String)                   // imagery and mood: "like a cage", "heavier than the water"
        case critique(String)                // a reviewer's questions: "themes", "symbolism"
        case refusal                         // "I'm sorry, but I can't write…": nobody asked it to
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
        // everyday words an interviewer needs that add no story content (tested on the Duo's model)
        "life", "lives", "like", "day", "days", "become", "becomes", "became", "came", "begin", "began", "begun",
        "job", "learn", "learned", "learning", "taught", "teach", "sort", "time", "times", "long", "ago",
        "years", "year", "grow", "grew", "alone", "help", "helps", "helped", "actually", "agree", "agreed",
        "draw", "drew", "draws", "drive", "drove", "drives", "seek", "seeks", "sought", "set", "express",
        "itself", "himself", "herself", "themselves", "otherwise", "past", "living", "move", "moves", "moved",
        "step", "steps", "join", "joined", "stayed", "kept", "bring", "brought", "find", "found", "lose",
        "lost", "try", "tried", "hoped", "care", "cares", "cared", "worry", "worries", "love", "loves", "loved",
        "hate", "hates", "trust", "trusts", "trusted", "afraid", "proud", "ashamed", "happy", "sad", "angry",
        "enough", "even", "such", "person", "people", "someone's", "talk",
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

        violations += suggestions(in: trimmed)
        violations += names(in: trimmed, authorText: authorText)

        // Content words must be the author's or open-ended.
        let authorWords = Self.words(authorText)
        for w in Self.words(Self.removingQuotes(trimmed)) where w.count > 2 {
            if !authorWords.contains(w) && !Self.openVocabulary.contains(w) && !Self.isInflection(w, of: authorWords) {
                violations.append(.inventedConcept(w))
            }
        }
        violations += pronouns(in: trimmed, authorText: authorText)
        return dedupe(violations)
    }

    /// Suggestion patterns at the start of a word, other than `allowed` ones.
    private func suggestions(in reply: String, allowed: Set<String> = []) -> [Violation] {
        let lower = " " + reply.lowercased() + " "
        return Self.suggestionPatterns
            .filter { !allowed.contains($0) && (lower.contains(" " + $0) || lower.contains("\n" + $0)) }
            .map { Violation.disguisedSuggestion($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Proper nouns: capitalised words not at a sentence start that the author never wrote.
    private func names(in reply: String, authorText: String) -> [Violation] {
        let authorCased = Set(authorText.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init))
        var out: [Violation] = []
        for s in Self.sentences(reply) {
            let tokens = s.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
            for (i, token) in tokens.enumerated() where i > 0 && token.first?.isUppercase == true && token != "I" && !token.hasPrefix("I'") {
                let t = token.hasSuffix("'s") ? String(token.dropLast(2)) : token   // "Ilsa's"
                if !authorCased.contains(t) && !Self.openVocabulary.contains(t.lowercased()) { out.append(.inventedName(t)) }
            }
        }
        return out
    }

    /// Gendered pronouns the author never used assume something about a
    /// character ("she" for Ilsa); a gendered word of the author's
    /// ("her brother Tomas") grounds them.
    private func pronouns(in reply: String, authorText: String) -> [Violation] {
        let authorWords = Self.words(authorText), words = Self.words(Self.removingQuotes(reply))
        return Self.genders.flatMap { pronouns, grounds in
            authorWords.isDisjoint(with: pronouns.union(grounds))
                ? pronouns.intersection(words).sorted().map(Violation.assumedPronoun) : []
        }
    }

    /// Each gender's pronouns, and the author's words that would ground them.
    static let genders: [(pronouns: Set<String>, grounds: Set<String>)] = [
        (["he", "him", "his", "himself"],
         ["man", "men", "boy", "brother", "father", "son", "husband", "uncle", "nephew", "king", "prince",
          "lord", "sir", "mr", "grandfather", "dad", "monk", "priest", "duke", "emperor", "god"]),
        (["she", "her", "hers", "herself"],
         ["woman", "women", "girl", "sister", "mother", "daughter", "wife", "aunt", "niece", "queen", "princess",
          "lady", "madam", "mrs", "ms", "miss", "grandmother", "mum", "mom", "nun", "priestess", "duchess",
          "empress", "goddess"]),
    ]

    /// For conversation (the companion as a friend to think out loud with; docs/ai-charter.md):
    /// ordinary language passes, but not prose, suggestions, a critic's
    /// questions, refusals, names the author never wrote or genders they
    /// never gave. Either-or questions pass (`offersChoices` flags them).
    public func checkReply(_ reply: String, authorText: String) -> [Violation] {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [.empty] }
        var violations: [Violation] = []
        // Three sentences, one question; "Ah, got it!" doesn't count as one.
        let sentences = Self.sentences(trimmed).filter { $0.split(separator: " ").count >= 4 }
        if trimmed.count > 450 || sentences.count > 3 || trimmed.filter({ $0 == "?" }).count > 1 {
            violations.append(.tooLong)
        }
        violations += suggestions(in: trimmed, allowed: Self.conversational)
        if trimmed.range(of: #"^(I['’]?m sorry|I am sorry|I can['’]?t|I cannot|As an AI)\b"#,
                         options: [.regularExpression, .caseInsensitive]) != nil {
            violations.append(.refusal)
        }
        // The author's own words ("the cage" they wrote) may be talked about.
        let author = authorText.lowercased()
        func marked(_ patterns: [String], _ violation: (String) -> Violation) {
            for p in patterns {
                if let r = trimmed.range(of: p, options: [.regularExpression, .caseInsensitive]),
                   !author.contains(trimmed[r].lowercased()) {
                    violations.append(violation(String(trimmed[r])))
                }
            }
        }
        marked(Self.proseMarkers, Violation.prose)
        marked(Self.critiqueMarkers, Violation.critique)
        violations += names(in: trimmed, authorText: authorText) + pronouns(in: trimmed, authorText: authorText)
        return dedupe(violations)
    }

    /// Suggestion patterns that are everyday talk in conversation: "doesn't
    /// add up", "let me try again". "Like a" is judged as prose instead.
    static let conversational: Set<String> = ["like a ", "add ", "try ", "introduce "]

    /// Imagery and mood: the companion writing the author's world (Kevin's line).
    static let proseMarkers = [
        // A simile, but not "sounds like a great start" or "like a character".
        #"\blike an? (?!(great|good|cool|nice|fun|really|very|solid|real|fresh|big|lot|bit|kind|sort|character|person|place|name|story|start|plan|question|thing)\b)\w+"#, #"\bas if\b"#, #"\bas though\b"#, #"\bheavier than\b"#,
        #"\balmost (physical|tangible|alive)\b"#, #"\bmirrors?\b"#, #"\bechoe?s?\b"#, #"\bcage\b"#,
        #"\bweight of\b"#, #"\bheld breath\b"#,
    ]

    /// A literary reviewer's questions: too loaded to help the author think
    /// (Kevin's line; it pokes at the story, not its meaning).
    static let critiqueMarkers = [
        #"\bthem(e|es|atic|atically)\b"#, #"\bsymbol\w*"#, #"\bmotifs?\b"#, #"\ballegor\w*"#,
        #"\bmetaphor\w*"#, #"\bstands? for\b"#, #"\bdeeper meaning\b"#, #"\bsignifican(ce|t) of\b"#,
        #"\bnarrative (arc|function|purpose)\b"#, #"\bjuxtapos\w*"#,
    ]

    /// "Is it X or Y?", or a menu of answers ("—open sea, river, enclosed
    /// bay—"). Allowed in conversation for now, but flagged for review
    /// (Kevin, 2026-11-22: open it up, flag it, tighten later if need be).
    public static func offersChoices(_ reply: String) -> Bool {
        reply.range(of: #"\b(is|are|was|were|does|did|do|has|have)\b[^?.!]*\bor\b[^?]*\?"#,
                    options: [.regularExpression, .caseInsensitive]) != nil
            || reply.range(of: #"[—:(]\s*[^,—:()?.!]+(,\s*[^,—:()?.!]+){2,}"#, options: .regularExpression) != nil
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
        // Longer or shorter forms of the author's words ("rowers", "row" for "rower").
        return vocab.contains { ($0.count > 3 && w.hasPrefix($0) && w.count - $0.count <= 3)
            || (w.count > 2 && $0.hasPrefix(w) && $0.count - w.count <= 3) }
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

    static func removingQuotes(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "[\"\u{201C}][^\"\u{201D}]*[\"\u{201D}]") else { return s }
        let ns = s as NSString
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
    }
}
