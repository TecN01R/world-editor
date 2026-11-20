import Foundation

/// Recognises requests for the companion to *produce* creative content ("write
/// the next scene", "give me a name for…", "brainstorm some magic systems").
/// Those never reach a generative model as a task: the companion declines in
/// fixed wording and offers to help the author work it out instead.
/// Asking for help brainstorming ("help me brainstorm the ending") is fine:
/// the companion facilitates, drawing ideas out of the author.
public enum CreativeRequest {
    static let patterns: [String] = [
        "write ", "rewrite", "draft ", "continue the", "continue my", "finish the", "finish my",
        "next scene", "next chapter", "what happens next", "suggest", "brainstorm some", "brainstorm ideas",
        "brainstorm a ", "brainstorm names", "brainstorm for me", "come up with",
        "give me ideas", "give me an idea", "give me some", "ideas for", "idea for", "name for",
        "names for", "invent", "make up", "create a", "design a", "describe what", "plot twist",
        "how should the story", "how should it end", "what should happen", "what should she",
        "what should he", "what should they", "what should my", "fill in", "flesh out", "expand on",
        "help me write", "can you write", "could you write", "improve this", "make this better",
        "polish", "punch up", "tell me what", "decide for me", "pick one for me",
    ]

    /// Requests to be helped, not supplied.
    static let facilitation = ["help me brainstorm", "brainstorm with me", "help me think", "help me figure",
                               "help me work out", "ask me", "question me", "challenge me"]

    public static func isCreative(_ message: String) -> Bool {
        let m = " " + message.lowercased().replacingOccurrences(of: "\u{2019}", with: "'") + " "
        if facilitation.contains(where: { m.contains($0) }) && !m.contains("for me") { return false }
        return patterns.contains { m.contains($0) }
    }

    /// Fixed, model-free reply. Kept short and not preachy.
    public static let decline = "That part is yours to write, so I won't supply it. I can help you work it out, though."
}

/// Questions the companion can always fall back on. They contain only
/// open-ended words plus, optionally, a phrase quoted verbatim from the author.
public enum FallbackQuestion {
    public static func make(about phrase: String?, seed: Int = 0) -> String {
        guard let p = phrase?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else {
            let generic = [
                "What do you already know about this that you haven't written down yet?",
                "What would need to be true for this to feel right to you?",
                "Where does this sit with what you wrote earlier?",
                "What are you most unsure about here?",
            ]
            return generic[abs(seed) % generic.count]
        }
        let templates = [
            "What do you mean by \u{201C}\(p)\u{201D}?",
            "Why does \u{201C}\(p)\u{201D} matter to you here?",
            "What have you already decided about \u{201C}\(p)\u{201D}, and what is still open?",
            "Is \u{201C}\(p)\u{201D} consistent with what you wrote before?",
        ]
        return templates[abs(seed) % templates.count]
    }
}
