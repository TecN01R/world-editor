import Foundation

/// The writer's standing instructions for the companion (Kevin, 2026-11-25: "keep the prompting
/// but keep it blank and the user can fill in instructions over time and the model can write its
/// own instructions based on what the user tells it to do"). Blank at first, so the model runs
/// stock. The writer edits them (Instructions… in the companion's menu), and the model adds one
/// with `add_instruction` when the writer tells it how to reply from now on. Read before every
/// reply, after the line on what's open (`CompanionPrompt.plain`).
public enum Instructions {
    public static let toolName = "add_instruction"
    public static let toolDescription = "Adds an instruction to the writer's standing instructions for you, which you "
        + "read before every reply. Use it only when the writer tells you how they want you to reply from now on. "
        + "One short instruction a call."
    /// Its one argument, and the guide to it.
    public static let argument = "instruction"
    public static let argumentGuide = "The instruction, as you'll read it (\"Don't suggest names unless they ask.\")"
    /// At most this many a reply.
    public static let perReply = 2
    public static let added = "Added. You'll read it before every reply from now on."
    public static let needsInstruction = "Nothing was added: give the instruction to add."
    public static let lastOne = "Nothing was added: that's as many as one reply adds. Answer the writer now."

    /// The instructions as the prompt shows them, under a line saying whose they are; nil when
    /// there are none.
    public static func shown(_ text: String?) -> String? {
        let text = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : "The writer's instructions for you:\n" + text
    }

    /// `text` with each of `new` on a line of its own after it.
    public static func adding(_ new: [String], to text: String?) -> String {
        let text = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ([text] + new).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
