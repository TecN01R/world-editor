#if canImport(llama)
import CryptoKit
import Foundation
import Guardrails
import llama
import Network
import os
import UIKit

/// The companion's model: NVIDIA's Nemotron 3.5 Bolt E4B (OpenMDW-1.1, post-trained from
/// Google's Gemma 4 E4B, Apache-2.0), in bartowski's 4-bit file, on llama.cpp (MIT) with
/// Metal. Kevin's choice, 2026-11-25: it thinks before each reply, its thought capped at 128 tokens as llama.cpp's server caps it
/// (`ThinkingBudget`), and looks things up in the author's pages with `search_pages`, in the
/// model file's own chat format (`GemmaChat`). Its largest table, the per-layer embeddings
/// (1.9 GB), stays in storage and is read a row at a time (llama.cpp's lazy reading), so it
/// runs in about 4 GB. Not on the simulator, which llama.cpp's framework has no build for:
/// the companion uses Apple's model there.
final class LlamaModel: CompanionModel, @unchecked Sendable {
    static let name = "Nemotron 3.5 Bolt"

    /// One checked revision of the file, on Hugging Face: bartowski's Q4_K_M of NVIDIA's model.
    private enum Source {
        static let url = URL(string: "https://huggingface.co/bartowski/NVIDIA-Nemotron-3.5-Bolt-E4B-GGUF/resolve/"
                             + "7a243bc11b80212594a71d2ecddde5798a43e265/NVIDIA-Nemotron-3.5-Bolt-E4B-Q4_K_M.gguf")!
        static let bytes: Int64 = 5_162_292_576
        static let sha256 = "5f0f982d11bc1408783d13e4440b06e6c1e989024ac26f9a2999cb4c496bedcc"
    }

    /// Application Support (which iOS never clears), out of iCloud backups.
    private static let folder = URL.applicationSupportDirectory.appending(path: "Models", directoryHint: .isDirectory)
    /// Renamed to this only once whole and checked; named by its checksum, so another file
    /// of the model is never taken for it.
    fileprivate static let file = folder.appending(path: "nemotron-3.5-bolt-e4b-5f0f982d.gguf")
    /// The download so far, which a later try goes on from.
    private static let partial = folder.appending(path: "nemotron-3.5-bolt-e4b-5f0f982d.gguf.partial")

    /// Thinking before each reply is capped at this many tokens, NVIDIA's setting for the model.
    static let thinkingBudget = 128

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
    var isInstalled: Bool { FileManager.default.fileExists(atPath: Self.file.path) }
    func downloadSize() async -> Int64? { Source.bytes }

    var version: String? {
        guard let installed = (try? FileManager.default.attributesOfItem(atPath: Self.file.path))?[.creationDate] as? Date
        else { return nil }
        return "Downloaded \(installed.formatted(date: .abbreviated, time: .omitted))"
    }

    func prepare() async throws {
        guard !isInstalled else { return }
        try await install()
    }

    // MARK: - Replies

    /// Its sampling, stock (Kevin, 2026-11-25: "only run models stock"): NVIDIA's card,
    /// temperature 1 and top-p 0.95 in both thinking modes, nothing else (no top-k, which came
    /// from Gemma's card); a new seed each reply.
    private static let replying = Sampling(temperature: 1, topP: 0.95)

    /// A reply with its tools (`replyWithTools`), each pass of the model on llama.cpp.
    func stream(_ prompt: CompanionPrompt, tools: ReplyTools, thinking: Bool) -> AsyncThrowingStream<ReplySoFar, Error> {
        streaming { continuation in
            try await replyWithTools(prompt, tools: tools, thinking: thinking, model: Self.name,
                                     state: Engine.state, to: continuation) { text, inThought, show in
                let pass = Pass()
                // No length limit of its own (Kevin, 2026-11-25: he never wanted one): it writes
                // until it ends its turn or calls a tool, or the context is full.
                let run = try await Self.again(pass) {
                    try await self.engine.generate(text, written: pass.tokens, sampling: Self.replying,
                                                   budget: thinking ? Self.thinkingBudget : nil, inThought: inThought,
                                                   room: thinking ? 1000 : 300, maxNew: .max) { event in
                        switch event {
                        case .reading(let done, let total):
                            show(pass.output(inThought), Double(done) / Double(max(total, 1)))
                        case .token(let token, let piece):
                            pass.add(token, piece)
                            show(pass.output(inThought), nil)
                        }
                    }
                }
                return PassDone(output: pass.output(inThought), summary: run.summary, resumed: pass.resumed)
            }
        }
    }

    /// Reads what the message states: the model writes it as JSON, as the prompt's example
    /// shows, greedily (its most likely reading) and without thinking.
    func file(_ prompt: FilingPrompt) async throws -> Filings {
        let text = GemmaChat.prompt(system: prompt.system, turns: [.init(speaker: .author, text: prompt.message)],
                                    tools: [], thinking: false)
        let began = ContinuousClock.now
        let pass = Pass()
        let run = try await Self.again(pass, startOver: true) {
            try await self.engine.generate(text, written: [], sampling: nil, budget: nil, inThought: false, room: 300, maxNew: 600) {
                if case .token(let token, let piece) = $0 { pass.add(token, piece) }
            }
        }
        let output = pass.output(false)
        let filings = Filings.parse(output.said)
        trialLog("FILING took \(ContinuousClock.now - began) (\(run.summary)): "
                 + "\(filings.facts.count) facts, \(filings.pages.count) pages; output \(output.said)")   // TRIAL
        return filings
    }

    /// Runs `job` (a pass of the model) again if leaving the app ended it: the engine waits
    /// for the author to come back first. A reply goes on from what it had written (kept in
    /// `pass`, and on screen); filing (`startOver`) begins again. So a reply, or the filing
    /// after one, isn't lost to a look at another app.
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

    /// Downloads the model from Hugging Face (5.2 GB, one checked revision), then checks it.
    /// 5.2 GB is for Wi-Fi: on cellular, a hotspot or Wi-Fi in Low Data Mode it waits, saying
    /// why, and goes on from where it was once it's back on Wi-Fi. It stops only when the
    /// connection keeps failing (Download Paused, to resume from where it got to), or when
    /// there isn't room for it (the download offered again, with how much is needed).
    private func install() async throws {
        defer { onProgress(nil) }
        var folder = Self.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        // Another file of the model, part or whole (NVIDIA's, briefly downloaded), makes room.
        for item in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where item.lastPathComponent.contains(".gguf") && item.lastPathComponent != Self.partial.lastPathComponent {
            try? FileManager.default.removeItem(at: item)
        }
        let progress = InstallProgress(report: onProgress, total: Source.bytes)
        progress.waiting("Starting…")
        var failures = 0
        while true {
            if Self.downloaded > Source.bytes { try? FileManager.default.removeItem(at: Self.partial) }   // not this file
            let had = Self.downloaded
            try Self.checkSpace(have: had)
            try await Self.wifi(progress)
            do {
                try await Self.downloadOnWiFi(progress)
                break
            } catch is LeftWiFi {
                continue
            } catch let error as URLError where error.code != .cancelled {
                // The connection, or Hugging Face, failing: again in a minute, up to three
                // times in a row without getting further.
                failures = Self.downloaded > had ? 1 : failures + 1
                guard failures < 3 else { throw URLError(.networkConnectionLost) }
                progress.waiting("Trying again in a minute…")
                try await Task.sleep(for: .seconds(60))
            } catch is CancellationError {
                throw URLError(.networkConnectionLost)   // shown as Download Paused, to go on from here
            }
        }
        try await Self.check(progress)
        try FileManager.default.moveItem(at: Self.partial, to: Self.file)
    }

    /// How much of the download is here.
    private static var downloaded: Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: partial.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Downloads the rest of the file while the phone stays on Wi-Fi: moving to a metered
    /// network ends it (`LeftWiFi`), to go on once back.
    private static func downloadOnWiFi(_ progress: InstallProgress) async throws {
        progress.newRun()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await RangeDownload.run(Source.url, to: partial, total: Source.bytes) { progress.downloaded($0) } }
            group.addTask {
                for await path in network() {
                    if path.status != .satisfied {
                        progress.waiting("Waiting for a connection…")
                    } else if !unmetered(path) {
                        throw LeftWiFi()
                    }
                }
                throw CancellationError()   // the stream ends only when this is cancelled
            }
            // The download done, or the watcher throwing; never the watcher just ending,
            // which would pass for a download that finished.
            _ = try await group.next()
            group.cancelAll()
        }
    }

    /// Checks the whole file against its published checksum; a damaged one is removed and
    /// the download offered again.
    private static func check(_ progress: InstallProgress) async throws {
        let whole = try await Task.detached(priority: .userInitiated) { () -> Bool in
            let handle = try FileHandle(forReadingFrom: partial)
            defer { try? handle.close() }
            var hash = SHA256(), done: Int64 = 0
            // Each piece read is given back as soon as it's hashed: read without a pool of its
            // own, every piece of the 5 GB stayed in memory until the end, and iOS closed the
            // app partway through (Kevin, 2026-11-25).
            while try autoreleasepool(invoking: {
                guard let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty else { return false }
                try Task.checkCancellation()
                hash.update(data: chunk)
                done += Int64(chunk.count)
                progress.checking(done)
                return true
            }) {}
            return done == Source.bytes && hash.finalize().map { String(format: "%02x", $0) }.joined() == Source.sha256
        }.value
        guard whole else {
            try? FileManager.default.removeItem(at: partial)
            throw DownloadBlocked(reason: "The download was damaged on the way. Download it again.")
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

    /// Room for the rest of the download, by what iOS counts as free for something the author
    /// asked for (space it can clear included), with half a gigabyte to spare.
    private static func checkSpace(have: Int64) throws {
        let needed = Source.bytes - have + 500_000_000
        let free = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        guard let free, free < needed else { return }
        throw DownloadBlocked(reason: "It needs \(needed.formatted(.byteCount(style: .file))) of free space, and "
            + "\(max(free, 0).formatted(.byteCount(style: .file))) is free. Free up space in Settings › General › iPhone Storage.")
    }

    /// Frees what the models before it left on the phone, once it runs: Gemma 4 26B's files
    /// (14.3 GB, TurboFieldfare's folder and its install in progress) beside it in Models,
    /// and Gemma 4 E4B and E2B in Hugging Face's cache. One model on the phone (Kevin, 2026-11-24).
    fileprivate static func removeRetired() {
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where item.lastPathComponent != file.lastPathComponent && item.lastPathComponent != partial.lastPathComponent {
            try? fm.removeItem(at: item)
        }
        let cache = URL.cachesDirectory.appending(path: "huggingface/hub")
        for (repo, file) in [("unsloth--gemma-4-E4B-it-qat-GGUF", "gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf"),
                             ("unsloth--gemma-4-E2B-it-GGUF", "gemma-4-E2B-it-Q4_K_M.gguf")] {
            try? fm.removeItem(at: cache.appending(path: "models--" + repo))
            UserDefaults.standard.removeObject(forKey: "companionRevision." + file)
        }
    }
}

/// The job couldn't be finished: the author left the app, and iOS gives a background app
/// no GPU. It's run again once they're back (`LlamaModel.again`).
private struct Interrupted: Error {}

/// The phone moved from Wi-Fi to a metered network while the model downloaded.
private struct LeftWiFi: Error {}

/// llama.cpp failed: `what` says at what (with its return code, where it gave one).
private struct LlamaFailed: Error, CustomStringConvertible {
    var what: String
    var description: String { "llama.cpp: \(what)" }
}

/// How the model picks each token: nil in `generate` is greedy (its most likely).
private struct Sampling {
    var temperature: Float
    var topP: Float
}

/// A pass of the model: what it has written so far, as tokens and as text with its special
/// tokens written out, for `GemmaChat.read`. Written by one job at a time.
private final class Pass: @unchecked Sendable {
    private(set) var tokens: [llama_token] = []
    private var bytes: [UInt8] = []
    /// How often it went on from what it had written after the author came back.
    var resumed = 0

    func add(_ token: llama_token, _ piece: [UInt8]) {
        tokens.append(token)
        bytes += piece
    }

    /// What it has written, up to the last whole character. `inThought`: its prompt opened its thought.
    func output(_ inThought: Bool) -> GemmaChat.Output {
        var end = bytes.count
        while end > 0, !ThinkingBudget.completes(Array(bytes[max(0, end - 4)..<end])) { end -= 1 }
        return GemmaChat.read(String(decoding: bytes[..<end], as: UTF8.self), thinking: inThought)
    }

    /// Starts over (filing, whose output isn't shown, begun again after the author left the app).
    func clear() {
        tokens = []
        bytes = []
    }
}

/// What a pass of the model did, for the TRIAL log.
private struct Run {
    var promptTokens = 0
    /// Of the prompt, what the cache held already, and what was read and in how long.
    var cachedTokens = 0
    var readSeconds = 0.0
    var written = 0
    var writeSeconds = 0.0
    /// The token it ended with, or its length limit.
    var ended = ""

    var summary: String {
        let rate = writeSeconds > 0 ? Double(written) / writeSeconds : 0
        return "prompt \(promptTokens) tokens (\(cachedTokens) already read; \(promptTokens - cachedTokens) read in "
            + String(format: "%.1f s", readSeconds) + "), \(written) written in "
            + String(format: "%.1f s (%.1f a second)", writeSeconds, rate) + ", ended by \(ended)"
    }
}

/// The model as loaded, and what its KV cache holds (the prompt and output it last read and
/// wrote, as tokens). Used by one job at a time (`Engine`), on the model's thread.
private final class Loaded: @unchecked Sendable {
    let model: OpaquePointer
    let context: OpaquePointer
    let vocab: OpaquePointer
    let batch: OpaquePointer
    let maxContext: Int
    let batchSize: Int
    /// The sliding window of its local-attention layers, in tokens.
    let window: Int32
    /// The tokens that open its thought (`<|channel>thought`), end it (`<channel|>`) and call a
    /// tool, and those a prompt ends with when it has opened its thought for it
    /// (`GemmaChat.thoughtOpened`).
    let thoughtStart: [llama_token]
    let thoughtEnd: [llama_token]
    let callStart: [llama_token]
    let thoughtOpened: [llama_token]
    var cached: [llama_token] = []

    init(model: OpaquePointer, context: OpaquePointer, maxContext: Int, batchSize: Int) throws {
        self.model = model
        self.context = context
        self.maxContext = maxContext
        self.batchSize = batchSize
        window = max(1, llama_model_n_swa(model))
        guard let vocab = llama_model_get_vocab(model), let batch = llama_batch_ext_init(context) else {
            throw LlamaFailed(what: "no vocabulary or batch")
        }
        self.vocab = vocab
        self.batch = batch
        thoughtStart = Self.tokens("<|channel>thought", vocab, bos: false)
        thoughtEnd = Self.tokens("<channel|>", vocab, bos: false)
        callStart = Self.tokens("<|tool_call>", vocab, bos: false)
        thoughtOpened = Self.tokens(GemmaChat.thoughtOpened, vocab, bos: false)
    }

    deinit {
        llama_batch_ext_free(batch)
        llama_free(context)
        llama_model_free(model)
    }

    /// `text` as tokens, its special tokens recognised (the chat format's markers), after
    /// `<bos>` when `bos`.
    func tokens(_ text: String, bos: Bool) -> [llama_token] { Self.tokens(text, vocab, bos: bos) }

    private static func tokens(_ text: String, _ vocab: OpaquePointer, bos: Bool) -> [llama_token] {
        let length = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(length) + 8)
        var n = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), bos, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), bos, true)
        }
        return Array(tokens.prefix(Int(max(n, 0))))
    }

    /// A token's text, its special tokens written out.
    func piece(_ token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        if n < 0 {
            buffer = [CChar](repeating: 0, count: Int(-n))
            n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        }
        return buffer.prefix(Int(max(n, 0))).map { UInt8(bitPattern: $0) }
    }

    /// Reads `tokens` from position `at`, keeping logits for the last only.
    func read(_ tokens: ArraySlice<llama_token>, at start: Int) throws {
        llama_batch_ext_clear(batch)
        for (i, token) in tokens.enumerated() {
            let index = llama_batch_ext_add_token(batch, 0, token)
            var position = llama_pos(start + i)
            guard index >= 0, llama_batch_ext_set_pos(batch, index, &position) else { throw LlamaFailed(what: "batch") }
        }
        _ = llama_batch_ext_set_output_logits(batch, Int32(tokens.count - 1), true)
        let status = llama_process(context, LLAMA_PROCESS_TYPE_DECODE, batch)
        guard status == 0 else { throw LlamaFailed(what: "decode returned \(status)") }
    }

    /// Where reading `ids` can start: after the beginning it shares with what the cache holds
    /// (a prompt that only adds to the last reads only what's new), short of its last token,
    /// which is read again to write from. Going back further than that, the cache's
    /// sliding-window layers keep only their last positions (a window and a batch), so it can
    /// go back only as far as they still cover what follows; otherwise it reads from the start
    /// (llama.cpp's server checks the same).
    func start(for ids: [llama_token]) -> Int {
        let common = min(zip(cached, ids).prefix { $0.0 == $0.1 }.count, ids.count - 1)
        let memory = llama_get_memory(context)
        if common < cached.count {
            let covered = common == 0 || llama_memory_seq_pos_min(memory, 0) <= max(0, llama_pos(common) - window)
            guard covered, llama_memory_seq_rm(memory, 0, llama_pos(common), -1) else {
                forget()
                return 0
            }
        }
        cached = Array(cached.prefix(common))
        return common
    }

    /// Forgets what the cache holds (after a failure, when it's no longer known).
    func forget() {
        llama_memory_clear(llama_get_memory(context), true)
        cached = []
    }
}

/// Runs the model: one job at a time, as the phone has one GPU and the model one KV cache.
private final class Engine: @unchecked Sendable {
    enum Event {
        case reading(done: Int, total: Int)
        case token(llama_token, [UInt8])
    }

    private let turns = Turns()
    /// Only while holding a turn.
    private var loaded: Loaded?
    /// A memory warning came while a job held the model.
    private let warned = OSAllocatedUnfairLock(initialState: false)
    /// The model's own thread: loading the model, and waiting on the GPU token by token,
    /// block, which Swift's shared threads are not for.
    private static let thread = ModelThread()

    /// Runs the model on `prompt` (in the chat format, from after `<bos>`) and what it has
    /// `written` of this pass so far, handing each event to `onEvent`, until it ends its turn,
    /// calls a tool or has written `maxNew` tokens. `budget`: its thought's cap, in tokens;
    /// `inThought`: the prompt opened its thought. Throws `PromptTooLong` when fewer than
    /// `room` tokens would be left for its output, and `Interrupted` when the author leaves
    /// the app meanwhile.
    func generate(_ prompt: String, written: [llama_token], sampling: Sampling?, budget: Int?, inThought: Bool,
                  room: Int, maxNew: Int, onEvent: @escaping (Event) -> Void) async throws -> Run {
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
        // Leaving the app from here (loading included) ends the job before its next piece of
        // GPU work, which would fail in the background.
        let away = OSAllocatedUnfairLock(initialState: false)
        let observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                              object: nil, queue: nil) { _ in away.withLock { $0 = true } }
        defer { NotificationCenter.default.removeObserver(observer) }
        if await MainActor.run(body: { UIApplication.shared.applicationState == .background }) {
            away.withLock { $0 = true }
        }
        let stop = { away.withLock { $0 } }
        return try await Self.awake {
            guard !stop() else { throw Interrupted() }
            let model: Loaded
            if let loaded {
                model = loaded
            } else {
                model = try await Task(executorPreference: Self.thread) { try Self.load() }.value
                loaded = model
                LlamaModel.removeRetired()
            }
            let job = Task(executorPreference: Self.thread) {
                try Self.run(model, prompt: prompt, written: written, sampling: sampling, budget: budget, inThought: inThought,
                             room: room, maxNew: maxNew, stop: { stop() || Task.isCancelled }, onEvent: onEvent)
            }
            do {
                return try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
            } catch is Interrupted where Task.isCancelled {
                throw CancellationError()
            }
        }
    }

    /// The pass itself, on the model's thread.
    private static func run(_ model: Loaded, prompt: String, written: [llama_token], sampling: Sampling?, budget limit: Int?,
                            inThought: Bool, room: Int, maxNew: Int, stop: () -> Bool,
                            onEvent: (Event) -> Void) throws -> Run {
        let ids = model.tokens(prompt, bos: true) + written
        let left = model.maxContext - ids.count
        guard left >= max(100, room - written.count) else { throw PromptTooLong() }
        var run = Run(promptTokens: ids.count)
        var budget = limit.map {
            ThinkingBudget(start: model.thoughtStart, ends: [model.thoughtEnd, model.callStart], forced: model.thoughtEnd, budget: $0)
        }
        // As llama.cpp's server primes it with the template's opening of the model's turn.
        if inThought { budget?.prime(model.thoughtOpened) }
        for token in written { budget?.accept(token, completesCharacter: ThinkingBudget.completes(model.piece(token))) }
        let sampler = Self.sampler(sampling)
        defer { llama_sampler_free(sampler) }
        do {
            // Reading the prompt: what the cache doesn't hold, a batch at a time.
            let clock = ContinuousClock()
            var at = model.start(for: ids)
            run.cachedTokens = at
            let reading = clock.now
            while at < ids.count {
                guard !stop() else { throw Interrupted() }
                let end = min(at + model.batchSize, ids.count)
                try model.read(ids[at..<end], at: at)
                model.cached += ids[at..<end]
                at = end
                onEvent(.reading(done: at - run.cachedTokens, total: ids.count - run.cachedTokens))
            }
            run.readSeconds = (clock.now - reading).seconds
            // Writing, a token at a time.
            let writing = clock.now
            for _ in 0..<max(0, min(maxNew, left)) {
                let token: llama_token
                if let forced = budget?.forcedToken {
                    token = forced
                    llama_sampler_accept(sampler, token)
                } else {
                    token = llama_sampler_sample(sampler, model.context, -1)
                }
                let piece = model.piece(token)
                budget?.accept(token, completesCharacter: ThinkingBudget.completes(piece))
                if llama_vocab_is_eog(model.vocab, token) {
                    run.writeSeconds = (clock.now - writing).seconds
                    run.ended = String(decoding: piece, as: UTF8.self)
                    return run
                }
                onEvent(.token(token, piece))
                run.written += 1
                guard !stop() else { throw Interrupted() }
                try model.read([token], at: model.cached.count)
                model.cached.append(token)
            }
            run.writeSeconds = (clock.now - writing).seconds
            run.ended = "its length limit"
            return run
        } catch {
            if !(error is Interrupted) { model.forget() }   // what the cache holds is no longer known
            throw error
        }
    }

    /// The sampler chain llama.cpp's server runs it with (top-p, temperature, a new seed each
    /// time), or greedy.
    private static func sampler(_ sampling: Sampling?) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        if let sampling {
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(sampling.topP, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_temp(sampling.temperature))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))
        } else {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        }
        return chain
    }

    /// Loads the installed model on the GPU, its per-layer embeddings left in storage and read
    /// as needed, with room for a whole conversation, its tools' answers and its reply. Logs what
    /// the phone offers it (TRIAL).
    private static func load() throws -> Loaded {
        let clock = ContinuousClock()
        let began = clock.now
        let before = os_proc_available_memory()
        _ = Self.backend
        var params = llama_model_default_params()
        params.n_gpu_layers = 999
        params.load_mode = LLAMA_LOAD_MODE_MMAP
        params.lazy_mode = LLAMA_LAZY_MODE_ON
        guard let model = llama_model_load_from_file(LlamaModel.file.path, params) else {
            // A file that won't load is damaged: removed, so the download is offered again.
            trialLog("LOAD failed: removed, to download again")   // TRIAL
            try? FileManager.default.removeItem(at: LlamaModel.file)
            throw LlamaFailed(what: "the model didn't load")
        }
        let opened = clock.now
        var context = llama_context_default_params()
        // Room for a whole conversation, its tools' answers and its reply (Kevin, 2026-11-25: "you
        // WILL lift the limits"; 8,192 before): the higher memory limit has the room.
        context.n_ctx = 16384
        context.n_batch = 512
        context.n_ubatch = 512
        context.n_seq_max = 1
        // Memory kept small for the 15 Pro (Kevin's phone gives the app about 3.4 GB): its
        // sliding-window layers keep only their window (168 MB of cache in all, not 448), and
        // room is made for one token's output at a time, the only one read (117 MB, not 590).
        context.swa_full = false
        context.n_outputs_max = 1
        guard let ctx = llama_init_from_model(model, context) else {
            llama_model_free(model)
            throw LlamaFailed(what: "no context")
        }
        let loaded: Loaded
        do {
            loaded = try Loaded(model: model, context: ctx, maxContext: Int(llama_n_ctx(ctx)), batchSize: Int(context.n_batch))
        } catch {
            llama_free(ctx)   // a Loaded that failed to finish never frees them itself
            llama_model_free(model)
            throw error
        }
        trialLog("LOAD \(LlamaModel.name): model \(gigabytes(llama_model_size(model))) in \(opened - began), context "
                 + "\(loaded.maxContext) in \(clock.now - opened); memory left \(gigabytes(before)) before, "
                 + "\(gigabytes(os_proc_available_memory())) after")   // TRIAL
        return loaded
    }

    /// llama.cpp's backends, set up once; its log kept to warnings and errors, in the app's log.
    private static let backend: Void = {
        llama_log_set({ level, text, _ in
            guard level == GGML_LOG_LEVEL_WARN || level == GGML_LOG_LEVEL_ERROR, let text else { return }
            Logger(subsystem: "com.tecn01r.worldeditor", category: "llama").warning("\(String(cString: text), privacy: .public)")
        }, nil)
        llama_backend_init()
    }()

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
        if loaded != nil { trialLog("UNLOAD \(LlamaModel.name): \(reason)") }   // TRIAL
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
    /// and end the job.
    private static func awake<T>(_ body: () async throws -> T) async throws -> T {
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
        defer { Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = false } }
        return try await body()
    }

    /// TRIAL: the memory left to the app, and how hot the phone is.
    static var state: String {
        let heat = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
        return "memory left \(gigabytes(os_proc_available_memory())); heat \(heat)"
    }

    private static func gigabytes(_ bytes: some BinaryInteger) -> String { String(format: "%.2f GB", Double(bytes) / 1e9) }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
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

// MARK: - The download

/// Downloads `url` into `file`, going on from what's there with an HTTP range request
/// (Hugging Face's storage honours them, through its redirect), reporting the bytes so far.
private final class RangeDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let handle: FileHandle
    private let total: Int64
    private let report: (Int64) -> Void
    private var have: Int64
    private var failure: Error?
    private var done: CheckedContinuation<Void, Error>?
    private let range: String

    private init(file: URL, total: Int64, report: @escaping (Int64) -> Void) throws {
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        handle = try FileHandle(forWritingTo: file)
        have = Int64(try handle.seekToEnd())
        range = "bytes=\(have)-"
        self.total = total
        self.report = report
    }

    static func run(_ url: URL, to file: URL, total: Int64, report: @escaping (Int64) -> Void) async throws {
        let download = try RangeDownload(file: file, total: total, report: report)
        defer { try? download.handle.close() }
        guard download.have < total else { return }
        report(download.have)
        let configuration = URLSessionConfiguration.default
        configuration.allowsExpensiveNetworkAccess = false   // Wi-Fi only
        configuration.allowsConstrainedNetworkAccess = false
        configuration.timeoutIntervalForRequest = 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: download, delegateQueue: queue)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue(download.range, forHTTPHeaderField: "Range")
        let task = session.dataTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                queue.addOperation {
                    download.done = continuation
                    task.resume()
                }
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// The range goes with the request to wherever Hugging Face sends it.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var request = request
        request.setValue(range, forHTTPHeaderField: "Range")
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 206 || (status == 200 && have == 0) {
            completionHandler(.allow)
        } else if status == 200 {
            // The whole file, from the start, where the rest was asked for: start over.
            do {
                try handle.truncate(atOffset: 0)
                have = 0
                completionHandler(.allow)
            } catch {
                failure = error
                completionHandler(.cancel)
            }
        } else {
            // Busy or gone for now (429, 5xx): tried again later, as a dropped connection.
            failure = URLError(status == 416 ? .dataLengthExceedsMaximum : .badServerResponse)
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle.write(contentsOf: data)
            have += Int64(data.count)
            report(have)
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result = failure ?? error ?? (have < total ? URLError(.networkConnectionLost) : nil)
        if let result { done?.resume(throwing: result) } else { done?.resume() }
        done = nil
    }
}

/// The download's progress as the companion shows it: bytes so far and in all, in
/// Foundation's words for a file download, then the check of the file, which goes round the
/// bar again; and whatever it waits for meanwhile, with the bar where it was.
private final class InstallProgress: @unchecked Sendable {
    private struct State {
        var shown: Download
        /// When this run began, and the bytes it began with.
        var began: Date?
        var startedAt: Int64 = 0
        /// The bytes last shown: the download is shown every 4 MB or so, not every packet.
        var lastShown: Int64 = -1
    }

    private let report: @Sendable (Download?) -> Void
    private let total: Int64
    private let state: OSAllocatedUnfairLock<State>

    init(report: @escaping @Sendable (Download?) -> Void, total: Int64) {
        self.report = report
        self.total = total
        state = OSAllocatedUnfairLock(initialState: State(shown: Download(done: 0, total: total, detail: "Starting…")))
    }

    /// A new run of the download: its speed is its own.
    func newRun() {
        state.withLock { state in
            state.began = nil
            state.lastShown = -1
        }
    }

    /// What it's waiting for, with the bar where it was.
    func waiting(_ detail: String) {
        let shown = state.withLock { state in
            state.shown.detail = detail
            return state.shown
        }
        report(shown)
    }

    func downloaded(_ bytes: Int64) {
        let due = state.withLock { state in
            guard bytes - state.lastShown >= 4 << 20 || bytes == total else { return false }
            state.lastShown = bytes
            return true
        }
        guard due else { return }
        // A file download, worded the way Apple's apps word one
        // ("1.5 GB of 5.2 GB (12 MB/sec) — About 7 minutes remaining").
        let progress = Progress(totalUnitCount: total)
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.completedUnitCount = bytes
        let (began, from) = state.withLock { state in
            if state.began == nil { (state.began, state.startedAt) = (Date(), bytes) }
            return (state.began!, state.startedAt)
        }
        let seconds = Date().timeIntervalSince(began)
        if seconds > 2 {
            let rate = Double(bytes - from) / seconds
            progress.throughput = Int(rate)
            progress.estimatedTimeRemaining = rate > 0 ? Double(total - bytes) / rate : nil
        }
        show(Download(done: bytes, total: total, detail: progress.localizedAdditionalDescription))
    }

    func checking(_ bytes: Int64) {
        guard bytes % (256 << 20) < (8 << 20) || bytes == total else { return }   // every quarter gigabyte or so
        show(Download(done: bytes, total: total, detail: "Checking the download: \(bytes.formatted(.byteCount(style: .file))) of "
                          + "\(total.formatted(.byteCount(style: .file)))"))
    }

    private func show(_ download: Download) {
        state.withLock { $0.shown = download }
        report(download)
    }
}
#endif
