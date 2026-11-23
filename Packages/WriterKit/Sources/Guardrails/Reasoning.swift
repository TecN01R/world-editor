import Foundation

/// A model's output split into what it thought and what it said. Thinking
/// models write their reasoning before the reply; the reasoning is shown apart
/// (collapsed) and never kept in the conversation, as the models' makers advise.
public struct Reasoned: Equatable, Sendable {
    public var reasoning: String
    public var reply: String

    public init(reasoning: String = "", reply: String) {
        self.reasoning = reasoning
        self.reply = reply
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
}
