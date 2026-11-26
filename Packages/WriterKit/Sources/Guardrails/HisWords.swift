import Foundation
import WriterCore

/// The author's own words as they go into a page (filing places them; Kevin, 2026-11-24: "It can
/// either append as a new sentence or insert it where appropriate and clean up
/// capitalization and punctuation"). Only case, punctuation and spacing change: no spelling
/// fixes (they would "correct" the names of his world), no "she" turned into a name, nothing
/// reworded (Kevin, 2026-11-26, approving the design). `sameWords` is the check that holds
/// it: nothing is placed whose words differ from the message's.
public enum HisWords {
    /// One line, tidied: spaces collapsed and none before punctuation; each sentence begun
    /// with a capital, and "i" as "I"; a full stop at the end if it ends in a letter or digit.
    public static func tidied(_ line: String) -> String {
        var text = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        for mark in [",", ".", "!", "?", ";", ":"] { text = text.replacingOccurrences(of: " " + mark, with: mark) }
        var sentenceStart = true
        let words = text.split(separator: " ").map { piece -> String in
            var word = String(piece)
            // "i", "i'm", "i," but not "it".
            if word.first == "i", word.dropFirst().first.map({ !$0.isLetter }) ?? true {
                word = "I" + word.dropFirst()
            }
            if sentenceStart, let letter = word.firstIndex(where: \.isLetter),
               !word[..<letter].contains(where: \.isNumber) {
                word.replaceSubrange(letter...letter, with: word[letter].uppercased())
            }
            if word.contains(where: { $0.isLetter || $0.isNumber }) {
                // A sentence ends at . ! or ?, before any closing quote or bracket.
                sentenceStart = word.last(where: { !closers.contains($0) }).map { ".!?".contains($0) } ?? false
            }
            return word
        }
        var out = words.joined(separator: " ")
        if let last = out.last, last.isLetter || last.isNumber { out += "." }
        return out
    }

    private static let closers: Set<Character> = ["\"", "'", "\u{201D}", "\u{2019}", ")", "]"]

    /// Whether `placed` says what `message` says, word for word: the same letters and
    /// digits, in the same words, whatever their case, punctuation and spacing.
    public static func sameWords(_ placed: String, _ message: String) -> Bool {
        words(placed) == words(message)
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }
    /// The paragraph of the author's on `page` that `sentence` fits at the end of: the one
    /// about the same thing, sharing the most of its telling words (two at least, or a
    /// name), the later of equals. Nil if none does: it goes at the end of the page. Lists
    /// are left alone, and so are words the whole page shares (its title).
    public static func fit(_ sentence: String, in page: Document) -> UUID? {
        let common = Set(stems(page.title))
        let telling = Set(stems(sentence)).subtracting(common)
        let names = Set(stems(namesIn(sentence)))
        var best: (id: UUID, score: Int)?
        for paragraph in page.paragraphs where paragraph.kind == .body && !paragraph.text.isEmpty {
            let shared = telling.intersection(stems(paragraph.text))
            let score = shared.count + shared.intersection(names).count
            if score >= 2, score >= best?.score ?? 0 { best = (paragraph.id, score) }
        }
        return best?.id
    }

    /// Words with a capital inside a sentence: names ("the Iron Abbey").
    private static func namesIn(_ text: String) -> String {
        var names: [Substring] = [], starts = true
        for word in text.split(separator: " ") {
            if !starts, word.first?.isUppercase == true { names.append(word) }
            starts = word.last.map { ".!?".contains($0) } ?? false
        }
        return names.joined(separator: " ")
    }

    /// `text`'s words that say something, each cut to its stem ("trained", "training": "train").
    static func stems(_ text: String) -> [String] {
        words(text.replacingOccurrences(of: "\u{2019}s", with: "").replacingOccurrences(of: "'s", with: ""))
            .filter { $0.count >= 3 && !small.contains($0) }
            .map { word in
                for suffix in ["ing", "ed", "es", "s"] where word.hasSuffix(suffix) && word.count - suffix.count >= 4 {
                    return String(word.dropLast(suffix.count))
                }
                return word
            }
    }

    /// Words too common to tell what a sentence is about.
    private static let small: Set<String> = [
        "the", "and", "but", "for", "nor", "yet", "with", "from", "into", "onto", "upon", "about", "over", "under",
        "after", "before", "then", "than", "that", "this", "these", "those", "there", "here", "what", "when", "where",
        "which", "who", "whom", "whose", "why", "how", "was", "were", "are", "is", "be", "been", "being", "has", "have",
        "had", "does", "did", "doing", "will", "would", "can", "could", "should", "shall", "may", "might", "must",
        "she", "her", "hers", "herself", "him", "his", "himself", "they", "them", "their", "theirs", "themselves",
        "its", "itself", "our", "ours", "you", "your", "yours", "not", "all", "any", "some", "each", "every", "one",
        "also", "just", "very", "only", "still", "even", "much", "many", "more", "most", "out", "off", "too", "now",
        "always", "never", "once", "again", "back", "because", "while", "until", "though", "although", "like",
    ]
}
