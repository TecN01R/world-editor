import Foundation
import WriterCore

/// A model's output split into what it thought and what it said. Thinking
/// models write their reasoning before the reply; the reasoning is shown apart
/// (collapsed) and never kept in the conversation, as the models' makers advise.
public struct Reasoned: Equatable, Sendable {
    public var reasoning: String
    public var reply: String
    /// What it searched the author's pages for while replying, in order (`PageLookup`):
    /// shown as "Searched your pages for …" and kept with the reply (`Conversation.Turn.searches`).
    public var searches: [String]
    /// What it looked up in the real world while replying, and found (`WebLookup`): shown as
    /// "Searched Wikipedia for …" under the reply, with its sources.
    public var lookups: [LookedUp]

    public init(reasoning: String = "", reply: String = "", searches: [String] = [], lookups: [LookedUp] = []) {
        self.reasoning = reasoning
        self.reply = reply
        self.searches = searches
        self.lookups = lookups
    }

    /// Gemma 4's output, whole or so far: `<|channel>thought\n…<channel|>reply`
    /// (its chat template's format). Before the channel closes, everything is
    /// reasoning and the reply is empty; without a channel, it's all reply.
    public static func gemma(_ output: String) -> Reasoned {
        guard let open = output.range(of: "<|channel>") else { return Reasoned(reply: tidy(output)) }
        let before = output[..<open.lowerBound]
        var rest = output[open.upperBound...]
        if rest.hasPrefix("thought") { rest = rest.dropFirst("thought".count) }
        guard let close = rest.range(of: "<channel|>") else {
            return Reasoned(reasoning: tidy(rest), reply: tidy(before))
        }
        return Reasoned(reasoning: tidy(rest[..<close.lowerBound]), reply: tidy(before + rest[close.upperBound...]))
    }

    private static func tidy(_ text: some StringProtocol) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `text` as Gemma 4 reads plain words. Its prompt is tokenized with its
    /// control tokens recognised anywhere, so one typed on a page (`<turn|>`,
    /// say, in notes about chat formats) would end the turn it sits in: a
    /// zero-width space inside each keeps them words. Every one of its control
    /// tokens has `<|` or `|>` in it, but for the few listed here.
    public static func gemmaPlain(_ text: String) -> String {
        guard text.contains("<") || text.contains("|>") else { return text }
        var text = text.replacingOccurrences(of: "<|", with: "<\u{200B}|").replacingOccurrences(of: "|>", with: "|\u{200B}>")
        for token in ["<bos>", "<eos>", "<pad>", "<unk>", "<mask>", "<__media__>"] {   // the last is llama.cpp's image marker
            text = text.replacingOccurrences(of: token, with: "<\u{200B}" + token.dropFirst())
        }
        return text
    }
}
