import Foundation

/// The companion's conversation about one page (or the whole world: `aboutWorld`):
/// its replies (`question`) and the author's answers. The answers are the author's
/// own words, so they count as author text (docs/ai-charter.md): what the companion
/// may quote and build on.
public struct Conversation: Codable, Hashable, Sendable {
    public struct Turn: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var question: String
        /// The author's answer, in their words; nil while the question waits.
        public var answer: String?
        public var asked: Date
        /// When they answered (conversations from before it was kept: nil).
        public var answered: Date?
        /// The open page's fields and title when they answered: the first reading of the
        /// answer may change only what's still as it was then.
        public var seen: [UUID: FieldValue]?
        public var seenTitle: String?
        /// What was filed from the answer (types, fields, new pages), until undone.
        public var filed: FilingRecord?

        /// Its answer is still to be filed: never read, or read with nothing found and
        /// nothing undone, so Try Again reads it again (Kevin's "I think it was actually a
        /// bireme", read by a weaker model the first time, 2026-11-24).
        public var needsFiling: Bool { answer != nil && (filed?.filedNothing ?? true) }
        /// Every reply it gave here, oldest first, once Try Again made more than one;
        /// `question` is the one chosen: the one showing when the author answered,
        /// which the conversation goes on from (Kevin, 2026-11-24).
        public var versions: [String]?
        /// What the companion searched the author's pages for while writing each of its
        /// replies here (`question` or one of `versions`), in order, for the "Searched your
        /// pages for …" line. Kept so the line survives reopening; never sent to the model.
        public var searches: [String: [String]]?

        public init(id: UUID = UUID(), question: String, answer: String? = nil, asked: Date = Date(),
                    filed: FilingRecord? = nil) {
            self.id = id
            self.question = question
            self.answer = answer
            self.asked = asked
            self.filed = filed
        }
    }

    /// The page it's about; a conversation about the whole world has its own id here.
    public var page: UUID
    public var turns: [Turn]
    /// About the whole world, not one page: one of the world's conversations listed
    /// under the pages list's Companion (Kevin, 2026-11-24).
    public var aboutWorld: Bool

    public init(page: UUID, turns: [Turn] = [], aboutWorld: Bool = false) {
        self.page = page
        self.turns = turns
        self.aboutWorld = aboutWorld
    }

    private enum CodingKeys: String, CodingKey { case page, turns, aboutWorld }

    /// Conversations saved before `aboutWorld` load as a page's.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        page = try c.decode(UUID.self, forKey: .page)
        turns = try c.decode([Turn].self, forKey: .turns)
        aboutWorld = try c.decodeIfPresent(Bool.self, forKey: .aboutWorld) ?? false
    }

    /// What a list shows for it: the author's first words, on one line.
    public var title: String? {
        guard let first = turns.lazy.compactMap(\.answer).first else { return nil }
        return first.split(whereSeparator: \.isNewline).first.map(String.init) ?? first
    }

    /// When it was last added to.
    public var lastActive: Date? {
        turns.last.map { $0.answered ?? $0.asked }
    }

    /// The question waiting for an answer, if any.
    public var waiting: Turn? { turns.last.flatMap { $0.answer == nil ? $0 : nil } }

    /// One filed change, and the answer it was filed from.
    public struct Filed: Hashable, Sendable {
        public var action: FilingRecord.Entry
        public var turn: UUID
        public init(action: FilingRecord.Entry, turn: UUID) {
            self.action = action
            self.turn = turn
        }
    }

    /// Whether something filed since changed what `action` (filed from `turn`) did, so it
    /// can't be undone until that is: Undo goes newest first for each field and page
    /// (Kevin, 2026-11-24), so taking back an old value never revives one already undone.
    /// `elsewhere`: the world's other conversations, whose filings can change this page too.
    /// - Parameter except: changes to leave out (being undone with it: `undoChain`, `rewind`).
    public func changedLater(_ action: FilingRecord.Entry, in turn: UUID, elsewhere: [Conversation] = [],
                             except: Set<Filed> = []) -> Bool {
        guard let t = turns.firstIndex(where: { $0.id == turn }), let actions = turns[t].filed?.actions,
              let at = actions.firstIndex(of: action) else { return false }
        func changed(by later: FilingRecord.Entry, from id: UUID, sameMessage: Bool) -> Bool {
            !except.contains(Filed(action: later, turn: id)) && action.isChanged(by: later, sameMessage: sameMessage)
        }
        func changes(_ turn: Turn) -> Bool {
            (turn.filed?.actions ?? []).contains { changed(by: $0, from: turn.id, sameMessage: false) }
        }
        // When each was filed (older records: when it was answered).
        func filed(_ turn: Turn) -> Date { turn.filed?.date ?? turn.answered ?? turn.asked }
        let when = filed(turns[t])
        return actions[(at + 1)...].contains { changed(by: $0, from: turn, sameMessage: true) }
            || turns[(t + 1)...].contains(where: changes)
            || elsewhere.contains { $0.page != page && $0.turns.contains { filed($0) > when && changes($0) } }
    }

    /// What undoing `action` (filed from `turn`) takes back with it: everything filed
    /// since in this conversation that changed what it did, and whatever changed those,
    /// in the order to undo them, newest first, `action` last (Kevin, 2026-11-24: "undo
    /// to this point and all layered changes would be undone"). nil when something filed
    /// from another conversation built on one of them: that's undone there first.
    public func undoChain(_ action: FilingRecord.Entry, in turn: UUID, elsewhere: [Conversation] = []) -> [Filed]? {
        // Every action in the order filed, with the index of the message it came from.
        let all = turns.enumerated().flatMap { t, turn in
            (turn.filed?.actions ?? []).map { (message: t, filed: Filed(action: $0, turn: turn.id)) }
        }
        guard let start = all.firstIndex(where: { $0.filed == Filed(action: action, turn: turn) }) else { return nil }
        // Oldest first: each later one joins if it changed something already in the chain.
        var chain = [all[start]]
        for later in all[(start + 1)...] where chain.contains(where: {
            $0.filed.action.isChanged(by: later.filed.action, sameMessage: $0.message == later.message)
        }) {
            chain.append(later)
        }
        let undone = Set(chain.map { $0.filed })
        // Built on from elsewhere: changedLater would still hold once these are undone.
        guard !undone.contains(where: { changedLater($0.action, in: $0.turn, elsewhere: elsewhere, except: undone) })
        else { return nil }
        return chain.reversed().map { $0.filed }
    }

    /// What going back to before `turn`'s answer takes back: everything filed from it and
    /// from every answer since, newest first (Changes' timeline, Kevin, 2026-11-24: "it
    /// should be a timeline"). nil when something filed from another conversation built
    /// on one of them: that's undone there first.
    public func rewind(to turn: UUID, elsewhere: [Conversation] = []) -> [Filed]? {
        guard let t = turns.firstIndex(where: { $0.id == turn }) else { return nil }
        let chain = turns[t...].flatMap { turn in (turn.filed?.actions ?? []).map { Filed(action: $0, turn: turn.id) } }
        let undone = Set(chain)
        // Everything later here goes with them, so only another conversation's filings can stop it.
        guard !chain.contains(where: { changedLater($0.action, in: $0.turn, elsewhere: elsewhere, except: undone) })
        else { return nil }
        return chain.reversed()
    }

    /// Everything the author said here, in their words.
    public var authorText: String { turns.compactMap(\.answer).joined(separator: "\n") }

    /// The companion's reply, and what it searched the author's pages for while writing it.
    public mutating func ask(_ question: String, searches: [String] = [], at date: Date = Date()) {
        guard waiting == nil else { return }
        var turn = Turn(question: question, asked: date)
        if !searches.isEmpty { turn.searches = [question: searches] }
        turns.append(turn)
    }

    /// Takes the waiting reply back to ask again: the turn, to restore if asking fails.
    public mutating func retract() -> Turn? {
        guard waiting != nil else { return nil }
        return turns.removeLast()
    }

    /// The new reply in place of `retracted` (if Try Again took one back), which is kept with
    /// its versions and what each searched for.
    public mutating func ask(_ question: String, after retracted: Turn?, searches: [String] = [], at date: Date = Date()) {
        ask(question, searches: searches, at: date)
        guard let retracted else { return }
        let earlier = (retracted.versions ?? [retracted.question]).filter { $0 != question }
        guard !earlier.isEmpty, let i = turns.indices.last else { return }
        turns[i].versions = earlier + [question]
        let kept = (retracted.searches ?? [:]).filter { earlier.contains($0.key) }.merging(turns[i].searches ?? [:]) { $1 }
        turns[i].searches = kept.isEmpty ? nil : kept
    }

    /// Makes `version` the reply the conversation goes on from, while it waits for an answer
    /// (once answered, the one they answered stays).
    public mutating func choose(_ version: String, in turn: UUID) {
        guard let i = turns.firstIndex(where: { $0.id == turn }), turns[i].answer == nil,
              turns[i].versions?.contains(version) == true else { return }
        turns[i].question = version
    }

    /// Deletes one of a waiting turn's versions (never its last); if it was the chosen one, the one before it is chosen.
    public mutating func delete(_ version: String, in turn: UUID) {
        guard let i = turns.firstIndex(where: { $0.id == turn }), turns[i].answer == nil, var versions = turns[i].versions,
              versions.count > 1, let at = versions.firstIndex(of: version) else { return }
        versions.remove(at: at)
        if turns[i].question == version { turns[i].question = versions[max(at - 1, 0)] }
        turns[i].versions = versions.count > 1 ? versions : nil
        if !versions.contains(version) { turns[i].searches?[version] = nil }
        if turns[i].searches?.isEmpty == true { turns[i].searches = nil }
    }

    /// The author's words: an answer to the waiting reply, or, if nothing has been said
    /// yet, the conversation's first words (the world's conversation waits for them;
    /// Kevin, 2026-11-24), on a turn with no reply before it.
    public mutating func answer(_ text: String, at date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if turns.isEmpty { turns.append(Turn(question: "", asked: date)) }
        guard let i = turns.indices.last, turns[i].answer == nil else { return }
        turns[i].answer = trimmed
        turns[i].answered = date
    }

    /// One value filing gave a field, for the field's timeline.
    public struct FieldChange: Hashable, Sendable, Identifiable {
        public var turn: UUID
        public var action: FilingRecord.Entry
        public var value: FieldValue
        /// The author's message it came from, and when they sent it.
        public var message: String
        public var date: Date
        /// Itself: the same value can be filed again from another message.
        public var id: Self { self }
    }

    /// Every value filing gave `field` of `page` in this conversation and that hasn't
    /// been undone, oldest first (Kevin, 2026-11-24: a timeline for a field changed more than once).
    public func history(of field: UUID, on page: UUID) -> [FieldChange] {
        turns.flatMap { turn in
            (turn.filed?.actions ?? []).compactMap { action -> FieldChange? in
                guard action.page == page, action.field == field, let value = action.value else { return nil }
                return FieldChange(turn: turn.id, action: action, value: value, message: turn.answer ?? "",
                                   date: turn.answered ?? turn.asked)
            }
        }
    }
}

/// Conversations as JSON files, one per page, beside a world's pages.
public final class ConversationStore: @unchecked Sendable {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func file(_ page: UUID) -> SavedFile<Conversation> {
        SavedFile(url: directory.appendingPathComponent("\(page.uuidString).json"))
    }

    /// The page's conversation; an empty one when nothing's been said. Throws
    /// `UnreadableFile` for a file this version can't read, which saving then leaves alone.
    public func load(_ page: UUID) throws -> Conversation {
        try file(page).read() ?? Conversation(page: page)
    }

    public func save(_ conversation: Conversation) throws {
        try file(conversation.page).write(conversation)
    }

    /// Every conversation in this world that this version can read.
    public func all() -> [Conversation] { scan().conversations }

    /// Every conversation in this world, and the files this version can't read.
    public func scan() -> (conversations: [Conversation], unreadable: [URL]) {
        let found = SavedFile<Conversation>.all(in: directory)
        return (found.values, found.unreadable)
    }

    /// Whether the author has said anything on this page. A conversation this version
    /// can't read counts as yes, so nothing is thrown away on a guess.
    public func hasTalk(_ page: UUID) -> Bool {
        (try? load(page)).map { !$0.authorText.isEmpty } ?? true
    }

    /// Deletes the page's conversation, unless this version can't read it.
    public func delete(_ page: UUID) {
        try? file(page).delete()
    }
}
