#if canImport(TurboFieldfare)
import Foundation
import Guardrails
import Metal
import Network
import os
import TurboFieldfare
import TurboFieldfareRepackCore
import UIKit

/// The companion's model: Google's Gemma 4 26B-A4B (Apache-2.0) on TurboFieldfare
/// (Swift and Metal, Apache-2.0). The model is 14.3 GB, more than the phone's memory,
/// but only about 4B of its parameters work on each token: TurboFieldfare keeps the
/// 1.35 GB every token uses in memory and reads the few experts each token picks
/// from storage. The one model on the phone (Kevin, 2026-11-24: "when the work is
/// ready replace"): it replaced Gemma 4 E4B, whose files it removes once it runs.
/// Not on the simulator, which TurboFieldfare isn't built for: the companion uses
/// Apple's model there.
final class TurboModel: CompanionModel, @unchecked Sendable {
    static let name = "Gemma 4 26B"

    /// Its own folder in Application Support (which iOS never clears), out of iCloud
    /// backups: the installer keeps its download in progress, lock and checkpoint beside it.
    private static let folder = URL.applicationSupportDirectory.appending(path: "Models", directoryHint: .isDirectory)
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
        // Near the app's memory limit, iOS would close it: the model's memory (about
        // 3 GB) is given back between replies, and the next reply loads it again.
        memoryWarning = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                               object: nil, queue: nil) { _ in engine.unloadIfIdle() }
    }

    deinit { NotificationCenter.default.removeObserver(memoryWarning) }

    var unavailableReason: String? { get async { nil } }

    /// Installed and, as far as anyone has looked, whole: files that fail their check
    /// when it loads are removed (`load`), so the download is offered again.
    var isInstalled: Bool { FileManager.default.fileExists(atPath: Self.manifest.path) }

    func downloadSize() async -> Int64? { Int64(SupportedModelSource.approximateDownloadBytes) }

    var version: String? {
        guard let installed = (try? FileManager.default.attributesOfItem(atPath: Self.manifest.path))?[.creationDate] as? Date
        else { return nil }
        return "Downloaded \(installed.formatted(date: .abbreviated, time: .omitted))"
    }

    // Updates: none offered. The installer takes one checked revision of the model
    // (TurboFieldfare's pin), so a new one comes with a new TurboFieldfare in the app.

    func prepare() async throws {
        guard !isInstalled else { return }
        try await install()
        // Ended without the model (it shouldn't): shown as a download to resume.
        guard isInstalled else { throw URLError(.networkConnectionLost) }
    }

    // MARK: - Replies

    func stream(_ prompt: CompanionPrompt, thinking thinks: Bool) -> AsyncThrowingStream<ReplySoFar, Error> {
        streaming { continuation in
            let text = Self.chat(system: prompt.system, turns: prompt.turns.map { (author: $0.speaker == .author, text: $0.text) },
                                 thinking: thinks)
            // Gemma's recommended sampling (its model card): temperature 1, top-p 0.95,
            // top-k 64, no repetition penalty, and a new seed each reply, so Try Again
            // differs. Room for its reasoning as well as the reply (E4B's longest over the
            let config = GenerationConfig(maxNewTokens: 1500, temperature: 1, topK: 64, topP: 0.95, repetitionPenalty: 1)
            let room = thinks ? 1000 : 300
            let output = Output()
            let began = ContinuousClock.now
            let run: RawDecodeResult = try await Self.again {
                // Begun again after the author left the app (iOS gives an app in the
                // background no GPU): it goes on from what it had written, which stays on
                // screen, rather than starting over, which looked stuck (Kevin, 2026-11-24).
                // Its prompt is read again (the model's cache is dropped when a job ends
                // early), with what it had written as the start of its turn.
                var rest = config
                rest.maxNewTokens = max(1, config.maxNewTokens - output.tokens)
                if !output.raw.isEmpty { output.resumed += 1 }
                let written = Reasoned.gemma(output.raw)
                return try await self.engine.generate(text + output.raw, rest, room: max(100, room - output.tokens)) { event, tokenizer in
                    if case .prefill(let done, let total) = event {
                        continuation.yield(ReplySoFar(reply: written, reading: Double(done) / Double(max(total, 1))))
                        return
                    }
                    guard output.add(event, tokenizer) else { return }
                    let reply = Reasoned.gemma(output.raw)
                    if output.firstWords == nil, !reply.reply.isEmpty { output.firstWords = ContinuousClock.now - began }
                    continuation.yield(ReplySoFar(reply: reply))
                }
            }
            // TRIAL: speed on the phone. How much of the prompt it read (and how much it
            // had already), when its first words came, how fast it wrote, how often it
            // went on after the author came back, and what's left.
            let reply = Reasoned.gemma(output.raw)
            func count(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }
            trialLog("SPEED \(Self.name)\(thinks ? ", thinking" : ""): \(Self.reading(run)), "
                + "first words after \(output.firstWords ?? .zero) (\(count(reply.reasoning)) words of thinking), "
                + "whole reply (\(count(reply.reply)) words) in \(ContinuousClock.now - began), \(Self.writing(run)); "
                + (output.resumed > 0 ? "went on after the author came back \(output.resumed) times; " : "")
                + "\(Self.state); its output (\(output.raw.count) characters) began \(String(reflecting: String(output.raw.prefix(48))))")
        }
    }

    /// Reads what the message states: the model writes it as JSON, as the
    /// prompt's example shows, greedily (its most likely reading) and without
    func file(_ prompt: FilingPrompt) async throws -> Filings {
        let text = Self.chat(system: prompt.system, turns: [(true, prompt.message)], thinking: false)
        let output = Output()
        let began = ContinuousClock.now
        let run: RawDecodeResult = try await Self.again {
            output.clear()
            return try await engine.generate(text, GenerationConfig(maxNewTokens: 600, temperature: 0), room: 300) { event, tokenizer in
                _ = output.add(event, tokenizer)
            }
        }
        let filings = Filings.parse(output.raw)
        trialLog("FILING took \(ContinuousClock.now - began) (\(Self.reading(run)), \(Self.writing(run))): "
                 + "\(filings.facts.count) facts, \(filings.pages.count) pages; output \(output.raw)")   // TRIAL
        return filings
    }

    /// Runs `job` (a turn of the model) again if leaving the app ended it: the engine
    /// waits for the author to come back first, then a reply goes on from what it had
    /// written and filing starts over. So a reply, or the filing after one, isn't lost
    /// to a look at another app.
    private static func again<T>(_ job: () async throws -> T) async throws -> T {
        while true {
            do { return try await job() } catch is Interrupted { try Task.checkCancellation() }
        }
    }

    /// `system` and `turns` in Gemma 4's chat format (its chat template; TurboFieldfare's
    /// own rendering has no thinking), from after `<bos>`: the author's turns as the
    /// user's, the companion's earlier replies (never their reasoning, its makers'
    /// advice) as the model's, and the model's turn opened. To have it think first,
    /// `<|think|>` opens the system turn; otherwise its thought channel comes already
    /// closed, before its earlier replies too: as the model wrote them, so the prompt for
    /// a follow-up begins as its cache does and only the new messages are read. Words that
    /// read as its control tokens are defused (`Reasoned.gemmaPlain`).
    static func chat(system: String, turns: [(author: Bool, text: String)], thinking: Bool) -> String {
        func plain(_ text: String) -> String { Reasoned.gemmaPlain(text).trimmingCharacters(in: .whitespacesAndNewlines) }
        let thought = thinking ? "" : "<|channel>thought\n<channel|>"
        var text = ""
        if thinking || !system.isEmpty {
            text = "<|turn>system\n" + (thinking ? "<|think|>\n" : "") + plain(system) + "<turn|>\n"
        }
        for turn in turns {
            text += turn.author ? "<|turn>user\n" : ("<|turn>model\n" + thought)
            text += plain(turn.text) + "<turn|>\n"
        }
        return text + "<|turn>model\n" + thought
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

    /// Loads the installed model, sized to the memory iOS lets the app have, and
    /// logs what the phone offers it (TRIAL: the Duo's GPU and memory aren't known).
    private static func loadChecked() async throws -> Loaded {
        let clock = ContinuousClock()
        let began = clock.now
        let before = os_proc_available_memory()
        // A modest share of the app's memory: 16 experts a layer kept in memory (about
        // 1.5 GB), or 24 (about 2.25 GB, fewer reads from storage) where there's plenty.
        let slots = before >= 8_000_000_000 ? 24 : 16
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
        let device = context.device
        trialLog("LOAD \(name): \(device.name), Apple GPU family 10 \(device.supportsFamily(.apple10) ? "yes" : "no"), "
                 + "largest buffer \(gigabytes(device.maxBufferLength)), GPU working set \(gigabytes(device.recommendedMaxWorkingSetSize)); "
                 + "memory left \(gigabytes(before)) before, \(gigabytes(os_proc_available_memory())) after; "
                 + "\(slots) experts a layer, early expert reads \(runtime.earlyExpertRead.rawValue), context \(maxContext); tokenizer \(tokenized - began), shaders \(compiled - tokenized), "
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

    /// Frees what the models before it left on the phone, once it runs: Gemma 4 E4B
    /// (4.2 GB) and E2B (about 3 GB) in Hugging Face's cache, and which revision of
    /// each was in use. One model on the phone (Kevin, 2026-11-24).
    fileprivate static func removeRetired() {
        let cache = URL.cachesDirectory.appending(path: "huggingface/hub")
        for (repo, file) in [("unsloth--gemma-4-E4B-it-qat-GGUF", "gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf"),
                             ("unsloth--gemma-4-E2B-it-GGUF", "gemma-4-E2B-it-Q4_K_M.gguf")] {
            try? FileManager.default.removeItem(at: cache.appending(path: "models--" + repo))
            UserDefaults.standard.removeObject(forKey: "companionRevision." + file)
        }
    }

    // MARK: - TRIAL: what the log says

    private static func gigabytes(_ bytes: some BinaryInteger) -> String { String(format: "%.2f GB", Double(bytes) / 1e9) }

    /// How much of the prompt it read, and how fast.
    private static func reading(_ run: RawDecodeResult) -> String {
        "prompt \(run.prefillTokens) tokens (\(run.cachedPromptTokens) already read; \(run.computedPrefillTokens) read in "
            + String(format: "%.1f s", run.prefillSeconds) + ")"
    }

    /// How much it wrote, how fast, and why it stopped.
    private static func writing(_ run: RawDecodeResult) -> String {
        let rate = run.decodeSeconds > 0 ? Double(run.newTokens) / run.decodeSeconds : 0
        return "\(run.newTokens) tokens written in " + String(format: "%.1f s (%.1f a second)", run.decodeSeconds, rate)
            + ", ended by \(run.reason)"
    }

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

/// The model as loaded, and what its KV cache holds (the prompt and reply it last read
/// and wrote, as tokens). Used by one job at a time (`Engine`).
private final class Loaded: @unchecked Sendable {
    let context: MetalContext
    let tokenizer: GFTokenizer
    let model: Model
    let runner: RealForwardRunner
    let scratch: RawCompletionScratch
    let prefill: PrefillRuntimeConfig
    let maxContext: Int
    var cached: [Int32] = []

    init(context: MetalContext, tokenizer: GFTokenizer, model: Model, runner: RealForwardRunner,
         scratch: RawCompletionScratch, prefill: PrefillRuntimeConfig, maxContext: Int) {
        self.context = context
        self.tokenizer = tokenizer
        self.model = model
        self.runner = runner
        self.scratch = scratch
        self.prefill = prefill
        self.maxContext = maxContext
    }

    /// Where reading `ids` can start: after the beginning it shares with what the cache
    /// holds (a prompt that only adds to the last one reads only what's new), short of
    /// its last token, which is read again to reply from. Further back than the cache's
    /// end, only as far as its sliding window allows (280 tokens: a reply tried again);
    /// otherwise from the start.
    func start(for ids: [Int32]) -> RawCompletionStart {
        let common = min(zip(cached, ids).prefix { $0.0 == $0.1 }.count, ids.count - 1)
        let start: RawCompletionStart
        if common <= 0 || runner.continuationPosition != cached.count {
            start = .reset
        } else if common < cached.count, (try? runner.rewind(to: common)) == nil {
            start = .reset
        } else {
            start = .resume(cachedPromptTokens: common)
        }
        // TRIAL (Kevin, 2026-11-24: replies took 30 s, nearly all of it reading the prompt
        // again): how much of it the cache already held, and why it was read from the start.
        trialLog("CACHE \(ids.count) tokens, \(common) shared with the \(cached.count) cached, runner at "
                 + "\(runner.continuationPosition): \(start == .reset ? "read from the start" : "went on from the cache")")
        return start
    }
}

/// Runs the model: one job at a time, as the phone has one GPU and the model one KV cache.
private final class Engine: @unchecked Sendable {
    private let turns = Turns()
    /// Only while holding a turn.
    private var loaded: Loaded?
    /// A memory warning came while a job held the model.
    private let warned = OSAllocatedUnfairLock(initialState: false)
    /// The model's own thread: loading the model, and waiting on the GPU token by token,
    /// block, which Swift's shared threads are not for.
    private static let thread = ModelThread()

    /// Runs `prompt` (in the chat format, from after `<bos>`), handing each event to
    /// `onEvent`. Throws `PromptTooLong` when fewer than `room` tokens would be left
    /// for the output, and `Interrupted` when the author leaves the app meanwhile.
    func generate(_ prompt: String, _ config: GenerationConfig, room: Int,
                  onEvent: @escaping @Sendable (RawDecodeProgress, GFTokenizer) -> Void) async throws -> RawDecodeResult {
        // iOS gives a background app no GPU: a job asked for while the author is away
        // (filing as they leave, the first reply once the download finishes in the
        // background) waits for them, without holding the model (a memory warning can
        // still free it meanwhile).
        try await Self.foreground()
        await turns.wait()
        defer {
            // A memory warning came while it worked: its memory is given back now.
            let warning = warned.withLock { flag in
                let was = flag
                flag = false
                return was
            }
            if warning { unload(because: "memory warning during a job") }
            turns.next()
        }
        try Task.checkCancellation()
        // Leaving the app from here (loading included) ends the job at the next token, or
        // the next part of the prompt, before the GPU's work can fail mid-way.
        let away = OSAllocatedUnfairLock(initialState: (gone: false, job: Task<RawDecodeResult, Error>?.none))
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
                TurboModel.removeRetired()
            }
            let ids = [model.tokenizer.bosID] + model.tokenizer.encode(prompt, addBOS: false)
            let left = model.maxContext - ids.count
            guard left >= room else { throw PromptTooLong() }
            var limited = config
            limited.maxNewTokens = min(config.maxNewTokens, left)
            guard !away.withLock({ $0.gone }) else { throw Interrupted() }
            let start = model.start(for: ids)
            let job = Task(executorPreference: Self.thread) { [limited] in
                try await runRawCompletion(producer: model.runner, tokenizer: model.tokenizer, promptIds: ids, config: limited,
                                           context: model.context, scratch: model.scratch, prefillConfig: model.prefill,
                                           start: start) { onEvent($0, model.tokenizer) }
            }
            if away.withLock({ state in state.job = job; return state.gone }) { job.cancel() }
            do {
                let result = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
                model.cached = result.kvBackedTokenIDs
                return result
            } catch {
                model.cached = []   // what the cache holds is no longer known
                model.runner.reset()
                if away.withLock({ $0.gone }) { throw Interrupted() }
                throw error
            }
        }
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

    /// Runs `body` with the screen kept on: Auto-Lock would take the app to the
    /// background and end the job, and a reply on this model can outlast its minute.
    private static func awake<T>(_ body: () async throws -> T) async throws -> T {
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
        do {
            let result = try await body()
            await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
            return result
        } catch {
            await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
            throw error
        }
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

/// The model's output so far, with its thought channel's markers put back where they
/// came (they're special tokens, which decode to nothing) for `Reasoned.gemma` to read.
/// Written by one job at a time.
private final class Output: @unchecked Sendable {
    var raw = ""
    var firstWords: Duration?
    /// The tokens it has written, and how often it went on from them after the author came back.
    var tokens = 0
    var resumed = 0

    /// Adds what a token wrote; false for anything else (the prompt being read).
    func add(_ event: RawDecodeProgress, _ tokenizer: GFTokenizer) -> Bool {
        switch event {
        case .prefill:
            return false
        case .token(_, let id, let delta):
            tokens += 1
            raw += delta
            if id == tokenizer.channelStartID {
                raw += "<|channel>"
            } else if id == tokenizer.channelEndID {
                raw += "<channel|>"
            }
        case .tail(let text):
            raw += text
        }
        return true
    }

    /// Starts over (filing, whose output isn't shown, begun again after the author left the app).
    func clear() {
        raw = ""
        firstWords = nil
        tokens = 0
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
