import Foundation
import Guardrails
import OSLog
import WriterCore

/// The companion: talks with the author about the open page like a friend
/// they think out loud with, to draw out what they know but haven't written.
/// With `guarded` on, its replies pass `Interviewer.screen` (no prose,
/// suggestions or inventions) or are replaced by nothing at all; it never
/// writes into the page (docs/ai-charter.md).
@MainActor @Observable
final class Companion {
    enum State: Equatable {
        case idle, thinking, unavailable(String), failed
        /// No reply passed the guard: it says nothing rather than something stock.
        case quiet
        /// The model's download lost its connection; trying again resumes it.
        case downloadPaused
    }

    private(set) var conversation = Conversation(page: UUID())
    private(set) var state = State.idle
    /// The reply so far, while the model is writing it (the guard off).
    private(set) var writing: String?
    /// What it's thinking, while it thinks before replying.
    private(set) var reasoning: String?
    /// What it thought before each of its replies, for this session only: shown
    /// collapsed, never saved or sent back to the model (its makers' advice).
    private(set) var thoughts: [UUID: String] = [:]
    /// The panel is showing: beside the page unfolded, a sheet folded.
    var isOpen = false
    /// The Duo is folded (compact width): the companion is a sheet, not a column.
    var folded = true

    /// The model's first download, while it runs.
    private(set) var download: Download?

    // The one model the companion uses: the test's leader that runs on the
    // phone today (Kevin: one model, no choosing, as when it ships). Gemma,
    // set in `init`, wherever llama.cpp is; Apple's model elsewhere.
    #if canImport(AnyLanguageModel)
    static let modelName = GemmaModel.name
    #else
    static let modelName = "Apple's on-device model"   // the simulator: no llama.cpp there
    #endif
    private var model: any QuestionModel = AppleModel()
    private var store: ConversationStore?
    private var preparing: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.tecn01r.worldeditor", category: "companion")

    init() {
        #if canImport(AnyLanguageModel)
        model = GemmaModel { [weak self] download in
            Task { @MainActor in
                self?.download = download
                BackgroundDownload.update(download)   // keeps going if the author leaves the app
            }
        }
        #endif
    }

    /// The open page changed: load its conversation and, after a pause,
    /// prepare a question quietly.
    func open(_ page: WriterCore.Document, in library: Library) {
        preparing?.cancel()
        store = library.conversationsDirectory.flatMap { try? ConversationStore(directory: $0) }
        conversation = store?.load(page.id) ?? Conversation(page: page.id)
        state = .idle
        guard conversation.waiting == nil else { return }   // a blank page too: it helps you start
        preparing = Task {
            try? await Task.sleep(for: .seconds(2))   // settle: the author may be passing through
            guard !Task.isCancelled else { return }
            await ask(about: page, in: library)
        }
    }

    /// Asks again now, in place of any waiting reply.
    func retry(page: WriterCore.Document, in library: Library) {
        if conversation.waiting != nil { conversation.turns.removeLast() }
        askNow(about: page, in: library)
    }

    /// Forgets this page's conversation and starts afresh.
    func startOver(page: WriterCore.Document, in library: Library) {
        store?.delete(page.id)
        conversation = Conversation(page: page.id)
        state = .idle
        askNow(about: page, in: library)
    }

    /// The author's answer, in their words; then the next question.
    func answer(_ text: String, page: WriterCore.Document, in library: Library) {
        conversation.answer(text)
        save()
        askNow(about: page, in: library)
    }

    /// Drops whatever was being prepared and asks now.
    private func askNow(about page: WriterCore.Document, in library: Library) {
        preparing?.cancel()
        preparing = Task { await ask(about: page, in: library) }
    }

    /// Asks the model for a reply about `page`: up to five tries, each
    /// screened; if none passes, it stays quiet.
    private func ask(about page: WriterCore.Document, in library: Library) async {
        guard conversation.waiting == nil, conversation.page == page.id else { return }
        if let reason = await model.unavailableReason { state = .unavailable(reason); return }
        state = .thinking
        defer { self.writing = nil; self.reasoning = nil }
        let page = library.pages.first { $0.id == page.id } ?? page   // as it is now, not when it opened
        let writing = page.paragraphs.map(\.text).joined(separator: "\n")
        let fields = library.fieldText(page)
        let focus = [page.title, fields, writing, conversation.authorText].joined(separator: "\n")
        let world = library.worldSummary(except: page.id, focus: focus)
        let others = (store?.all() ?? []).filter { $0.page != page.id }
        let memory = Interviewer.memory(others.map { talk in
            (library.pages.first { $0.id == talk.page }?.heading ?? "", talk)
        }, focus: focus)
        // Everything the author wrote that the model sees: other pages and answers included.
        let authorText = ([page.title, fields, writing, world, conversation.authorText] + others.map(\.authorText))
            .joined(separator: "\n")
        var prompt = Interviewer.prompt(title: page.title, type: library.type(of: page)?.name, fields: fields,
                                        writing: writing, world: world, memory: memory, conversation: conversation)
        if !guarded { prompt.system = Self.plainInstructions }   // TRIAL
        let asked = conversation.turns.map(\.question)
        var question: String?
        for attempt in 1...(guarded ? 5 : 1) where question == nil {
            guard !Task.isCancelled else { state = .idle; return }
            do {
                let reply: String
                if guarded {   // the guard needs the whole reply before any of it shows
                    reply = try await model.propose(prompt)
                    question = Interviewer.screen(reply, authorText: authorText, asked: asked)
                } else {
                    var text = ""
                    // Always thinks first (Kevin: thinking on, no switch).
                    for try await partial in model.stream(prompt, thinking: true) {
                        guard !Task.isCancelled else { break }
                        text = partial.reply
                        self.reasoning = partial.reasoning
                        self.writing = partial.reply
                    }
                    reply = text
                    let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    question = whole.isEmpty ? nil : whole
                }
                if question == nil { Self.log.info("Rejected (try \(attempt)): \(reply, privacy: .private)") }
                let verdict: String
                if question == nil {
                    verdict = "REJECTED"
                } else if CompanionGuard.offersChoices(reply) {
                    verdict = "KEPT, FLAG either-or"
                } else {
                    verdict = "KEPT"
                }
                trialLog("\(verdict) \(page.title): \(reply)")   // TRIAL
            } catch {
                Self.log.error("Model failed: \(String(describing: error), privacy: .public)")
                trialLog("ERROR \(page.title): \(String(describing: error))")   // TRIAL
                state = error is URLError ? .downloadPaused : .failed
                return
            }
        }
        guard !Task.isCancelled, conversation.page == page.id else { state = .idle; return }
        guard let question else { state = .quiet; return }
        conversation.ask(question)
        if let reasoning, !reasoning.isEmpty, let turn = conversation.turns.last { thoughts[turn.id] = reasoning }
        save()
        state = .idle
    }

    private func save() { try? store?.save(conversation) }

    // TRIAL (Kevin, 2026-11-23): no guard while we find out which model is a good
    // companion; only his rules, in the instructions. Same text as
    var guarded = UserDefaults.standard.bool(forKey: "companionGuarded") {
        didSet { UserDefaults.standard.set(guarded, forKey: "companionGuarded") }
    }

    static let plainInstructions = """
    You're a friend the writer talks to and bounces ideas off while they build their world. Talk \
    with them like a person in a chat: react to what they say, think it through with them, answer \
    their questions, give your honest opinion when it helps, and ask about what you're curious \
    about. You don't have to be the expert.

    Three rules, and only three:
    - Never invent anything about their world. No names, places, events, details, motives or \
    ideas they haven't given you. Everything about their world comes from them.
    - Never write their story for them unless they ask you to.
    - Never ask a pointless question: don't repeat what they just said back to them as a \
    question, and don't ask something they've already answered or you've already asked.

    You'll see their other pages, what they've told you before, and the page they're on (help \
    them start if it's blank).
    """
}

// TRIAL: every candidate and the guard's verdict, and the models' speed and
// memory, pulled off the phone to compare models.
func trialLog(_ line: String) {
    let url = URL.documentsDirectory.appendingPathComponent("candidates.log")
    let data = Data((line.replacingOccurrences(of: "\n", with: " ") + "\n").utf8)
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() } else { try? data.write(to: url) }
}
