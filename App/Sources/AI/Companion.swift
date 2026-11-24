import Foundation
import Guardrails
import OSLog
import WriterCore

/// The companion: talks with the author about the open page like a friend
/// they think out loud with. What it says comes from its instructions alone
/// (`CompanionPrompt`): nothing checks or filters a reply afterwards (Kevin's
/// ruling, 2026-11-23). It never writes into the page (docs/ai-charter.md);
/// after each reply, what the author said is filed into the world's types,
/// fields and pages, in their words, with Undo (`Filer`; Kevin's ruling, 2026-11-23).
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
    /// How much of its prompt the model has read (0 to 1), while it reads before writing:
    /// tens of seconds on the 26B, shown so it doesn't look stuck (Kevin, 2026-11-24).
    private(set) var reading: Double?
    /// What it thought before each of its replies (by the reply, so each tried
    /// version keeps its own), for this session only: shown collapsed, never saved
    /// or sent back to the model (its makers' advice).
    private(set) var thoughts: [String: String] = [:]
    /// The panel is showing: beside the page unfolded, a sheet folded. Opening it
    /// prepares the open page's reply, if one is due (`prepareSoon`).
    var isOpen = false {
        didSet { if isOpen, !oldValue { prepareSoon() } }
    }
    /// The Duo is folded (compact width): the companion is a sheet, not a column.
    var folded = true

    /// The model's first download, while it runs.
    private(set) var download: Download?
    /// Why the download couldn't go ahead (too little free space), shown with its offer.
    private(set) var downloadNote: String?

    /// When the model on the phone was downloaded, for the menu.
    private(set) var modelVersion: String?

    /// Replies don't think first, and there's no switch for it (Kevin, 2026-11-24:
    /// "remove the thinking switch, trigger as necessary"): on the 26B its thinking
    /// drafted the reply four or five times at the phone's 7 tokens a second, minutes
    /// were. A reply that needs it turns it on: search, once it's in the app, if the
    private let thinks = false

    /// TRIAL (Kevin, 2026-11-24): the model with none of the app's instructions,
    /// examples or pages, only the conversation (`CompanionPrompt.plain`), to see
    /// how it does on its own.
    var plain = UserDefaults.standard.bool(forKey: "companionPlain") {
        didSet { UserDefaults.standard.set(plain, forKey: "companionPlain") }
    }
    /// The reply Try Again took back, kept as a version of the next one, or put back if that fails.
    private var retracted: Conversation.Turn?
    /// The world's other conversations, as of opening this page: their filings can
    /// change this page too, so Undo, newest first, looks at them as well.
    private(set) var others: [Conversation] = []
    /// The world's conversations about the world as a whole, newest first, for their list.
    private(set) var worldConversations: [Conversation] = []

    // The one model the companion uses (Kevin: one model, no choosing, as when it
    // ships): Gemma 4 26B, set in `init`, wherever TurboFieldfare is; Apple's
    // model elsewhere.
    #if canImport(TurboFieldfare)
    static let modelName = TurboModel.name
    #else
    static let modelName = "Apple's on-device model"   // the simulator: no TurboFieldfare there
    #endif
    /// The model isn't on the phone, and the author hasn't asked for it yet:
    /// the companion offers the download and does nothing else until then.
    private(set) var needsDownload = false
    /// The size of that download, once known.
    private(set) var downloadSize: Int64?
    private var model: any CompanionModel = AppleModel()
    private var store: ConversationStore?
    private var preparing: Task<Void, Never>?
    /// Counts asks, so one dropped for a newer one knows it.
    private var asks = 0
    /// The page open now (a world conversation's stand-in), whose reply is prepared when the companion opens.
    private var opened: (page: WriterCore.Document, library: Library)?
    /// Filing what the author last said; the next reply waits for it (one model, one job at a time).
    private var filing: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.tecn01r.worldeditor", category: "companion")

    init() {
        #if canImport(TurboFieldfare)
        model = TurboModel { [weak self] download in
            Task { @MainActor in
                self?.download = download
                BackgroundDownload.update(download)   // keeps going if the author leaves the app
            }
        }
        #endif
        if model.isInstalled {
            Task { [model] in await FilingLab.runIfAsked(with: model) }   // TRIAL
        } else {
            offerDownload()
        }
    }

    /// The author asked for the model: download it, then reply about the page open
    /// by then. Also resumes a download that lost its connection. The download is a
    /// task of its own, which opening another page or asking again never stops: it
    /// takes 10 to 30 minutes, and the author goes on writing meanwhile.
    func startDownload(page: WriterCore.Document, in library: Library) {
        guard download == nil else { return }
        opened = (page, library)
        // The download shows from the tap: the first progress report comes a
        // moment later, and in between the conversation would flash up (Kevin).
        download = Download(done: 0, total: downloadSize ?? 0, detail: "Starting…")
        downloadNote = nil
        needsDownload = false
        state = .idle
        preparing?.cancel()   // no reply while it downloads
        Task {
            do {
                try await model.prepare()
                download = nil
                modelVersion = model.version
                prepareSoon()   // if a reply is due (a new or blank page)
            } catch let blocked as DownloadBlocked {
                download = nil
                downloadNote = blocked.reason
                needsDownload = true
            } catch {
                download = nil
                Self.log.error("Download failed: \(String(describing: error), privacy: .public)")
                // A dropped connection shows Download Paused, which resumes; anything
                // else goes back to offering the download, never starting it unasked.
                if error is URLError { state = .downloadPaused } else { needsDownload = !model.isInstalled }
            }
        }
    }

    /// The open page changed: load its conversation and, after a pause, prepare a
    /// reply quietly (`prepareSoon`).
    /// - Parameter aboutWorld: a conversation about the whole world (`page` is a stand-in).
    func open(_ page: WriterCore.Document, in library: Library, aboutWorld: Bool = false) {
        let directory = library.conversationsDirectory
        // The same page again (folding or unfolding rebuilds the editor): leave a reply or
        // Try Again in progress alone.
        guard page.id != conversation.page || directory != store?.directory else { return }
        opened = (page, library)
        preparing?.cancel()
        store = directory.flatMap { try? ConversationStore(directory: $0) }
        conversation = (try? store?.load(page.id)) ?? Conversation(page: page.id)
        // (The first world conversation, from before there were several, went by the world's id.)
        if aboutWorld || page.id == library.world.id { conversation.aboutWorld = true }
        others = (store?.all() ?? []).filter { $0.page != page.id }
        retracted = nil
        if state != .downloadPaused { state = .idle }   // a paused download stays on offer
        guard conversation.waiting == nil else { return }   // a blank page too: it helps you start
        prepareSoon(after: .seconds(2))   // settle: the author may be passing through
    }

    /// Prepares the open page's reply after `pause`, if one is due, only while the
    /// companion is open: on this model a reply is minutes of the GPU's work, too much
    /// to spend on every page passed through with it closed. Not while the phone is hot
    /// or in Low Power Mode either: the author begins instead.
    private func prepareSoon(after pause: Duration = .zero) {
        let phone = ProcessInfo.processInfo
        guard isOpen, download == nil, state == .idle, let opened,
              phone.thermalState != .serious, phone.thermalState != .critical, !phone.isLowPowerModeEnabled else { return }
        preparing?.cancel()
        preparing = Task {
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            await ask(about: opened.page, in: opened.library)
        }
    }

    /// The model isn't on the phone (never downloaded, or its files failed their check
    /// and were removed): the download is offered, never started unasked.
    private func offerDownload() {
        needsDownload = true
        state = .idle
        Task { downloadSize = await model.downloadSize() }
    }

    /// Reads when the model on the phone was downloaded, for the menu.
    func readModelVersion() {
        modelVersion = model.version
    }

    /// Asks again now, in place of any waiting reply, which is kept as a version of the new one.
    func retry(page: WriterCore.Document, in library: Library) {
        if let turn = conversation.retract() { retracted = turn }
        askNow(about: page, in: library)
    }

    /// Goes on from this version of a reply.
    func choose(_ version: String, in turn: UUID) {
        conversation.choose(version, in: turn)
        save()
    }

    func delete(_ version: String, in turn: UUID) {
        conversation.delete(version, in: turn)
        save()
    }

    /// Lists the world's conversations about the world as a whole, newest first.
    func loadWorldConversations(in library: Library) {
        let store = library.conversationsDirectory.flatMap { try? ConversationStore(directory: $0) }
        worldConversations = (store?.all() ?? [])
            .filter { Self.isAboutWorld($0, in: library) && !$0.turns.isEmpty }
            .sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
    }

    /// About the world as a whole: marked so, or the first world conversation, which (from
    /// before there were several) went by the world's id.
    private static func isAboutWorld(_ talk: Conversation, in library: Library) -> Bool {
        talk.aboutWorld || talk.page == library.world.id
    }

    /// Deletes one of the world's conversations (what was filed from it stays in the pages).
    func deleteWorldConversation(_ id: UUID, in library: Library) {
        library.conversationsDirectory.flatMap { try? ConversationStore(directory: $0) }?.delete(id)
        if conversation.page == id { conversation = Conversation(page: UUID(), aboutWorld: true) }
        if library.lastWorldConversation == id { library.lastWorldConversation = nil }
        others.removeAll { $0.page == id }   // so it no longer holds Undo back
        loadWorldConversations(in: library)
    }

    /// Forgets this page's conversation and starts afresh.
    func startOver(page: WriterCore.Document, in library: Library) {
        store?.delete(page.id)
        conversation = Conversation(page: page.id, aboutWorld: conversation.aboutWorld)
        retracted = nil
        state = .idle
        askNow(about: page, in: library)
    }

    /// The author's answer, in their words; then the companion's reply.
    func answer(_ text: String, page: WriterCore.Document, in library: Library) {
        conversation.answer(text)
        // The page as they sent it: filing, after the reply, changes only what's still so.
        if let i = conversation.turns.indices.last, let now = library.pages.first(where: { $0.id == page.id }) {
            conversation.turns[i].seen = now.values
            conversation.turns[i].seenTitle = now.title
        }
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
        guard conversation.waiting == nil, conversation.page == page.id, !needsDownload else { return }
        // The world's conversation waits for the author to begin (Kevin, 2026-11-24: "no need
        // for it to think before prompted"); a page's begins with the companion.
        guard !conversation.aboutWorld || !conversation.turns.isEmpty else { return }
        if let reason = await model.unavailableReason { state = .unavailable(reason); return }
        state = .thinking
        // The reply as it's written is this ask's until a newer one takes over: an ask
        // dropped for another (asking again, another page) leaves the newer one's alone.
        asks += 1
        let ask = asks
        (writing, reasoning, reading) = (nil, nil, nil)
        defer { if asks == ask { (writing, reasoning, reading) = (nil, nil, nil) } }
        await filing?.value
        // Dropped while filing finished (another page opened, or asked again): whoever
        // dropped it owns the conversation and the reply taken back now.
        guard !Task.isCancelled else { return }
        let page = library.pages.first { $0.id == page.id } ?? page   // as it is now, not when it opened
        let others = library.pages.filter { $0.id != page.id }
        let earlier = (store?.all() ?? []).filter { $0.page != page.id }.map { talk in
            var talk = talk
            talk.aboutWorld = Self.isAboutWorld(talk, in: library)   // memory words it as such
            return (page: talk.aboutWorld ? "" : others.first { $0.id == talk.page }?.heading ?? "", conversation: talk)
        }
        let isWorld = conversation.aboutWorld   // a conversation about the whole world: no page open
        var reply = Reasoned(reply: "")
        do {
            // Unusual text takes more of the model's context than its length
            // suggests: a prompt that doesn't fit is rebuilt with less background.
            for room in [1, 2, 4] {
                let prompt: CompanionPrompt
                if plain {
                    prompt = CompanionPrompt.plain(conversation, maxTurnCharacters: 6000 / room)
                } else if isWorld {
                    prompt = CompanionPrompt(world: library.world.name, pages: others.map { library.companionPage($0, fields: true) },
                                             earlier: earlier, conversation: conversation,
                                             maxCharacters: 6000 / room, maxTurnCharacters: 6000 / room)
                } else {
                    prompt = CompanionPrompt(page: library.companionPage(page, open: true),
                                             others: others.map { library.companionPage($0) },
                                             earlier: earlier, conversation: conversation,
                                             maxCharacters: 6000 / room, maxTurnCharacters: 6000 / room)
                }
                do {
                    for try await partial in model.stream(prompt, thinking: thinks) {
                        guard !Task.isCancelled else { break }
                        reply = partial.reply
                        self.reasoning = reply.reasoning
                        self.writing = reply.reply
                        self.reading = partial.reading
                    }
                    break
                } catch is PromptTooLong where room < 4 {
                    continue
                }
            }
        } catch {
            Self.log.error("Model failed: \(String(describing: error), privacy: .public)")
            trialLog("ERROR \(page.title): \(String(describing: error))")   // TRIAL
            if !Task.isCancelled { restoreRetracted() }
            state = error is URLError ? .downloadPaused : .failed
            if !model.isInstalled { offerDownload() }   // its files failed their check and were removed
            return
        }
        guard !Task.isCancelled else { return }   // superseded: leave state to whoever dropped it
        guard conversation.page == page.id else { state = .idle; return }
        trialLog("REPLY\(plain ? " (plain)" : "") \(page.title): \(reply.reply)")   // TRIAL
        guard !reply.reply.isEmpty else { restoreRetracted(); state = .failed; return }   // ran out of room while thinking
        if modelVersion == nil { modelVersion = model.version }   // just downloaded
        conversation.ask(reply.reply, after: retracted)
        retracted = nil
        if !reply.reasoning.isEmpty { thoughts[reply.reply] = reply.reasoning }
        save()
        state = .idle
        // Replied: now what the author said, filed (after, so the reply never waits for it).
        if let answered = conversation.turns.dropLast().last {
            file(answered, page: page.id, aboutWorld: conversation.aboutWorld, in: library)
        }
    }

    /// Files what the author said in `turn` of `page`'s conversation, unless something already was.
    private func file(_ turn: Conversation.Turn, page: UUID, aboutWorld: Bool, in library: Library) {
        guard turn.needsFiling, let message = turn.answer, Filer.states(message) else { return }
        let previous = filing
        let world = store?.directory   // the world it was said in
        filing = Task {
            await previous?.value
            // Still the open world (the author may have switched worlds since).
            guard world == library.conversationsDirectory else { return }
            // A world conversation has no page of its own; it files into the pages it names.
            guard let doc = aboutWorld ? library.worldSubject(page) : library.pages.first(where: { $0.id == page }) else { return }
            let filings: Filings
            do {
                filings = try await model.file(library.filingPrompt(for: doc, aboutWorld: aboutWorld, asked: turn.question,
                                                                    message: message))
            } catch {
                Self.log.error("Filing failed: \(String(describing: error), privacy: .public)")
                trialLog("FILING ERROR: \(String(describing: error))")   // TRIAL
                return
            }
            // Gone meanwhile (a new conversation, another world): nothing to file into.
            let there = conversation.page == page ? conversation.turns.contains { $0.id == turn.id }
                                                  : (try? store?.load(page))?.turns.contains { $0.id == turn.id } == true
            guard there, world == library.conversationsDirectory,
                  aboutWorld || library.pages.contains(where: { $0.id == page }) else { return }
            // Kept even when empty: Try Again reads the message again only if nothing came of it.
            let sent = turn.seen.map { (values: $0, title: turn.seenTitle ?? "") }
            setFiled(library.file(filings, message: message, on: page, again: turn.filed, sent: sent), turn: turn.id, page: page)
        }
    }

    private func setFiled(_ record: FilingRecord, turn: UUID, page: UUID) {
        if conversation.page == page, let i = conversation.turns.firstIndex(where: { $0.id == turn }) {
            conversation.turns[i].filed = record
            save()
        } else if var talk = try? store?.load(page), let i = talk.turns.firstIndex(where: { $0.id == turn }) {
            talk.turns[i].filed = record   // the author has moved on to another page
            try? store?.save(talk)
            others.removeAll { $0.page == talk.page }   // so Undo here sees it
            others.append(talk)
        }
    }

    /// Takes back one thing filed from `turn` (what the author changed since stays), unless
    /// a later message changed it: that one is undone first.
    func undoFiling(_ action: FilingRecord.Entry, from turn: UUID, in library: Library) {
        guard !conversation.changedLater(action, in: turn, elsewhere: others),   // newest first (Kevin, 2026-11-24)
              var record = conversation.turns.first(where: { $0.id == turn })?.filed else { return }
        let records = (conversation.turns.filter { $0.id != turn } + others.flatMap(\.turns)).compactMap(\.filed)
        library.undo(action, of: &record, kept: { [store] id in store?.hasTalk(id) == true },
                     others: records)
        setFiled(record, turn: turn, page: conversation.page)   // kept when all undone, so it isn't filed again
    }

    /// What undoing `action` takes back with it, newest first, itself last (nil: built on
    /// from another conversation, to be undone there).
    func undoChain(_ action: FilingRecord.Entry, from turn: UUID) -> [Conversation.Filed]? {
        conversation.undoChain(action, in: turn, elsewhere: others)
    }

    /// What going back to before `turn`'s answer takes back, newest first (nil: built on
    /// from another conversation, to be undone there).
    func rewindChain(to turn: UUID) -> [Conversation.Filed]? {
        conversation.rewind(to: turn, elsewhere: others)
    }

    /// Takes back `chain` (an `undoChain` or `rewindChain`), newest first.
    func undo(_ chain: [Conversation.Filed], in library: Library) {
        for filed in chain { undoFiling(filed.action, from: filed.turn, in: library) }
    }

    /// Asking again failed or was dropped: the reply it would have replaced comes back.
    private func restoreRetracted() {
        guard let old = retracted else { return }   // cleared when another page opens
        retracted = nil
        if conversation.waiting == nil { conversation.turns.append(old) }
    }

    /// Saves the conversation, with a reply being tried again still in it until the new
    /// one comes: if the app closes or the page changes meanwhile, it isn't lost.
    private func save() {
        var talk = conversation
        if let retracted, talk.waiting == nil { talk.turns.append(retracted) }
        guard !(talk.aboutWorld && talk.turns.isEmpty) else { return }   // a world conversation exists once something's said
        try? store?.save(talk)
        if talk.aboutWorld {
            // Newest first, as Messages keeps its list: the one just added to goes to the top,
            // with its title and time as they are now (unfolded the list stays beside it).
            worldConversations.removeAll { $0.page == talk.page }
            worldConversations.insert(talk, at: 0)
        }
    }
}

// TRIAL: every reply, and the model's speed and memory, pulled off the phone
// to see how it does there.
func trialLog(_ line: String) {
    let url = URL.documentsDirectory.appendingPathComponent("candidates.log")
    let data = Data((line.replacingOccurrences(of: "\n", with: " ") + "\n").utf8)
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() } else { try? data.write(to: url) }
}
