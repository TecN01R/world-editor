import Foundation
import Guardrails
import OSLog
import UIKit
import WriterCore

/// The companion: talks with the author about the open page like a friend
/// they think out loud with. What it says comes from the model alone, stock, with its
/// tools (`CompanionPrompt.plain`): nothing checks or filters a reply
/// afterwards (Kevin's ruling, 2026-11-23). It never writes into the page (docs/ai-charter.md);
/// after each reply, what the author said is filed into the world's
/// types, fields and pages, in their words, with Undo (`Filer`; Kevin's ruling,
/// 2026-11-23).
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
    /// shown so it doesn't look stuck (Kevin, 2026-11-24).
    private(set) var reading: Double?
    /// What it thought before each of its replies (by the reply, so each tried
    /// version keeps its own), for this session only: shown collapsed, never saved
    /// or sent back to the model (its makers' advice).
    private(set) var thoughts: [String: String] = [:]
    /// Its conversation is on screen (the world's, in `RootView`). Opening it prepares the
    /// open conversation's reply, if one is due (`prepareSoon`); leaving it files what they
    /// said that's still to be (`fileWaiting`), if a reply had stopped that.
    var isOpen = false {
        didSet {
            if isOpen, !oldValue { prepareSoon() }
            if !isOpen, oldValue { fileWaiting() }
        }
    }

    /// The model's first download, while it runs.
    private(set) var download: Download?
    /// Why the download couldn't go ahead (too little free space), shown with its offer.
    private(set) var downloadNote: String?

    /// When the model on the phone was downloaded, for the menu.
    private(set) var modelVersion: String?

    /// It can see the pictures the author attaches: what it needs for them is on the phone
    /// (Kevin, 2026-11-26: "do pictures"); until then, attaching one offers that download.
    private(set) var seesPictures = false
    /// That download, while it runs; it goes on beside the conversation, not over it.
    private(set) var picturesDownload: Download?
    /// Why it couldn't go ahead or stopped, shown where it ran.
    private(set) var picturesNote: String?
    /// How much it is (nil: the model can't see pictures at all).
    var picturesDownloadSize: Int64? { model.picturesDownloadSize }

    /// Replies think first, briefly, and there's no switch for it (Kevin, 2026-11-24:
    /// "remove the thinking switch"): the companion's model is made to think (NVIDIA runs
    /// it so). Its thought is capped at NVIDIA's setting (`LlamaModel.thinkingBudget`).
    private let thinks = true

    /// It may look up the real world on Wikipedia when it isn't sure (`WebLookup`; Kevin,
    /// 2026-11-25: "go for it with the web stuff"): on unless turned off in its menu. Only
    /// the words it looks up leave the phone, never a name from the author's pages.
    var looksUp = UserDefaults.standard.object(forKey: "companionLooksUp") as? Bool ?? true {
        didSet { UserDefaults.standard.set(looksUp, forKey: "companionLooksUp") }
    }

    /// The companion is the model stock, with its tools (Kevin, 2026-11-25: "I want you to only
    /// run models stock from now on and only put stock models on my phone, with tools of
    /// course"): `CompanionPrompt.plain`, only the conversation and which page is open, and the
    /// author's standing instructions (`Instructions`; Kevin: "keep the prompting but keep it
    /// blank and the user can fill in instructions over time and the model can write its own
    /// instructions based on what the user tells it to do"). Blank at first; the author edits
    /// them (`CompanionInstructions`) and the model adds to them (`add_instruction`). One set for
    /// every world, kept on the phone: they're about how it talks with the author.
    var instructions = UserDefaults.standard.string(forKey: "companionInstruction") {
        didSet { UserDefaults.standard.set(instructions, forKey: "companionInstruction") }
    }

    /// The reply Try Again took back, kept as a version of the next one, or put back if that fails.
    private var retracted: Conversation.Turn?
    /// The world's other conversations, as of opening this page: their filings can
    /// change this page too, so Undo, newest first, looks at them as well.
    private(set) var others: [Conversation] = []
    /// The world's conversations about the world as a whole, newest first, for their list.
    private(set) var worldConversations: [Conversation] = []

    // The one model the companion uses (Kevin: one model, no choosing, as when it
    // ships): Nemotron 3.5 Bolt, set in `init`, wherever llama.cpp is; Apple's
    // model elsewhere.
    #if canImport(llama)
    static let modelName = LlamaModel.name
    #else
    static let modelName = "Apple's on-device model"   // the simulator: llama.cpp's framework has no build for it
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
    /// The model's download, while it runs.
    private var downloading: Task<Void, Never>?
    /// Filing what the author said, while it's under way (`fileWaiting`); a reply stops it
    /// (`stopFiling`) and waits for it to stop (one GPU, one job at a time).
    private var filing: Task<Void, Never>?
    /// The message the model is reading now, to file it.
    private(set) var filingTurn: UUID?
    /// Messages whose filing failed in this session (the model's error, or their page gone):
    /// left for the next launch, so filing doesn't go round on one.
    private var skipped: Set<UUID> = []
    /// The message Try Again's reply answers, when its first reading found nothing: read once
    /// more (`Turn.needsFiling`; a weaker model had read "trireme" for "bireme").
    private var readAgain: UUID?
    /// How many messages of the world's other conversations were read since launch (`sweepLimit`).
    private var swept = 0
    /// TRIAL: the launch's `FILING BACKLOG` line is written.
    @ObservationIgnored private var countedBacklog = false
    /// The model has replied, read the conversation or filed since launch, so it's loaded.
    @ObservationIgnored private var modelWarm = false
    /// Debug builds' self-check failed on the model's own error, so it's left for the next launch.
    @ObservationIgnored private var selfCheckFailed = false
    private static let log = Logger(subsystem: "com.tecn01r.worldeditor", category: "companion")

    init() {
        #if canImport(llama)
        // The download's progress, in the order it comes (only the latest matters): one report
        // each in a task of its own could come out of order, and a late one after the end
        // started the Live Activity again.
        let (progress, report) = AsyncStream<Download?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        model = LlamaModel { report.yield($0) }
        Task { [weak self] in
            for await download in progress {
                self?.download = download
                BackgroundDownload.update(download)   // keeps going if the author leaves the app
            }
        }
        #endif
        #if DEBUG
        // A scene (Scenes/) has its script play the model; never on a phone.
        if let scene = LaunchScene.current { model = ScriptedModel(script: scene.script) { [weak self] in self?.download = $0 } }
        #endif
        // Cancelled from the download's Live Activity (or iOS ended it) while away: it stops
        // where it got to, and Download goes on from there.
        BackgroundDownload.onCancel = { [weak self] in self?.downloading?.cancel() }
        if !model.isInstalled { offerDownload() }
        seesPictures = model.seesPictures
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
        downloading = Task {
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

    /// The author asked for what it needs to see pictures: downloaded beside the conversation,
    /// over Wi-Fi, resuming where it stopped if tried again.
    func downloadPictures() {
        guard picturesDownload == nil, !seesPictures, let size = model.picturesDownloadSize else { return }
        picturesDownload = Download(done: 0, total: size, detail: "Starting…")
        picturesNote = nil
        Task {
            // Its progress, in the order it comes (as the model's own download reports it).
            let (progress, report) = AsyncStream<Download?>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let showing = Task {
                for await download in progress {
                    picturesDownload = download
                    BackgroundDownload.update(download)   // keeps going if the author leaves the app
                }
            }
            do {
                try await model.preparePictures { report.yield($0) }
            } catch let blocked as DownloadBlocked {
                picturesNote = blocked.reason
            } catch {
                Self.log.error("Pictures' download failed: \(String(describing: error), privacy: .public)")
                picturesNote = "The download stopped. Attach a picture to go on from where it got to."
            }
            report.finish()
            await showing.value
            picturesDownload = nil
            seesPictures = model.seesPictures
        }
    }

    /// Keeps a picture the author attached (JPEG `data`) with the world's conversations, and
    /// returns it as attached; nil if it couldn't be kept.
    func keepPicture(_ data: Data, named name: String) -> Conversation.Attached? {
        guard let file = try? store?.keepPicture(data, type: "jpg") else { return nil }
        return Conversation.Attached(name: name, picture: file)
    }

    /// Where the pictures attached in this world's conversations are.
    var pictures: URL? { store?.pictures }

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
        if !countedBacklog {
            // TRIAL: what the last launch left to be read (a reply stopped its filing, or the app closed first).
            countedBacklog = true
            let backlog = waiting(in: conversation).count + sweep().count
            if backlog > 0 { trialLog("FILING BACKLOG \(backlog)") }
        }
        prepareSoon(after: .seconds(2))   // settle: the author may be passing through
    }

    /// Prepares the open page's reply after `pause`, if one is due (a blank page too: it
    /// helps you start), or else has the model ready for the author's message and files what
    /// they've said (`settle`); only while the companion is open: a reply is seconds of the
    /// GPU's work, too much to spend on every page passed through with it closed. Not while
    /// the phone is hot or in Low Power Mode either: the author begins instead, and only
    /// what they've said already is filed.
    private func prepareSoon(after pause: Duration = .zero) {
        guard isOpen, download == nil, state == .idle, let opened else { return }
        guard !Self.sparing else { fileWaiting(); return }
        preparing?.cancel()
        preparing = Task {
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            if replyDue {
                await ask(about: opened.page, in: opened.library)
            } else {
                await settle(opened.page, in: opened.library)
            }
        }
    }

    /// The phone is hot or in Low Power Mode: the model isn't run for what the author didn't ask for.
    private static var sparing: Bool {
        let phone = ProcessInfo.processInfo
        return phone.thermalState == .serious || phone.thermalState == .critical || phone.isLowPowerModeEnabled
    }

    /// The author is back in the app with the conversation in front: as on opening it; and
    /// after a reply that failed, what they said is still filed.
    func returned() {
        if state == .failed { fileWaiting() } else { prepareSoon() }
    }

    /// The conversation is at rest, a reply just written or none due: what the author has said
    /// is filed (`fileWaiting`), so its line shows as soon as it can, and then the model reads
    /// the conversation up to here, ready for their next message (`warmUp`). On one cache
    /// filing reads its prompt over the conversation's, so `warmUp` waits for it and reads the
    /// conversation again; where filing has a cache of its own (`filesApart`) neither disturbs
    /// the other. A message sent meanwhile stops both.
    private func settle(_ page: WriterCore.Document, in library: Library) async {
        fileWaiting()
        await warmUp(page, in: library)
    }

    /// Whether the companion's turn is next: nothing it asked is waiting for the author, and
    /// the world's conversation waits for the author to begin (Kevin, 2026-11-24: "no need
    /// for it to think before prompted"); a page's begins with the companion.
    private var replyDue: Bool {
        conversation.waiting == nil && (!conversation.aboutWorld || !conversation.turns.isEmpty)
    }

    /// Nothing due from the companion: the model is loaded and reads the conversation so far,
    /// so its reply to the author's next message starts from their words. Loading on sending
    /// cost 2–3 s of most replies' first words (the Duo's log, 2026-11-26).
    private func warmUp(_ page: WriterCore.Document, in library: Library) async {
        guard !Self.sparing, model.isInstalled, !needsDownload, await model.unavailableReason == nil else { return }
        if !model.filesApart { await filing?.value }   // on one cache, read after filing has read its own prompt over it
        guard !Task.isCancelled, conversation.page == page.id else { return }
        let page = library.pages.first { $0.id == page.id } ?? page   // as it is now, not when it opened
        await model.warmUp(prompt(about: page, in: library), tools: tools(for: page, in: library), thinking: thinks)
        modelWarm = true
    }

    /// The reply's prompt: the conversation (`kept`: the most of it, in characters, that it keeps),
    /// the open page as it is now, and the author's instructions.
    private func prompt(about page: WriterCore.Document, in library: Library, kept: Int = .max) -> CompanionPrompt {
        let isWorld = conversation.aboutWorld   // a conversation about the whole world: no page open
        let open = isWorld ? nil : CompanionPrompt.Page(page, schema: library.schema) { id in
            library.pages.first { $0.id == id }?.heading
        }
        return CompanionPrompt.plain(conversation, page: open, world: isWorld ? library.world.name : nil,
                                     instructions: instructions, pictures: model.seesPictures ? pictures : nil,
                                     maxTurnCharacters: kept)
    }

    /// What the reply's tools reach: every page, with its type and fields, and what the author
    /// said in their other conversations (this one's words are in the prompt already).
    private func tools(for page: WriterCore.Document, in library: Library) -> ReplyTools {
        let talks = (store?.all() ?? []).filter { $0.page != page.id }
        let pageLookup = model.canSearch ? PageLookup(pages: library.pages, schema: library.schema, conversations: talks) : nil
        // A look-up never sends their names: their pages', and those they wrote, unless the
        // phone's dictionary knows the word (a real place's name).
        return ReplyTools(pages: pageLookup, lookingUp: looksUp && pageLookup != nil, listing: true,
                          instructing: model.canSearch,
                          documents: model.canSearch ? Documents.Lookup(conversation) : nil,
                          theirNames: WebLookup.theirNames(pages: pageLookup, said: conversation.turns.compactMap(\.answer),
                                                           known: Self.dictionary()))
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
        stopFiling()
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

    /// The author's answer, in their words, with any documents they `attached`; then the
    /// companion's reply.
    func answer(_ text: String, attached: [Conversation.Attached] = [], page: WriterCore.Document, in library: Library) {
        conversation.answer(text, attached: attached)
        // The page as they sent it: filing, after the reply, changes only what's still so.
        if let i = conversation.turns.indices.last, let now = library.pages.first(where: { $0.id == page.id }) {
            conversation.turns[i].seen = now.values
            conversation.turns[i].seenTitle = now.title
        }
        save()
        stopFiling()
        askNow(about: page, in: library)
    }

    /// Drops whatever was being prepared and asks now.
    private func askNow(about page: WriterCore.Document, in library: Library) {
        preparing?.cancel()
        preparing = Task { await ask(about: page, in: library) }
    }

    /// Asks the model for a reply about `page`, shown as it's written.
    private func ask(about page: WriterCore.Document, in library: Library) async {
        guard replyDue, conversation.page == page.id, !needsDownload else { return }
        if let reason = await model.unavailableReason { state = .unavailable(reason); return }
        seesPictures = model.seesPictures   // a damaged file is removed, and its download offered again
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
        let tools = tools(for: page, in: library)
        var reply = Reasoned(reply: "")
        do {
            // The whole conversation (Kevin, 2026-11-25: "you WILL lift the limits"); only one
            // that outgrows the model's context is read from a later point, newest kept.
            for kept in [Int.max, 24000, 12000] {
                let prompt = prompt(about: page, in: library, kept: kept)
                do {
                    for try await partial in model.stream(prompt, tools: tools, thinking: thinks) {
                        guard !Task.isCancelled else { break }
                        reply = partial.reply
                        self.reasoning = reply.reasoning
                        self.writing = reply.reply
                        self.reading = partial.reading
                    }
                    break
                } catch is PromptTooLong where kept > 12000 {
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
        trialLog("REPLY \(page.title): \(reply.reply)")   // TRIAL
        guard !reply.reply.isEmpty else { restoreRetracted(); state = .failed; return }   // ran out of room while thinking
        if modelVersion == nil { modelVersion = model.version }   // just downloaded
        conversation.ask(reply.reply, after: retracted, searches: reply.searches, lookups: reply.lookups,
                         instructions: reply.instructions)
        if !reply.instructions.isEmpty { instructions = Instructions.adding(reply.instructions, to: instructions) }
        retracted = nil
        if !reply.reasoning.isEmpty { thoughts[reply.reply] = reply.reasoning }
        save()
        state = .idle
        modelWarm = true
        // Try Again's reply: what the author said is read once more if nothing came of it the first time.
        if let answered = conversation.turns.dropLast().last, answered.filed?.filedNothing == true { readAgain = answered.id }
        // Replied: what the author said is filed now, after every reply (approved by Kevin,
        // 2026-11-27). It used to wait for two minutes of quiet (his call, 2026-11-24, when
        // filing cost the next reply the whole conversation read again), and whatever was still
        // waiting when the app closed was lost.
        await settle(page, in: library)
    }

    /// Whether a word is one of the language's, by the phone's own English dictionary.
    private static func dictionary() -> (String) -> Bool {
        let checker = UITextChecker()
        return { word in
            checker.rangeOfMisspelledWord(in: word, range: NSRange(location: 0, length: (word as NSString).length),
                                          startingAt: 0, wrap: false, language: "en_US").location == NSNotFound
        }
    }

    /// Files what the author has said that the model hasn't read yet (`Filer.pending`: read
    /// off the saved conversations, so nothing waits only in memory, where closing the app
    /// lost it): the open conversation's messages, oldest first, then the world's other
    /// conversations' (`sweep`). Each is looked for afresh, the one before having left its
    /// record. Run after every reply and whenever the conversation comes to rest (`settle`:
    /// on opening it, and on coming back to the app), and when the author leaves the
    /// conversation; a reply stops it (`stopFiling`), and the next of those goes on from
    /// wherever it had got to.
    private func fileWaiting() {
        guard filing == nil, model.isInstalled, !needsDownload, download == nil,
              state == .failed || (state == .idle && !replyDue), let library = opened?.library else { return }
        var due = nextToFile(in: library) != nil
        #if DEBUG
        due = due || selfCheckDue
        #endif
        guard due else { return }
        filing = Task {
            defer { filing = nil }
            // (A reply the companion began itself waits for the message being read, not for the rest.)
            while !Task.isCancelled, state != .thinking, let next = nextToFile(in: library) {
                guard await file(next.turn, of: next.talk, in: library) else { return }
            }
            #if DEBUG
            await selfCheck()
            #endif
        }
    }

    /// The author sent a message (or asked again): the reply goes first, filing after.
    private func stopFiling() {
        filing?.cancel()
    }

    /// The messages of `talk` still to be read, but for those whose filing failed this session.
    private func waiting(in talk: Conversation) -> [Conversation.Turn] {
        Filer.pending(in: talk).filter { !skipped.contains($0.id) }
    }

    /// The author's next message to read, with its conversation as it is now: the one Try
    /// Again's reply answers (`readAgain`), the open conversation's oldest, then the sweep's.
    private func nextToFile(in library: Library) -> (turn: Conversation.Turn, talk: Conversation)? {
        // Only while this world's conversations are still the ones open (the author may switch worlds).
        guard let store, store.directory == library.conversationsDirectory else { return nil }
        if let again = conversation.turns.first(where: { $0.id == readAgain }),
           again.needsFiling, again.answer.map(Filer.states) == true, !skipped.contains(again.id) {
            return (again, conversation)
        }
        if let turn = waiting(in: conversation).first { return (turn, conversation) }
        return sweep().first
    }

    /// The most messages of other conversations read in one launch, and how far back they go.
    private static let sweepLimit = 20
    private static let sweepReach: TimeInterval = 30 * 86_400

    /// The sweep: what is still to be read in the world's other conversations, as saved (one
    /// the author left while a reply held its filing up, or the app closed first), oldest
    /// message first. Not while the phone is hot or in Low Power Mode, at most `sweepLimit` in a
    /// launch, and only messages of the last 30 days: older ones that were never read (lost
    /// while what waited was kept only in memory, before 2026-11-27) are left alone, rather
    /// than bring words from months ago into the pages unasked.
    private func sweep() -> [(turn: Conversation.Turn, talk: Conversation)] {
        guard !Self.sparing else { return [] }
        let waiting = Filer.pending(across: others, since: Date.now.addingTimeInterval(-Self.sweepReach))
            .filter { !skipped.contains($0.turn.id) }
        return Array(waiting.prefix(max(0, Self.sweepLimit - swept)))
    }

    /// Files what the author said in `turn` of `talk`: the model reads it out (`filingPrompt`),
    /// what it read goes into the pages in their words (`Library.file`), and the record is kept
    /// on the turn whatever came of it, so it isn't read twice. False when stopped for a reply
    /// before it could.
    private func file(_ turn: Conversation.Turn, of talk: Conversation, in library: Library) async -> Bool {
        guard !Task.isCancelled else { return false }
        let page = talk.page, world = library.conversationsDirectory
        let aboutWorld = Self.isAboutWorld(talk, in: library), elsewhere = page != conversation.page
        if readAgain == turn.id { readAgain = nil }
        // Not tried again this session, whatever stops it short of a record (the model's error,
        // its page or conversation gone): only a reply stopping it, or its record, lifts this.
        skipped.insert(turn.id)
        // A world conversation has no page of its own; it files into the pages it names.
        guard let message = turn.answer,
              let doc = aboutWorld ? library.worldSubject(page) : library.pages.first(where: { $0.id == page }) else { return true }
        // TRIAL: which message, by its place and never its words.
        let place = (elsewhere ? "SWEEP conversation \(page.uuidString.prefix(8)), " : "")
            + "turn \((talk.turns.firstIndex { $0.id == turn.id } ?? 0) + 1) of \(talk.turns.count)"
        // Who they were last talking about, as the model is told and as its answer is then taken.
        let focus = aboutWorld ? Filer.focus(before: turn.id, in: talk, pages: library.pages) : []
        let prompt = library.filingPrompt(for: doc, aboutWorld: aboutWorld, asked: turn.question, message: message,
                                          focus: focus, saidBefore: Filer.said(before: turn.id, in: talk))
        let began = ContinuousClock.now
        filingTurn = turn.id
        defer { filingTurn = nil }
        let filings: Filings
        do {
            filings = try await model.file(prompt)
        } catch {
            if Task.isCancelled {
                skipped.remove(turn.id)   // stopped for a reply: read once that has come
                return false
            }
            if elsewhere { swept += 1 }
            Self.log.error("Filing failed: \(String(describing: error), privacy: .public)")
            trialLog("FILING ERROR \(place): \(String(describing: error))")   // TRIAL
            return true
        }
        if elsewhere { swept += 1 }
        modelWarm = true
        // Another world opened meanwhile: read when its own conversations are open again.
        guard world == library.conversationsDirectory else {
            skipped.remove(turn.id)
            return true
        }
        // Gone meanwhile (its conversation deleted, or its page): nothing to file into.
        guard let now = page == conversation.page ? conversation : others.first(where: { $0.page == page }),
              now.turns.contains(where: { $0.id == turn.id }),
              aboutWorld || library.pages.contains(where: { $0.id == page }) else { return true }
        // Read after something was filed from a later message (it waited through a launch or
        // two): it only adds.
        let late = Filer.isLate(turn.id, in: now, elsewhere: others + [conversation])
        let sent = turn.seen.map { (values: $0, title: turn.seenTitle ?? "") }
        // Its record is kept even when empty: it has been read. (The pages are on disk before it.)
        let record = library.file(filings, message: message, on: page, again: turn.filed, sent: sent, late: late, focus: focus)
        guard setFiled(record, turn: turn.id, page: page) else { return true }   // its conversation couldn't be saved
        skipped.remove(turn.id)
        trialLog("FILING \(place): \(ContinuousClock.now - began); \(Self.counts(record))" + (late ? "; read late, so it only added" : ""))   // TRIAL
        return true
    }

    /// TRIAL: what a filing did, in counts and never its words: pages made, types given, fields
    /// filled and corrected, pages renamed, and pages its sentences were placed on.
    private static func counts(_ record: FilingRecord) -> String {
        var counts: [(name: String, count: Int)] = [("made", 0), ("typed", 0), ("filled", 0), ("corrected", 0), ("renamed", 0), ("placed", 0)]
        for action in record.actions {
            switch action {
            case .created: counts[0].count += 1
            case .typed: counts[1].count += 1
            case .value: counts[2].count += 1
            case .replaced: counts[3].count += 1
            case .renamed: counts[4].count += 1
            case .placed, .described: counts[5].count += 1
            case .newType, .newField, .fieldAdded: break
            }
        }
        let done = counts.filter { $0.count > 0 }.map { "\($0.count) \($0.name)" }
        return done.isEmpty ? "nothing" : done.joined(separator: ", ")
    }

    /// Where filing has got to with what the author said in a turn of the open conversation.
    enum FilingStatus {
        /// Nothing to file, or nothing on its way: it stated nothing, or filing isn't under way.
        case none
        /// Filing is under way and will come to it.
        case waiting
        /// The model is reading it now.
        case reading
        /// Read, and something of it is in the pages.
        case filed
        /// Read, and nothing came of it (or all of it was undone).
        case nothing
    }

    func filingStatus(of turn: UUID) -> FilingStatus {
        if filingTurn == turn { return .reading }
        guard let turn = conversation.turns.first(where: { $0.id == turn }) else { return .none }
        if let record = turn.filed { return record.isEmpty ? .nothing : .filed }
        // Still to be read (as `Filer.pending` has it), and filing is on its way to it.
        return filing != nil && !skipped.contains(turn.id) && turn.answer.map(Filer.states) == true ? .waiting : .none
    }

    #if DEBUG
    /// Debug builds check that filing works with the model on this phone (`FilingSelfCheck`:
    /// five made-up exchanges filed into a small world of its own, never the author's pages):
    /// once for each build installed (by when its executable was made), and whenever a file
    /// named "selfcheck" is in the app's Documents. With the conversation open, the model
    /// loaded, nothing left to file and the phone neither hot nor in Low Power Mode; a reply
    /// stops it as it stops filing, and it starts over the next time. TRIAL: a line for each
    /// exchange, then how many of the five passed.
    private func selfCheck() async {
        guard selfCheckDue, isOpen, state == .idle, !Self.sparing, !Task.isCancelled else { return }
        do {
            let outcomes = try await FilingSelfCheck.run { [model] in try await model.file($0) }
            for outcome in outcomes {
                trialLog("SELF-CHECK \(outcome.letter) " + (outcome.passed ? "pass" : "FAIL: \(outcome.reason)"))
            }
            trialLog("SELF-CHECK \(outcomes.count { $0.passed })/\(outcomes.count)")
            UserDefaults.standard.set(Self.build, forKey: Self.selfCheckKey)
        } catch {
            if Task.isCancelled { return }   // stopped for a reply
            trialLog("SELF-CHECK stopped: \(String(describing: error))")
            selfCheckFailed = true
        }
        try? FileManager.default.removeItem(at: Self.selfCheckFile)
    }

    private var selfCheckDue: Bool {
        guard modelWarm, LaunchScene.current == nil else { return false }   // a scene's model plays a script
        return FileManager.default.fileExists(atPath: Self.selfCheckFile.path)
            || (!selfCheckFailed && UserDefaults.standard.double(forKey: Self.selfCheckKey) != Self.build)
    }

    private static let selfCheckKey = "filingSelfCheck"
    private static let selfCheckFile = URL.documentsDirectory.appendingPathComponent("selfcheck")
    /// When this build's executable was made: another for each install.
    private static let build = (try? Bundle.main.executableURL?.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
    #endif

    /// Keeps `record` on `turn` of `page`'s conversation, the open one or a saved one; false if it couldn't.
    @discardableResult private func setFiled(_ record: FilingRecord, turn: UUID, page: UUID) -> Bool {
        if conversation.page == page, let i = conversation.turns.firstIndex(where: { $0.id == turn }) {
            conversation.turns[i].filed = record
            save()
        } else if var talk = try? store?.load(page), let i = talk.turns.firstIndex(where: { $0.id == turn }) {
            talk.turns[i].filed = record   // the author has moved on to another page
            guard (try? store?.save(talk)) != nil else { return false }
            others.removeAll { $0.page == talk.page }   // so Undo here sees it
            others.append(talk)
        } else {
            return false
        }
        return true
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
            // with its title and time as they are now.
            worldConversations.removeAll { $0.page == talk.page }
            worldConversations.insert(talk, at: 0)
        }
    }
}

// TRIAL: every reply, and the model's speed and memory, pulled off the phone
// to see how it does there; each line with the time of day it was written.
func trialLog(_ line: String) {
    let url = URL.documentsDirectory.appendingPathComponent("candidates.log")
    let now = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: Date())
    let time = String(format: "%02ld:%02ld:%02ld.%03ld ", now.hour ?? 0, now.minute ?? 0, now.second ?? 0, (now.nanosecond ?? 0) / 1_000_000)
    let data = Data((time + line.replacingOccurrences(of: "\n", with: " ") + "\n").utf8)
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() } else { try? data.write(to: url) }
}
