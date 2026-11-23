import Foundation

/// The companion's questions about a page. The model proposes candidates;
/// only those `CompanionGuard` passes are shown, without repeats, topped up
/// with `FallbackQuestion`s so the author always gets a full set.
public struct PageQuestions: Sendable {
    public static let count = 3

    /// Everything the author wrote that's in scope: the page's title, text
    /// and field values.
    public let authorText: String
    public var guardrail = CompanionGuard()

    public init(authorText: String) {
        self.authorText = authorText
    }

    /// Candidates that are questions and pass the guard, tidied (no list
    /// numbering or bullets) and without repeats, at most `count`.
    public func accepted(_ candidates: [String], count: Int = Self.count) -> [String] {
        var out: [String] = [], seen = Set<String>()
        guard count > 0 else { return out }
        for c in candidates.map(Self.tidy) where c.hasSuffix("?") && guardrail.isAcceptable(c, authorText: authorText) {
            guard seen.insert(CompanionGuard.normalize(c)).inserted else { continue }
            out.append(c)
            if out.count == count { break }
        }
        return out
    }

    /// `accepted`, then fallback questions (about `topic`, which must be the
    /// author's own words, such as the page's title) up to `count`.
    public func filled(_ accepted: [String], topic: String?, count: Int = Self.count) -> [String] {
        var out = Array(accepted.prefix(count)), seed = 0
        while out.count < count, seed < 8 {
            // About the topic first, then general ones.
            let q = FallbackQuestion.make(about: seed < 4 ? topic : nil, seed: seed)
            if !out.contains(q) { out.append(q) }
            seed += 1
        }
        return out
    }

    /// Without list numbering or bullets ("1. ", "- ") and outer whitespace.
    public static func tidy(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: #"^(\d+[.)]|[-•*])\s+"#, options: .regularExpression) { t.removeSubrange(r) }
        return t
    }
}
