import Foundation

/// A ChatGPT data export's conversations (its `conversations.json`), read for the author's own
/// side: what they wrote, in order, on the branch each conversation ended on (Kevin, 2026-11-27:
/// "I'll just usually talk with ChatGPT and never actually formalize anything"; his past talks are
/// his world, unfiled). ChatGPT's replies are read only to know what each message answered, never
/// as the author's words (docs/ai-charter.md). Also the custom instructions he gave ChatGPT, which
/// are his own words about himself and how he wants replies.
public struct ChatGPTExport: Sendable {
    public struct Conversation: Sendable, Equatable {
        public var title: String
        public var created: Date?
        public var turns: [Turn]
    }

    /// One message of the author's, and what ChatGPT had said just before it (nil at the start).
    public struct Turn: Sendable, Equatable {
        public var answered: String?
        public var said: String
        public var date: Date?
    }

    /// What they told ChatGPT about themselves, and how they wanted it to reply.
    public struct Instructions: Sendable, Equatable {
        public var aboutMe: String?
        public var howToReply: String?
    }

    public var conversations: [Conversation]
    /// The newest custom instructions found in any conversation, if they set any.
    public var instructions: Instructions?

    /// `conversations.json` as exported: a list of conversations, each a tree of messages
    /// (`mapping`) whose branch shown last ends at `current_node`. Anything it can't read is
    /// left out, not guessed at.
    public init(_ data: Data) throws {
        let raw = try JSONDecoder().decode([Raw.Conversation].self, from: data)
        var conversations: [Conversation] = []
        var newest: (date: Double, instructions: Instructions)?
        for talk in raw {
            var turns: [Turn] = [], lastReply: String?
            for message in talk.branch() {
                if let found = message.instructions {
                    let date = message.create_time ?? talk.create_time ?? 0
                    if date >= newest?.date ?? -.infinity { newest = (date, found) }
                    continue
                }
                guard let text = message.text, !message.hidden else { continue }
                switch message.author.role {
                case "user":
                    turns.append(Turn(answered: lastReply, said: text, date: message.create_time.map(Date.init(timeIntervalSince1970:))))
                    lastReply = nil
                case "assistant":
                    lastReply = text
                default:
                    continue   // system and tool messages are neither side's words
                }
            }
            guard !turns.isEmpty else { continue }
            conversations.append(Conversation(title: talk.title ?? "", created: talk.create_time.map(Date.init(timeIntervalSince1970:)),
                                              turns: turns))
        }
        self.conversations = conversations
        self.instructions = newest?.instructions
    }

    /// The export's own shapes, as far as they're read.
    private enum Raw {
        struct Conversation: Decodable {
            var title: String?
            var create_time: Double?
            var mapping: [String: Node]
            var current_node: String?

            /// The messages from the first to `current_node`, following each node's parent.
            func branch() -> [Message] {
                var messages: [Message] = [], seen: Set<String> = []
                var id = current_node
                while let at = id, let node = mapping[at], seen.insert(at).inserted {
                    if let message = node.message { messages.append(message) }
                    id = node.parent
                }
                return messages.reversed()
            }
        }

        struct Node: Decodable {
            var message: Message?
            var parent: String?
        }

        struct Message: Decodable {
            struct Author: Decodable { var role: String }
            struct Content: Decodable {
                var content_type: String?
                var parts: [Part]?
                var user_profile: String?
                var user_instructions: String?
            }
            /// A part is text, or something else (a picture's pointer), which is left out.
            struct Part: Decodable {
                var text: String?
                init(from decoder: Decoder) throws {
                    text = try? decoder.singleValueContainer().decode(String.self)
                }
            }
            struct Metadata: Decodable {
                var is_visually_hidden_from_conversation: Bool?
                var user_context_message_data: Context?
            }
            struct Context: Decodable {
                var about_user_message: String?
                var about_model_message: String?
            }

            var author: Author
            var create_time: Double?
            var content: Content?
            var metadata: Metadata?

            var hidden: Bool { metadata?.is_visually_hidden_from_conversation == true }

            /// The message's words, from text parts only; nil when there are none.
            var text: String? {
                guard let content, ["text", "multimodal_text", nil].contains(content.content_type) else { return nil }
                let text = (content.parts ?? []).compactMap(\.text).joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }

            /// The custom instructions this message carries, if it's the one that does.
            var instructions: Instructions? {
                let context = metadata?.user_context_message_data
                let aboutMe = Self.words(context?.about_user_message ?? content?.user_profile)
                let howToReply = Self.words(context?.about_model_message ?? content?.user_instructions)
                guard content?.content_type == "user_editable_context" || context != nil,
                      aboutMe != nil || howToReply != nil else { return nil }
                return Instructions(aboutMe: aboutMe, howToReply: howToReply)
            }

            private static func words(_ text: String?) -> String? {
                let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return text.isEmpty ? nil : text
            }
        }
    }
}
