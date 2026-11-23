import Foundation

/// The companion's conversation about one page: its replies (`question`) and
/// the author's answers. The answers are the author's own words, so they count
/// as author text (docs/ai-charter.md): what the companion may quote and build on.
public struct Conversation: Codable, Hashable, Sendable {
    public struct Turn: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var question: String
        /// The author's answer, in their words; nil while the question waits.
        public var answer: String?
        public var asked: Date

        public init(id: UUID = UUID(), question: String, answer: String? = nil, asked: Date = Date()) {
            self.id = id
            self.question = question
            self.answer = answer
            self.asked = asked
        }
    }

    public var page: UUID
    public var turns: [Turn]

    public init(page: UUID, turns: [Turn] = []) {
        self.page = page
        self.turns = turns
    }

    /// The question waiting for an answer, if any.
    public var waiting: Turn? { turns.last.flatMap { $0.answer == nil ? $0 : nil } }

    /// Everything the author said here, in their words.
    public var authorText: String { turns.compactMap(\.answer).joined(separator: "\n") }

    public mutating func ask(_ question: String, at date: Date = Date()) {
        guard waiting == nil else { return }
        turns.append(Turn(question: question, asked: date))
    }

    public mutating func answer(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = turns.indices.last, turns[i].answer == nil else { return }
        turns[i].answer = trimmed
    }
}

/// Conversations as JSON files, one per page, beside a world's pages.
public final class ConversationStore: @unchecked Sendable {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(_ page: UUID) -> URL { directory.appendingPathComponent("\(page.uuidString).json") }

    public func load(_ page: UUID) -> Conversation {
        (try? Data(contentsOf: url(page))).flatMap { try? JSONDecoder().decode(Conversation.self, from: $0) }
            ?? Conversation(page: page)
    }

    public func save(_ conversation: Conversation) throws {
        try JSONEncoder().encode(conversation).write(to: url(conversation.page), options: [.atomic])
    }

    /// Every page's conversation in this world.
    public func all() -> [Conversation] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap {
            (try? Data(contentsOf: $0)).flatMap { try? JSONDecoder().decode(Conversation.self, from: $0) }
        }
    }

    public func delete(_ page: UUID) {
        try? FileManager.default.removeItem(at: url(page))
    }
}
