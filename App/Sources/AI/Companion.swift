import Foundation
import Guardrails
import OSLog
import WriterCore

/// The companion: talks with the author about the open page like a friend
/// they think out loud with. What it says comes from its instructions alone
/// (`CompanionPrompt`): nothing checks or filters a reply afterwards (Kevin's
/// ruling, 2026-11-23). It never writes into the page (docs/ai-charter.md).
@MainActor @Observable
final class Companion {
    enum State: Equatable {
        case idle, thinking, unavailable(String), failed
        /// The model's download lost its connection; trying again resumes it.
        case downloadPaused
    }

    private(set) var conversation = Conversation(page: UUID())
    private(set) var state = State.idle
    /// The reply so far, while the model is writing it.
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

    /// When the model on the phone was downloaded, for the menu.
    private(set) var modelVersion: String?
    /// A newer file of the model, if its maker has published one: offered in
    /// the menu, never fetched unasked (it's gigabytes, and it may not behave
    /// as the one the instructions were measured on).
    private(set) var modelUpdate: ModelUpdate?
    private var lookedForUpdate = false

    /// It thinks before it replies, unless the author turns that off: replies
    /// then start sooner. (Measured, thinking made no difference to how good
    /// its replies are; it broke the rules a little less often with it.)
    var thinks = UserDefaults.standard.object(forKey: "companionThinks") as? Bool ?? true {
        didSet { UserDefaults.standard.set(thinks, forKey: "companionThinks") }
    }

    // The one model the companion uses: the test's leader that runs on the
    // phone today (Kevin: one model, no choosing, as when it ships). Gemma,
    // set in `init`, wherever llama.cpp is; Apple's model elsewhere.
    #if canImport(AnyLanguageModel)
    static let modelName = GemmaModel.name
    #else
    static let modelName = "Apple's on-device model"   // the simulator: no llama.cpp there
    #endif
    private var model: any CompanionModel = AppleModel()
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
    /// prepare a reply quietly.
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

    /// Reads what's on the phone and, once per launch, asks whether there's a newer file.
    func checkModel() {
        modelVersion = model.version
        guard !lookedForUpdate else { return }
        lookedForUpdate = true
        Task { modelUpdate = await model.availableUpdate() }
    }

    /// Downloads the newer file (the download shows as the first one did) and uses it from the next reply.
    func updateModel() {
        guard let update = modelUpdate, state != .thinking else { return }
        Task {
            do {
                try await model.install(update)
                modelUpdate = nil
                modelVersion = model.version
            } catch {
                Self.log.error("Model update failed: \(String(describing: error), privacy: .public)")
            }
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

    /// The author's answer, in their words; then the companion's reply.
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

    /// Asks the model for a reply about `page`, shown as it's written.
    private func ask(about page: WriterCore.Document, in library: Library) async {
        guard conversation.waiting == nil, conversation.page == page.id else { return }
        if let reason = await model.unavailableReason { state = .unavailable(reason); return }
        state = .thinking
        defer { self.writing = nil; self.reasoning = nil }
        let page = library.pages.first { $0.id == page.id } ?? page   // as it is now, not when it opened
        let others = library.pages.filter { $0.id != page.id }
        let earlier = (store?.all() ?? []).filter { $0.page != page.id }.map { talk in
            (page: others.first { $0.id == talk.page }?.heading ?? "", conversation: talk)
        }
        var reply = Reasoned(reply: "")
        do {
            // Unusual text takes more of the model's context than its length
            // suggests: a prompt that doesn't fit is rebuilt with less background.
            for room in [1, 2, 4] {
                let prompt = CompanionPrompt(page: library.companionPage(page, open: true),
                                             others: others.map { library.companionPage($0) },
                                             earlier: earlier, conversation: conversation,
                                             maxCharacters: 6000 / room, maxTurnCharacters: 6000 / room)
                do {
                    for try await partial in model.stream(prompt, thinking: thinks) {
                        guard !Task.isCancelled else { break }
                        reply = partial
                        self.reasoning = partial.reasoning
                        self.writing = partial.reply
                    }
                    break
                } catch is PromptTooLong where room < 4 {
                    continue
                }
            }
        } catch {
            Self.log.error("Model failed: \(String(describing: error), privacy: .public)")
            trialLog("ERROR \(page.title): \(String(describing: error))")   // TRIAL
            state = error is URLError ? .downloadPaused : .failed
            return
        }
        guard !Task.isCancelled, conversation.page == page.id else { state = .idle; return }
        trialLog("REPLY \(page.title): \(reply.reply)")   // TRIAL
        guard !reply.reply.isEmpty else { state = .failed; return }   // ran out of room while thinking
        if modelVersion == nil { modelVersion = model.version }   // just downloaded
        conversation.ask(reply.reply)
        if !reply.reasoning.isEmpty, let turn = conversation.turns.last { thoughts[turn.id] = reply.reasoning }
        save()
        state = .idle
    }

    private func save() { try? store?.save(conversation) }
}

// TRIAL: every reply, and the model's speed and memory, pulled off the phone
// to see how it does there.
func trialLog(_ line: String) {
    let url = URL.documentsDirectory.appendingPathComponent("candidates.log")
    let data = Data((line.replacingOccurrences(of: "\n", with: " ") + "\n").utf8)
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() } else { try? data.write(to: url) }
}
