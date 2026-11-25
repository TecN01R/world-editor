#if DEBUG && canImport(TurboFieldfare)
import Foundation
import Guardrails
import Metal
import Network
import os
import TurboFieldfare
import TurboFieldfareRepackCore
import UIKit

/// TRIAL, debug builds only (Kevin, 2026-11-25: "didn't we want to test the 26B with the newer
/// much higher memory limit?"): Google's Gemma 4 26B-A4B (Apache-2.0) on TurboFieldfare (Swift
/// and Metal, Apache-2.0), the companion's model until Nemotron, chosen in the companion's menu
/// to compare the two on the phone. The model is 14.3 GB, more than the phone's memory, but only
/// about 4B of its parameters work on each token: TurboFieldfare keeps the 1.35 GB every token
/// uses in memory and reads the few experts each token picks from storage, keeping the ones it
/// read in memory too (16 a layer under the default memory limit; 32 now there's room). It
/// replies as Nemotron does (`replyWithTools`: thinking capped, search_pages, look_up), in
/// Google's own chat format (`GemmaChat.Template.gemma4`). Its files are kept apart from
/// Nemotron's, which it leaves alone. Not on the simulator, which TurboFieldfare isn't built for.
final class TurboModel: CompanionModel, @unchecked Sendable {
    static let name = "Gemma 4 26B"

    /// Its own folder in Application Support (which iOS never clears), out of iCloud backups and
    /// out of Nemotron's (which removes anything else in its own): the installer keeps its
    /// download in progress, lock and checkpoint beside it.
    private static let folder = URL.applicationSupportDirectory.appending(path: "Trial Models", directoryHint: .isDirectory)
    private static let directory = folder.appending(path: "gemma4.gturbo", directoryHint: .isDirectory)
    /// Written last, when everything else is in place and checked.
    private static var manifest: URL { directory.appending(path: "manifest.json") }

    /// The download's bytes so far and in all, while it runs; nil when it ends.
    private let onProgress: @Sendable (Download?) -> Void
    private let engine: Engine
    private let memoryWarning: NSObjectProtocol

    init(onProgress: @escaping @Sendable (Download?) -> Void) {
        self.onProgress = onProgress
        let engine = Engine()
        self.engine = engine
        // Near the app's memory limit, iOS would close it: the model's memory is given back
        // between replies, and the next reply loads it again.
        memoryWarning = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                               object: nil, queue: nil) { _ in engine.unloadIfIdle() }
    }

    deinit { NotificationCenter.default.removeObserver(memoryWarning) }

    var unavailableReason: String? { get async { nil } }
    var canSearch: Bool { true }

    /// Installed and, as far as anyone has looked, whole: files that fail their check
    /// when it loads are removed (`load`), so the download is offered again.
    var isInstalled: Bool { FileManager.default.fileExists(atPath: Self.manifest.path) }

    func downloadSize() async -> Int64? { Int64(SupportedModelSource.approximateDownloadBytes) }

    var version: String? {
        guard let installed = (try? FileManager.default.attributesOfItem(atPath: Self.manifest.path))?[.creationDate] as? Date
        else { return nil }
        return "Downloaded \(installed.formatted(date: .abbreviated, time: .omitted))"
    }

    func prepare() async throws {
        guard !isInstalled else { return }
        try await install()
        // Ended without the model (it shouldn't): shown as a download to resume.
        guard isInstalled else { throw URLError(.networkConnectionLost) }
    }

    // MARK: - Replies

    /// Gemma's recommended sampling (its model card): temperature 1, top-p 0.95, top-k 64, no
    /// repetition penalty, and a new seed each reply.
    private static let replying = GenerationConfig(maxNewTokens: 1500, temperature: 1, topK: 64, topP: 0.95, repetitionPenalty: 1)

    /// A reply with its tools (`replyWithTools`), each pass of the model on TurboFieldfare.
    func stream(_ prompt: CompanionPrompt, tools: ReplyTools, thinking: Bool) -> AsyncThrowingStream<ReplySoFar, Error> {
        streaming { continuation in
            try await replyWithTools(prompt, tools: tools, thinking: thinking, template: .gemma4, model: Self.name,
                                     state: Self.state, to: continuation) { text, _, show in
                let pass = Pass()
                let run = try await Self.again(pass) {
                    var config = Self.replying
                    config.maxNewTokens -= pass.tokens.count
                    // Its thought capped as Nemotron's is, so the two compare.
                    return try await self.engine.generate(text, written: pass.tokens, config: config,
                                                          budget: thinking ? LlamaModel.thinkingBudget : nil,
                                                          room: thinking ? 1000 : 300) { event in
                        switch event {
                        case .reading(let done, let total):
                            show(pass.output, Double(done) / Double(max(total, 1)))
                        case .token(let token, let piece):
                            pass.add(token, piece)
                            show(pass.output, nil)
                        }
                    }
                }
                return PassDone(output: pass.output, summary: run.summary, resumed: pass.resumed)
            }
        }
    }

    /// Reads what the message states: the model writes it as JSON, as the prompt's example
    /// shows, greedily (its most likely reading) and without thinking.
    func file(_ prompt: FilingPrompt) async throws -> Filings {
        let text = GemmaChat.prompt(system: prompt.system, turns: [.init(speaker: .author, text: prompt.message)],
                                    tools: [], thinking: false, template: .gemma4)
        let began = ContinuousClock.now
        let pass = Pass()
        let run = try await Self.again(pass, startOver: true) {
            try await engine.generate(text, written: [], config: GenerationConfig(maxNewTokens: 600, temperature: 0),
                                      budget: nil, room: 300) {
                if case .token(let token, let piece) = $0 { pass.add(token, piece) }
            }
        }
        let output = pass.output
        let filings = Filings.parse(output.said)
        trialLog("FILING \(Self.name) took \(ContinuousClock.now - began) (\(run.summary)): "
                 + "\(filings.facts.count) facts, \(filings.pages.count) pages; output \(output.said)")   // TRIAL
        return filings
    }

    /// Runs `job` (a pass of the model) again if leaving the app ended it: the engine waits
    /// for the author to come back first. A reply goes on from what it had written (kept in
    /// `pass`, and on screen); filing (`startOver`) begins again.
    private static func again(_ pass: Pass, startOver: Bool = false, _ job: () async throws -> Run) async throws -> Run {
        while true {
            do {
                return try await job()
            } catch is Interrupted {
                try Task.checkCancellation()
                if startOver { pass.clear() } else if !pass.tokens.isEmpty { pass.resumed += 1 }
            }
        }
    }

    // MARK: - Installing

    /// Downloads the model from Hugging Face (one checked revision, 14.6 GB) and repacks
    /// it on the phone as TurboFieldfare reads it, checking each file. 14.6 GB is for
    /// Wi-Fi: on cellular, a hotspot or Wi-Fi in Low Data Mode it waits, saying why, and
    /// goes on from where it was once it's back on Wi-Fi. It stops only when the
    /// connection keeps failing (Download Paused, to resume from where it got to), or
    /// when there isn't room for it (the download offered again, with how much is needed).
    private func install() async throws {
        defer { onProgress(nil) }
        do {
            var folder = Self.folder
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            let paths = try RemoteInstallPaths(outputDirectory: Self.directory.path)
            // What an earlier try got to, which this one goes on from.
            let saved = (try? RemoteInstallCheckpoint.load(from: paths.checkpointFile))?.completedRanges ?? []
            let progress = InstallProgress(report: onProgress, partial: paths.partialDirectory,
                                           resumed: Int64(saved.reduce(0) { $0 + $1.sourceBytes }))
            progress.waiting("Starting…")
            try Self.checkSpace(have: saved.reduce(0) { $0 + $1.destinationBytes })
            var failures = 0
            while true {
                try await Self.wifi(progress)
                do {
                    try await Self.repackOnWiFi(progress)
                    return
                } catch is LeftWiFi {
                    continue
                } catch let error where RemoteRetryPolicy.isRetryable(error) {
                    // The connection, or Hugging Face, still failing after the installer's
                    // own tries: again in a minute, up to three times without getting further.
                    failures = progress.downloaded ? 1 : failures + 1
                    guard failures < 3 else { throw error }
                    progress.waiting("Trying again in a minute…")
                    try await Task.sleep(for: .seconds(60))
                }
            }
        } catch {
            throw Self.shown(error)
        }
    }

    /// Runs the installer while the phone stays on Wi-Fi: moving to a metered network
    /// ends it (`LeftWiFi`), to go on once back. A connection that drops is the
    /// installer's to wait out (it retries, and waits for a connection to come back).
    private static func repackOnWiFi(_ progress: InstallProgress) async throws {
        progress.newRun()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await repack { progress.update($0) } }
            group.addTask {
                for await path in network() where !progress.downloadDone {   // checking the files needs no network
                    if path.status != .satisfied {
                        progress.waiting("Waiting for a connection…")
                    } else if !unmetered(path) {
                        throw LeftWiFi()
                    }
                }
                throw CancellationError()   // the stream ends only when this is cancelled
            }
            // The installer done, or the watcher throwing; never the watcher just ending,
            // which would pass for an install that finished.
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private static func repack(progress: @escaping @Sendable (ModelInstallProgress) -> Void) async throws {
        func run(resume: Bool) async throws {
            let options = SupportedModelSource.installOptions(outputDirectory: directory, overwrite: true, token: nil, resume: resume)
            _ = try await RemoteStreamingRepacker(options: options).run(progress: progress)
        }
        let checkpoint = try RemoteInstallPaths(outputDirectory: directory.path).checkpointFile
        do {
            try await run(resume: FileManager.default.fileExists(atPath: checkpoint))
        } catch RepackError.installStateIncompatible, RepackError.installStateCorrupt {
            // Half of an install, or one of another revision: it starts again.
            try? RemoteStreamingRepacker.discardPartial(outputDirectory: directory.path)
            try await run(resume: false)
        }
    }

    /// Waits for Wi-Fi, saying what it's waiting for.
    private static func wifi(_ progress: InstallProgress) async throws {
        for await path in network() {
            if unmetered(path) { break }
            let lowData = path.status == .satisfied && path.usesInterfaceType(.wifi) && path.isConstrained && !path.isExpensive
            progress.waiting(lowData ? "Low Data Mode is on for this Wi-Fi. Turn it off in Settings to download."
                                     : "Waiting for Wi-Fi…")
        }
        try Task.checkCancellation()
    }

    /// The network as it is and as it changes, until the stream is dropped.
    private static func network() -> AsyncStream<NWPath> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield($0) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "com.tecn01r.worldeditor.companion-network"))
        }
    }

    /// Connected, and not over cellular, a hotspot or Low Data Mode.
    private static func unmetered(_ path: NWPath) -> Bool {
        path.status == .satisfied && !path.isExpensive && !path.isConstrained
    }

    /// Room for the install, by what iOS counts as free for something the author asked
    /// for (space it can clear included): the model, the installer's reserve and the part
    /// downloading, less what's already here from an earlier try. The installer checks
    /// again by what's free now (`shown`).
    private static func checkSpace(have: UInt64) throws {
        let needed = Int64(SupportedModelSource.installedBytes + SupportedModelSource.reserveBytes)
            + Int64(RemoteChunkPolicy.defaultBytes) - Int64(have)
        let free = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        if let free, free < needed { throw space(needed: needed, free: free) }
    }

    private static func space(needed: Int64, free: Int64) -> DownloadBlocked {
        DownloadBlocked(reason: "It needs \(needed.formatted(.byteCount(style: .file))) of free space, and "
            + "\(max(free, 0).formatted(.byteCount(style: .file))) is free. Free up space in Settings › General › iPhone Storage.")
    }

    /// How the companion shows an install that ended: a dropped connection, Hugging Face
    /// busy for now, or the install stopped, as a download to resume (Download Paused)
    /// rather than one to offer again; too little space, as the offer with how much it needs.
    private static func shown(_ error: Error) -> Error {
        if error is URLError || error is CancellationError { return URLError(.networkConnectionLost) }
        guard let failure = error as? RepackError else { return error }
        switch failure {
        case .remoteBodyTruncated:
            return URLError(.networkConnectionLost)
        case .remoteHTTPStatus(url: _, status: let status), .remoteHTTPResponse(url: _, status: let status, retryAfter: _):
            return status == 408 || status == 429 || status >= 500 ? URLError(.networkConnectionLost) : error
        case .diskSpaceInsufficient(path: _, required: let needed, available: let free):
            return space(needed: Int64(needed), free: Int64(free))
        default:
            return error
        }
    }

    // MARK: - Loading

    /// Loads the installed model. Files that fail their check are removed, so the
    /// companion offers the download again rather than failing every reply (and
    /// reading all 14.3 GB again for each, when the whole model is checked).
    fileprivate static func load() async throws -> Loaded {
        do {
            return try await loadChecked()
        } catch let error where isDamaged(error) {
            trialLog("LOAD failed its check, removed to download again: \(error)")   // TRIAL
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// The installed files fail their check, or aren't a model this TurboFieldfare reads:
    /// only downloading it again helps.
    private static func isDamaged(_ error: Error) -> Bool {
        switch error {
        case ModelError.missingFile, ModelError.checksumMismatch, ModelError.tensorSizeMismatch, ModelError.tensorNotFound,
             ModelError.indexCorrupt, ModelError.partialInstall, ModelError.notAGTurboDirectory, ModelError.unsupportedVersion,
             ModelError.archMismatch, ModelError.unknownFlag, ModelError.trustedReceiptInvalid,
             RepackError.configurationInvalid:   // the whole model, checked again, found wrong
            return true
        default:
            return false
        }
    }

    /// Loads the installed model, sized to the memory iOS lets the app have, and logs what
    /// the phone offers it (TRIAL).
    private static func loadChecked() async throws -> Loaded {
        let clock = ContinuousClock()
        let began = clock.now
        let before = os_proc_available_memory()
        // The experts it read kept in memory, a layer's worth each: 16 (about 1.5 GB; about
        // 2.2 GB in all as it wrote, under the default limit's 3.4 GB), or more where there's
        // room, for fewer reads from storage: 32 on the higher limit (about 5.8 GB), 1.65 GB
        // more for a fifth more of the experts each token picks found in memory (TurboFieldfare's
        // CACHE-03), 24 between. TurboFieldfare takes no more than 32.
        let slots = switch before {
        case 5_000_000_000...: 32
        case 4_200_000_000...: 24
        default: 16
        }
        let runtime = RuntimeConfiguration(expertCacheSlots: slots, prefillChunkTokens: 256, forceLogitsHead: true,
                                           earlyExpertRead: .router)
        // The tokenizer the installer put beside the model: never fetched from the Hub.
        guard let words = GFTokenizer.tokenizerFolder(forModelDirectory: directory) else {
            throw ModelError.missingFile(name: "tokenizer/tokenizer.json")
        }
        let tokenizer = try await GFTokenizer.load(from: words)
        let tokenized = clock.now
        let context = try MetalContext()   // compiles its shaders, from source, on the phone
        let compiled = clock.now
        let (model, receipt) = try open(on: context.device, runtime: runtime)
        let opened = clock.now
        // Room for the companion's prompts (instructions, examples, background and
        // conversation: 2,000 to 4,500 tokens) and its reply.
        let maxContext = 8192
        let runner = try RealForwardRunner(model: model, context: context, maxContext: maxContext, runtimeConfiguration: runtime)
        let scratch = try RawCompletionScratch(context: context, vocab: model.config.vocabSize)
        trialLog("LOAD \(name): memory left \(gigabytes(before)) before, \(gigabytes(os_proc_available_memory())) after; "
                 + "\(slots) experts a layer, context \(maxContext); tokenizer \(tokenized - began), shaders \(compiled - tokenized), "
                 + "model \(opened - compiled) (\(receipt)), runner \(clock.now - opened); in all \(clock.now - began)")   // TRIAL
        return Loaded(context: context, tokenizer: tokenizer, model: model, runner: runner, scratch: scratch,
                      prefill: runtime.prefillConfig, maxContext: maxContext)
    }

    /// Opens the model, trusting the check made once after install (its receipt) for
    /// the 12.9 GB of experts; the 1.35 GB every token uses is still checked each time.
    /// The receipt names the folder it checked, and reinstalling the app can move its
    /// folder: the same files, moved with it, keep their check. Otherwise the whole
    /// model is checked again (14.3 GB read) and a new receipt written.
    private static func open(on device: MTLDevice, runtime: RuntimeConfiguration) throws -> (Model, String) {
        func model() throws -> Model {
            try Model.load(directoryURL: directory, device: device, streamingMode: .pread(slotCount: runtime.expertCacheSlots),
                           expertCachePolicy: runtime.modelExpertCachePolicy, integrityPolicy: .sizeCheckTrustedReceipt)
        }
        do {
            return (try model(), "checked once")
        } catch ModelError.trustedReceiptInvalid(let detail) {
            trialLog("LOAD receipt: \(detail)")   // TRIAL
            if (try? moveReceipt()) == true, let moved = try? model() { return (moved, "receipt moved with the app") }
            _ = try VerifiedInstallTool.run(options: VerifyInstallOptions(inputGTurbo: directory.path))
            return (try model(), "checked again")
        }
    }

    /// Points the receipt at the folder the model is in now; false if it already does.
    private static func moveReceipt() throws -> Bool {
        let old = try VerifiedInstallReceiptReader.load(directoryURL: directory)
        let here = directory.standardizedFileURL.path
        guard old.modelDirectoryPath != here else { return false }
        let moved = VerifiedInstallReceipt(schemaVersion: old.schemaVersion, manifestSha256: old.manifestSha256,
                                           modelDirectoryPath: here, sourceRepoID: old.sourceRepoID,
                                           sourceRevision: old.sourceRevision, verificationTimestamp: old.verificationTimestamp,
                                           toolVersion: old.toolVersion, files: old.files)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(moved).write(to: directory.appending(path: VerifiedInstallReceiptReader.fileName), options: .atomic)
        return true
    }

    // MARK: - TRIAL: what the log says

    private static func gigabytes(_ bytes: some BinaryInteger) -> String { String(format: "%.2f GB", Double(bytes) / 1e9) }

    /// The memory left to the app, and how hot the phone is.
    private static var state: String {
        let heat = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
        return "memory left \(gigabytes(os_proc_available_memory())); heat \(heat)"
    }
}

/// The job couldn't be finished: the author left the app, and iOS gives a background
/// app no GPU. It's run again once they're back (`TurboModel.again`).
private struct Interrupted: Error {}

/// The phone moved from Wi-Fi to a metered network while the model downloaded.
private struct LeftWiFi: Error {}

/// A pass of the model: what it has written so far, as tokens and as text with its special
/// tokens written out, for `GemmaChat.read`. Written by one job at a time.
private final class Pass: @unchecked Sendable {
    private(set) var tokens: [Int32] = []
    private var text = ""
    /// How often it went on from what it had written after the author came back.
    var resumed = 0

    /// What `token` wrote, or (nil) text held back until it stopped.
    func add(_ token: Int32?, _ piece: String) {
        if let token { tokens.append(token) }
        text += piece
    }

    /// What it has written, read as Google's format: it opens its thought itself.
    var output: GemmaChat.Output { GemmaChat.read(text, thinking: false) }

    /// Starts over (filing, whose output isn't shown, begun again after the author left the app).
    func clear() {
        tokens = []
        text = ""
    }
}

/// What a pass of the model did, for the TRIAL log: each run of TurboFieldfare in it (more than
/// one when its thought's cap ended its thought, and it went on from there).
private struct Run {
    var runs: [RawDecodeResult] = []

    var summary: String {
        runs.map { run in
            let rate = run.decodeSeconds > 0 ? Double(run.newTokens) / run.decodeSeconds : 0
            return "prompt \(run.prefillTokens) tokens (\(run.cachedPromptTokens) already read; \(run.computedPrefillTokens) read in "
                + String(format: "%.1f s", run.prefillSeconds) + "), \(run.newTokens) written in "
                + String(format: "%.1f s (%.1f a second)", run.decodeSeconds, rate) + ", ended by \(run.reason)"
        }.joined(separator: ", then ")
    }
}

/// The model as loaded, and what its KV cache holds (the prompt and reply it last read
/// and wrote, as tokens). Used by one job at a time (`Engine`), on the model's thread.
private final class Loaded: @unchecked Sendable {
    let context: MetalContext
    let tokenizer: GFTokenizer
    let model: Model
    let runner: RealForwardRunner
    let scratch: RawCompletionScratch
    let prefill: PrefillRuntimeConfig
    let maxContext: Int
    var cached: [Int32] = []
    /// Its thought's opening (`<|channel>thought`), as tokens, for its cap.
    let thoughtStart: [Int32]
    /// Each token met so far, and its own text if it's special (empty if not).
    private var specials: [Int32: String] = [:]

    init(context: MetalContext, tokenizer: GFTokenizer, model: Model, runner: RealForwardRunner,
         scratch: RawCompletionScratch, prefill: PrefillRuntimeConfig, maxContext: Int) {
        self.context = context
        self.tokenizer = tokenizer
        self.model = model
        self.runner = runner
        self.scratch = scratch
        self.prefill = prefill
        self.maxContext = maxContext
        thoughtStart = tokenizer.encode("<|channel>thought", addBOS: false)
    }

    /// A new cap for its thought: the thought ends naturally at `<channel|>` or a call (`<|tool_call>`),
    /// and the cap forces `<channel|>`, as llama.cpp's server caps Nemotron's.
    func budget(_ tokens: Int) -> ThinkingBudget {
        ThinkingBudget(start: thoughtStart, ends: [[tokenizer.channelEndID], [tokenizer.toolCallStartID]],
                       forced: [tokenizer.channelEndID], budget: tokens)
    }

    /// What `token` wrote: TurboFieldfare's text for it (`delta`), and a special token's own
    /// (`<|tool_call>`, `<channel|>`), which its streaming leaves out.
    func piece(_ token: Int32, _ delta: String) -> String {
        let special = specials[token] ?? {
            let own = tokenizer.decode([token], skipSpecialTokens: false)
            let text = own == tokenizer.decode([token], skipSpecialTokens: true) ? "" : own
            specials[token] = text
            return text
        }()
        return delta + special
    }

    /// Where reading `ids` can start: after the beginning it shares with what the cache
    /// holds (a prompt that only adds to the last one reads only what's new), short of
    /// its last token, which is read again to reply from. Further back than the cache's
    /// end, only as far as its sliding window allows (280 tokens: a reply tried again);
    /// otherwise from the start.
    func start(for ids: [Int32]) -> RawCompletionStart {
        let common = min(zip(cached, ids).prefix { $0.0 == $0.1 }.count, ids.count - 1)
        if common <= 0 || runner.continuationPosition != cached.count { return .reset }
        if common < cached.count, (try? runner.rewind(to: common)) == nil { return .reset }
        return .resume(cachedPromptTokens: common)
    }
}

/// Runs the model: one job at a time, as the phone has one GPU and the model one KV cache.
private final class Engine: @unchecked Sendable {
    enum Event {
        case reading(done: Int, total: Int)
        /// What a token wrote, or (nil) text held back (part of a character) until it stopped.
        case token(Int32?, String)
    }

    private let turns = Turns()
    /// Only while holding a turn.
    private var loaded: Loaded?
    /// A memory warning came while a job held the model.
    private let warned = OSAllocatedUnfairLock(initialState: false)
    /// The model's own thread: loading the model, and waiting on the GPU token by token,
    /// block, which Swift's shared threads are not for.
    private static let thread = ModelThread()

    /// Runs `prompt` (in the chat format, from after `<bos>`) and what it has `written` of this
    /// pass so far, handing each event to `onEvent`, until it ends its turn, calls a tool or has
    /// written `config.maxNewTokens`. `budget`: its thought's cap, in tokens. Throws
    /// `PromptTooLong` when fewer than `room` tokens would be left for the output, and
    /// `Interrupted` when the author leaves the app meanwhile.
    func generate(_ prompt: String, written: [Int32], config: GenerationConfig, budget: Int?, room: Int,
                  onEvent: @escaping (Event) -> Void) async throws -> Run {
        // iOS gives a background app no GPU: a job asked for while the author is away
        // (filing as they leave, the first reply once the download finishes in the
        // background) waits for them, without holding the model.
        try await Self.foreground()
        await turns.wait()
        defer {
            let warning = warned.withLock { flag in
                defer { flag = false }
                return flag
            }
            if warning { unload(because: "memory warning during a job") }
            turns.next()
        }
        try Task.checkCancellation()
        // Leaving the app from here (loading included) ends the job at the next token, or
        // the next part of the prompt, before the GPU's work can fail mid-way.
        let away = OSAllocatedUnfairLock(initialState: (gone: false, job: Task<Run, Error>?.none))
        let observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                              object: nil, queue: nil) { _ in
            away.withLock { state in
                state.gone = true
                return state.job
            }?.cancel()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        if await MainActor.run(body: { UIApplication.shared.applicationState == .background }) {
            away.withLock { $0.gone = true }
        }
        return try await Self.awake {
            guard !away.withLock({ $0.gone }) else { throw Interrupted() }   // not even loading it in the background
            let model: Loaded
            if let loaded {
                model = loaded
            } else {
                // On the model's thread: loading blocks for seconds (the shaders compiled,
                // the 1.35 GB every token uses checked), minutes when the whole model is.
                model = try await Task(executorPreference: Self.thread) { try await TurboModel.load() }.value
                loaded = model
            }
            guard !away.withLock({ $0.gone }) else { throw Interrupted() }
            let job = Task(executorPreference: Self.thread) {
                try await Self.run(model, prompt: prompt, written: written, config: config, budget: budget, room: room,
                                   onEvent: onEvent)
            }
            if away.withLock({ state in state.job = job; return state.gone }) { job.cancel() }
            do {
                return try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
            } catch {
                model.cached = []   // what the cache holds is no longer known
                model.runner.reset()
                if away.withLock({ $0.gone }) { throw Interrupted() }
                throw error
            }
        }
    }

    /// The pass itself, on the model's thread. When its thought reaches its cap, TurboFieldfare
    /// is stopped there, and run again from what the cache holds with `<channel|>` added: it
    /// reads only those last two tokens, and writes on from there.
    private static func run(_ model: Loaded, prompt: String, written: [Int32], config: GenerationConfig, budget limit: Int?,
                            room: Int, onEvent: (Event) -> Void) async throws -> Run {
        var ids = [model.tokenizer.bosID] + model.tokenizer.encode(prompt, addBOS: false) + written
        let left = model.maxContext - ids.count
        guard left >= max(100, room - written.count) else { throw PromptTooLong() }
        var budget = limit.map(model.budget)
        for token in written { budget?.accept(token, completesCharacter: true) }
        var config = config
        config.maxNewTokens = min(config.maxNewTokens, left)
        var run = Run()
        while config.maxNewTokens > 0 {
            let result = try await runRawCompletion(producer: model.runner, tokenizer: model.tokenizer, promptIds: ids, config: config,
                                                    context: model.context, scratch: model.scratch, prefillConfig: model.prefill,
                                                    start: model.start(for: ids), shouldStop: { budget?.forcedToken != nil }) { event in
                switch event {
                case .prefill(let done, let total):
                    onEvent(.reading(done: done, total: total))
                case .token(_, let token, let delta):
                    let piece = model.piece(token, delta)
                    budget?.accept(token, completesCharacter: !piece.isEmpty)
                    onEvent(.token(token, piece))
                case .tail(let text):
                    onEvent(.token(nil, text))
                }
            }
            model.cached = result.kvBackedTokenIDs
            run.runs.append(result)
            guard result.reason == .cancelled, let forced = budget?.forcedToken else { break }
            budget?.accept(forced, completesCharacter: true)
            onEvent(.token(forced, "<channel|>"))
            ids = result.kvBackedTokenIDs + result.uncommittedBoundaryTokenIDs + [forced]
            config.maxNewTokens -= result.newTokens + 1
        }
        return run
    }

    /// Gives back the model's memory now, or once the job at work is done.
    func unloadIfIdle() {
        guard turns.take() else {
            warned.withLock { $0 = true }
            return
        }
        unload(because: "memory warning")
        turns.next()
    }

    /// Only while holding a turn.
    private func unload(because reason: String) {
        if loaded != nil { trialLog("UNLOAD \(TurboModel.name): \(reason)") }   // TRIAL
        loaded = nil
    }

    /// Returns once the app is in the foreground: at once, or when the author comes back.
    /// Looked at each second rather than told, as a notification could come between
    /// looking and waiting.
    @MainActor private static func foreground() async throws {
        while UIApplication.shared.applicationState == .background {
            try await Task.sleep(for: .seconds(1))
        }
        try Task.checkCancellation()
    }

    /// Runs `body` with the screen kept on: Auto-Lock would take the app to the background
    /// and end the job, and a reply on this model can outlast its minute.
    private static func awake<T>(_ body: () async throws -> T) async throws -> T {
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
        defer { Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = false } }
        return try await body()
    }
}

/// Hands the model to one job at a time, in the order they asked.
private final class Turns: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (busy: false, waiting: [CheckedContinuation<Void, Never>]()))

    func wait() async {
        await withCheckedContinuation { (turn: CheckedContinuation<Void, Never>) in
            let now = state.withLock { state in
                guard state.busy else { state.busy = true; return true }
                state.waiting.append(turn)
                return false
            }
            if now { turn.resume() }
        }
    }

    /// Takes the turn if no one has it.
    func take() -> Bool {
        state.withLock { state in
            guard !state.busy else { return false }
            state.busy = true
            return true
        }
    }

    func next() {
        let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard !state.waiting.isEmpty else { state.busy = false; return nil }
            return state.waiting.removeFirst()
        }
        next?.resume()
    }
}

/// A serial thread of the app's own, for work that blocks while the GPU runs.
private final class ModelThread: TaskExecutor {
    private let queue = DispatchQueue(label: "com.tecn01r.worldeditor.companion-model", qos: .userInitiated)

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        queue.async { job.runSynchronously(on: self.asUnownedTaskExecutor()) }
    }
}

/// The installer's progress as the companion shows a download: the bytes so far and
/// in all, in Foundation's words for a file download, then the check of each file
/// once all of it is here, which goes round the bar again; and whatever it waits
/// for meanwhile, with the bar where it was.
private final class InstallProgress: @unchecked Sendable {
    private struct State {
        /// What the companion shows now.
        var shown: Download
        /// When this run of the installer began downloading, and how much it has downloaded.
        var began: Date?
        var thisRun: Int64 = 0
        /// All of it is here and its files are being checked: the bytes checked before
        /// the file being checked, and that file's.
        var checking = false
        var checked: Int64 = 0
        var file: Int64 = 0
    }

    private let report: @Sendable (Download?) -> Void
    /// Where the files are while they're installed.
    private let partial: String
    private let state: OSAllocatedUnfairLock<State>

    /// `resumed`: the bytes an earlier try downloaded, which this one goes on from.
    init(report: @escaping @Sendable (Download?) -> Void, partial: String, resumed: Int64) {
        self.report = report
        self.partial = partial
        state = OSAllocatedUnfairLock(initialState: State(shown: Download(
            done: resumed, total: Int64(SupportedModelSource.approximateDownloadBytes), detail: "Starting…")))
    }

    /// A new run of the installer: its speed, and how far its check has got, are its own.
    func newRun() {
        state.withLock { state in
            state.began = nil
            state.thisRun = 0
            state.checking = false
            state.checked = 0
            state.file = 0
        }
    }

    /// This run has downloaded something.
    var downloaded: Bool { state.withLock { $0.thisRun > 0 } }

    /// Everything is downloaded: what's left (checking and finishing) needs no network.
    var downloadDone: Bool { state.withLock { $0.checking } }

    /// What it's waiting for, with the bar where it was.
    func waiting(_ detail: String) {
        let shown = state.withLock { state in
            state.shown.detail = detail
            return state.shown
        }
        report(shown)
    }

    func update(_ event: ModelInstallProgress) {
        let installed = Int64(SupportedModelSource.installedBytes)
        switch event {
        case .downloadingMetadata:
            // Going on from an earlier try: what's here is read and checked first.
            if state.withLock({ $0.shown.done > 0 }) { waiting("Checking what’s downloaded so far…") }
        case .copyingPayload(let reused, let thisRun, let total):
            // A file download, so Foundation words it the way Apple's apps do
            // ("1.5 GB of 14.6 GB (12 MB/sec) — About 20 minutes remaining").
            let progress = Progress(totalUnitCount: Int64(total))
            progress.kind = .file
            progress.fileOperationKind = .downloading
            progress.completedUnitCount = Int64(reused + thisRun)
            let began = state.withLock { state in
                let began = state.began ?? Date()
                state.began = began
                state.thisRun = Int64(thisRun)
                return began
            }
            // Speed since this run began, for the time left.
            let seconds = Date().timeIntervalSince(began)
            if seconds > 2 {
                let rate = Double(thisRun) / seconds
                progress.throughput = Int(rate)
                progress.estimatedTimeRemaining = rate > 0 ? Double(progress.totalUnitCount - progress.completedUnitCount) / rate : nil
            }
            show(Download(done: progress.completedUnitCount, total: progress.totalUnitCount,
                          detail: progress.localizedAdditionalDescription))
        case .hashingOutput(let file):
            let size = (try? FileManager.default.attributesOfItem(atPath: partial + "/" + file))?[.size] as? Int64 ?? 0
            let checked = state.withLock { state in
                state.checking = true
                state.checked += state.file
                state.file = size
                return state.checked
            }
            show(Download(done: min(checked, installed), total: installed,
                          detail: "Checking the download: \(checked.formatted(.byteCount(style: .file))) of "
                              + "\(installed.formatted(.byteCount(style: .file)))"))
        case .finalizing:
            show(Download(done: installed, total: installed, detail: "Finishing…"))
        case .planning, .checkingDisk, .reservingOutput:
            break
        }
    }

    private func show(_ download: Download) {
        state.withLock { $0.shown = download }
        report(download)
    }
}
#endif
