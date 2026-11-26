import Foundation

/// The author's own words as they go into a page (Add to Page; Kevin, 2026-11-24: "It can
/// either append as a new sentence or insert it where appropriate and clean up
/// capitalization and punctuation"). Only case, punctuation and spacing change: no spelling
/// fixes (they would "correct" the names of his world), no "she" turned into a name, nothing
/// reworded (Kevin, 2026-11-26, approving the design). `sameWords` is the check that holds
/// it: nothing is placed whose words differ from the message's.
public enum HisWords {
    /// `message` as page paragraphs, one per line of it, each tidied (`tidied`).
    public static func paragraphs(_ message: String) -> [String] {
        message.split(whereSeparator: \.isNewline).map { tidied(String($0)) }.filter { !$0.isEmpty }
    }

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

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }
}
