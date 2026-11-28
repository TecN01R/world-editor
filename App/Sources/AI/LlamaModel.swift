#if canImport(llama)
import BackgroundTasks
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

    /// A file the companion downloads: one checked revision, on Hugging Face.
    fileprivate struct ModelFile: Sendable {
        let url: URL
        let bytes: Int64
        let sha256: String
        /// Its name once whole and checked: named by its checksum, so another file is never taken for it.
        let name: String

        var file: URL { LlamaModel.folder.appending(path: name) }
        /// The download so far, which a later try goes on from.
        var partial: URL { LlamaModel.folder.appending(path: name + ".partial") }
        var isInstalled: Bool { FileManager.default.fileExists(atPath: file.path) }
    }

    /// bartowski's Q4_K_M of NVIDIA's model.
    fileprivate static let model = ModelFile(
        url: URL(string: "https://huggingface.co/bartowski/NVIDIA-Nemotron-3.5-Bolt-E4B-GGUF/resolve/"
                 + "7a243bc11b80212594a71d2ecddde5798a43e265/NVIDIA-Nemotron-3.5-Bolt-E4B-Q4_K_M.gguf")!,
        bytes: 5_162_292_576, sha256: "5f0f982d11bc1408783d13e4440b06e6c1e989024ac26f9a2999cb4c496bedcc",
        name: "nemotron-3.5-bolt-e4b-5f0f982d.gguf")

    /// What lets it see pictures (Kevin, 2026-11-26: "do pictures"): Gemma 4 E4B's vision
    /// projector, as bartowski ships it beside the model, at 16 bits (990 MB). NVIDIA trained
    /// the model on text only, so how well it sees is for Kevin to judge by using it.
    fileprivate static let eyes = ModelFile(
        url: URL(string: "https://huggingface.co/bartowski/NVIDIA-Nemotron-3.5-Bolt-E4B-GGUF/resolve/"
                 + "7a243bc11b80212594a71d2ecddde5798a43e265/mmproj-NVIDIA-Nemotron-3.5-Bolt-E4B-f16.gguf")!,
        bytes: 990_373_664, sha256: "64c6e621ee6a791765ad251f808b3981da5a1722c52b0ed473f0e4156617e6e2",
        name: "nemotron-3.5-bolt-e4b-pictures-64c6e621.gguf")

    /// Application Support (which iOS never clears), out of iCloud backups.
    private static let folder = URL.applicationSupportDirectory.appending(path: "Models", directoryHint: .isDirectory)

    /// Thinking before each reply is capped at this many tokens, NVIDIA's setting for the model.
    static let thinkingBudget = 128

    private let onProgress: @Sendable (Download?) -> Void
    private let engine: Engine
    private let memoryWarning: NSObjectProtocol

    init(onProgress: @escaping @Sendable (Download?) -> Void) {
        self.onProgress = onProgress
        let engine = Engine()
        self.engine = engine
        // Near the app's memory limit, or away from it, iOS would close it: then the model's
        // memory is given back between replies, and the next reply loads it again
        // (`Engine.unloadIfIdle`). UIKit posts the warning on the main thread.
        memoryWarning = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                               object: nil, queue: .main) { _ in
            engine.unloadIfIdle(away: MainActor.assumeIsolated { UIApplication.shared.applicationState == .background })
        }
    }

    deinit { NotificationCenter.default.removeObserver(memoryWarning) }

    var unavailableReason: String? { get async { nil } }
    var canSearch: Bool { true }
    var isInstalled: Bool { Self.model.isInstalled }
    func downloadSize() async -> Int64? { Self.model.bytes }
    var seesPictures: Bool { Self.eyes.isInstalled }
    var picturesDownloadSize: Int64? { Self.eyes.bytes }
    var filesApart: Bool { engine.filesApart }

    var version: String? {
        guard let installed = (try? FileManager.default.attributesOfItem(atPath: Self.model.file.path))?[.creationDate] as? Date
        else { return nil }
        return "Downloaded \(installed.formatted(date: .abbreviated, time: .omitted))"
    }

    func prepare() async throws {
        guard !isInstalled else { return }
        try await install(Self.model, report: onProgress)
    }

    func preparePictures(progress: @escaping @Sendable (Download?) -> Void) async throws {
        guard !seesPictures else { return }
        try await install(Self.eyes, report: progress)
    }

    // MARK: - Replies

    /// Its sampling, stock (Kevin, 2026-11-25: "only run models stock"): NVIDIA's card,
    /// temperature 1 and top-p 0.95 in both thinking modes, nothing else (no top-k, which came
    /// from Gemma's card); a new seed each reply.
    private static let replying = Sampling(temperature: 1, topP: 0.95)

    /// Reads the prompt as the reply's first pass will begin it, writing nothing: the reply
    /// then reads only from where they differ, the author's message (`Loaded.start`).
    func warmUp(_ prompt: CompanionPrompt, tools: ReplyTools, thinking: Bool) async {
        let text = GemmaChat.prompt(system: prompt.system, turns: prompt.turns, searches: [], tools: tools.offered, thinking: thinking)
        let began = ContinuousClock.now
        guard let run = try? await engine.generate(text, pictures: pictures(prompt), written: [], sampling: nil, budget: nil,
                                                   inThought: false, room: 0, maxNew: 0, onEvent: { _ in }) else { return }
        trialLog("WARM-UP took \(ContinuousClock.now - began) (\(run.summary))")   // TRIAL
    }

    /// The pictures in `prompt`, in the order its text has them (`GemmaChat.pictureMarker`);
    /// none when it can't see them yet.
    private func pictures(_ prompt: CompanionPrompt) -> [URL] {
        seesPictures ? prompt.turns.flatMap(\.pictures) : []
    }

    /// A reply with its tools (`replyWithTools`), each pass of the model on llama.cpp.
    func stream(_ prompt: CompanionPrompt, tools: ReplyTools, thinking: Bool) -> AsyncThrowingStream<ReplySoFar, Error> {
        streaming { continuation in
            // Runs on if the author leaves the app, where the phone allows it.
            let background = await MainActor.run { BackgroundReply.begin() }
            defer { BackgroundReply.end(background) }
            try await replyWithTools(prompt, tools: tools, thinking: thinking, model: Self.name,
                                     state: Engine.state, to: continuation) { text, inThought, show in
                let pass = Pass()
                // No length limit of its own (Kevin, 2026-11-25: he never wanted one): it writes
                // until it ends its turn or calls a tool, or the context is full.
                let run = try await Self.again(pass) {
                    try await self.engine.generate(text, pictures: self.pictures(prompt), written: pass.tokens,
                                                   sampling: Self.replying, budget: thinking ? Self.thinkingBudget : nil,
                                                   inThought: inThought, room: thinking ? 1000 : 300, maxNew: .max) { event in
                        switch event {
                        case .reading(let done, let total):
                            show(pass.output(inThought), Double(done) / Double(max(total, 1)))
                        case .token(let token, let piece):
                            pass.add(token, piece)
                            show(pass.output(inThought), nil)
                        }
                        BackgroundReply.progressed()
                    }
                }
                return PassDone(output: pass.output(inThought), summary: run.summary, resumed: pass.resumed)
            }
        }
    }

    /// Reads what the message states: the model writes it as JSON, as the prompt's example
    /// shows, greedily (its most likely reading) and without thinking; on a sequence of its
    /// own where the model has one (`filesApart`), so the conversation's cache is left as it was.
    func file(_ prompt: FilingPrompt) async throws -> Filings {
        let text = GemmaChat.prompt(system: prompt.system, turns: [.init(speaker: .author, text: prompt.message)],
                                    tools: [], thinking: false)
        let began = ContinuousClock.now
        let pass = Pass()
        let run = try await Self.again(pass, startOver: true) {
            try await self.engine.generate(text, written: [], sequence: Loaded.filing, sampling: nil, budget: nil,
                                           inThought: false, room: 300, maxNew: 600) {
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

    /// Downloads `item` from Hugging Face (the model, 5.2 GB, or its eyes, 990 MB; one checked
    /// revision), then checks it. That much is for Wi-Fi: on cellular, a hotspot or Wi-Fi in
    /// Low Data Mode it waits, saying why, and goes on from where it was once it's back on Wi-Fi. It stops only when the
    /// connection keeps failing (Download Paused, to resume from where it got to), or when
    /// there isn't room for it (the download offered again, with how much is needed).
    private func install(_ item: ModelFile, report: @escaping @Sendable (Download?) -> Void) async throws {
        defer { report(nil) }
        var folder = Self.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        // Another file of the model, part or whole (NVIDIA's, briefly downloaded), makes room.
        Self.removeRetired()
        let progress = InstallProgress(report: report, total: item.bytes)
        progress.waiting("Starting…")
        var failures = 0
        while true {
            if Self.downloaded(item) > item.bytes { try? FileManager.default.removeItem(at: item.partial) }   // not this file
            let had = Self.downloaded(item)
            try Self.checkSpace(item, have: had)
            try await Self.wifi(progress)
            do {
                try await Self.downloadOnWiFi(item, progress)
                break
            } catch is LeftWiFi {
                continue
            } catch let error as URLError where error.code != .cancelled {
                // The connection, or Hugging Face, failing: again in a minute, up to three
                // times in a row without getting further.
                failures = Self.downloaded(item) > had ? 1 : failures + 1
                guard failures < 3 else { throw URLError(.networkConnectionLost) }
                progress.waiting("Trying again in a minute…")
                try await Task.sleep(for: .seconds(60))
            } catch is CancellationError {
                throw URLError(.networkConnectionLost)   // shown as Download Paused, to go on from here
            }
        }
        try await Self.check(item, progress)
        try FileManager.default.moveItem(at: item.partial, to: item.file)
    }

    /// How much of `item`'s download is here.
    private static func downloaded(_ item: ModelFile) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: item.partial.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Downloads the rest of the file while the phone stays on Wi-Fi: moving to a metered
    /// network ends it (`LeftWiFi`), to go on once back.
    private static func downloadOnWiFi(_ item: ModelFile, _ progress: InstallProgress) async throws {
        progress.newRun()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await RangeDownload.run(item.url, to: item.partial, total: item.bytes) { progress.downloaded($0) } }
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
    private static func check(_ item: ModelFile, _ progress: InstallProgress) async throws {
        let whole = try await Task.detached(priority: .userInitiated) { () -> Bool in
            let handle = try FileHandle(forReadingFrom: item.partial)
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
            return done == item.bytes && hash.finalize().map { String(format: "%02x", $0) }.joined() == item.sha256
        }.value
        guard whole else {
            try? FileManager.default.removeItem(at: item.partial)
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
    private static func checkSpace(_ item: ModelFile, have: Int64) throws {
        let needed = item.bytes - have + 500_000_000
        let free = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        guard let free, free < needed else { return }
        throw DownloadBlocked(reason: "It needs \(needed.formatted(.byteCount(style: .file))) of free space, and "
            + "\(max(free, 0).formatted(.byteCount(style: .file))) is free. Free up space in Settings › General › iPhone Storage.")
    }

    /// Frees what the models before it left on the phone, once it runs or before a download:
    /// everything in Models but its own two files (Gemma 4 26B's 14.3 GB, TurboFieldfare's
    /// folder, NVIDIA's file briefly downloaded), and Gemma 4 E4B and E2B in Hugging Face's
    /// cache. One model on the phone (Kevin, 2026-11-24).
    fileprivate static func removeRetired() {
        let fm = FileManager.default
        let kept = Set([model, eyes].flatMap { [$0.file.lastPathComponent, $0.partial.lastPathComponent] })
        for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where !kept.contains(item.lastPathComponent) {
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

/// The model as loaded, and what its KV cache holds for each of its sequences (the prompt and
/// output it last read and wrote there, as tokens): the conversation's and, where the phone
/// has the memory for one (`Engine.load`), filing's own, so that filing after every reply
/// never puts its prompt over the conversation's. Used by one job at a time (`Engine`), on
/// the model's thread.
private final class Loaded: @unchecked Sendable {
    /// The conversation's sequence (pictures are seen on it), and filing's.
    static let conversation: llama_seq_id = 0
    static let filing: llama_seq_id = 1

    let model: OpaquePointer
    let context: OpaquePointer
    let vocab: OpaquePointer
    let batch: OpaquePointer
    /// The room each sequence has, in tokens.
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
    /// What each sequence's cache holds.
    var cached: [[llama_token]]
    /// What sees pictures (llama.cpp's mtmd, with `LlamaModel.eyes`), loaded with the first
    /// prompt that has one.
    private var eyes: OpaquePointer?

    init(model: OpaquePointer, context: OpaquePointer, maxContext: Int, batchSize: Int) throws {
        self.model = model
        self.context = context
        self.maxContext = maxContext
        self.batchSize = batchSize
        cached = Array(repeating: [], count: Int(llama_n_seq_max(context)))
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
        if let eyes { mtmd_free(eyes) }
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

    /// Reads `tokens` into `sequence` from position `at`, keeping logits for the last only.
    func read(_ tokens: ArraySlice<llama_token>, at start: Int, sequence: llama_seq_id) throws {
        llama_batch_ext_clear(batch)
        for (i, token) in tokens.enumerated() {
            let index = llama_batch_ext_add_token(batch, sequence, token)
            var position = llama_pos(start + i)
            guard index >= 0, llama_batch_ext_set_pos(batch, index, &position) else { throw LlamaFailed(what: "batch") }
        }
        _ = llama_batch_ext_set_output_logits(batch, Int32(tokens.count - 1), true)
        let status = llama_process(context, LLAMA_PROCESS_TYPE_DECODE, batch)
        guard status == 0 else { throw LlamaFailed(what: "decode returned \(status)") }
    }

    /// Where reading `ids` into `sequence` can start: after the beginning it shares with what its cache holds
    /// (a prompt that only adds to the last reads only what's new), short of its last token,
    /// which is read again to write from, and never inside one of its `pictures`, which is
    /// seen whole. Going back further than that, the cache's
    /// sliding-window layers keep only their last positions (a window and a batch), so it can
    /// go back only as far as they still cover what follows; otherwise it reads from the start
    /// (llama.cpp's server checks the same).
    func start(for ids: [llama_token], pictures: [Range<Int>], sequence: llama_seq_id) -> Int {
        let cached = cached[Int(sequence)]
        var common = min(zip(cached, ids).prefix { $0.0 == $0.1 }.count, ids.count - 1)
        if let picture = pictures.first(where: { $0.lowerBound < common && common < $0.upperBound }) {
            common = picture.lowerBound
        }
        let memory = llama_get_memory(context)
        if common < cached.count {
            let covered = common == 0 || llama_memory_seq_pos_min(memory, sequence) <= max(0, llama_pos(common) - window)
            guard covered, llama_memory_seq_rm(memory, sequence, llama_pos(common), -1) else {
                forget(sequence)
                return 0
            }
        }
        self.cached[Int(sequence)] = Array(cached.prefix(common))
        return common
    }

    /// `prompt` as the model reads it: its tokens, and in their place each of `pictures`, in the
    /// order of its markers (`GemmaChat.pictureMarker`), as mtmd makes it of the picture. Each
    /// picture stands in `ids` as tokens of its own, made from its file's name, so the cache
    /// sees the same picture again as the same, and another as another.
    func prompt(_ prompt: String, pictures: [URL]) throws -> ReadPrompt {
        guard !pictures.isEmpty else { return ReadPrompt(ids: tokens(prompt, bos: true)) }
        let eyes = try loadEyes()
        var bitmaps: [OpaquePointer?] = []
        defer { for bitmap in bitmaps { mtmd_bitmap_free(bitmap) } }
        for url in pictures {
            guard let bitmap = mtmd_helper_bitmap_init_from_file(eyes, url.path, false, mtmd_helper_init_opt_default()).bitmap
            else { throw LlamaFailed(what: "the picture \(url.lastPathComponent) didn't open") }
            bitmaps.append(bitmap)
        }
        guard let chunks = mtmd_input_chunks_init() else { throw LlamaFailed(what: "no chunks") }
        let read = ReadPrompt(chunks: chunks)
        let status = prompt.withCString { text in
            var input = mtmd_input_text(text: text, text_len: strlen(text), add_special: true, parse_special: true)
            return bitmaps.withUnsafeBufferPointer { mtmd_tokenize(eyes, chunks, &input, $0.baseAddress, $0.count) }
        }
        guard status == 0 else { throw LlamaFailed(what: "the prompt's pictures returned \(status)") }
        var seen = 0
        for i in 0..<mtmd_input_chunks_size(chunks) {
            guard let chunk = mtmd_input_chunks_get(chunks, i) else { continue }
            if mtmd_input_chunk_get_type(chunk) == MTMD_INPUT_CHUNK_TYPE_TEXT {
                var count = 0
                if let tokens = mtmd_input_chunk_get_tokens_text(chunk, &count) {
                    read.ids += UnsafeBufferPointer(start: tokens, count: count)
                }
            } else {
                // One position a token, as Gemma's pictures have (not M-RoPE's).
                let count = Int(mtmd_input_chunk_get_n_tokens(chunk))
                guard Int(mtmd_input_chunk_get_n_pos(chunk)) == count else { throw LlamaFailed(what: "a picture's positions") }
                // Its stand-in, from its file's name (each picture is a file of its own), in the
                // order the prompt has them.
                guard seen < pictures.count else { throw LlamaFailed(what: "more pictures than files") }
                let stand = -1 - llama_token(truncatingIfNeeded: pictures[seen].lastPathComponent.hashValue & 0x3fff_ffff)
                seen += 1
                read.pictures.append((read.ids.count..<read.ids.count + count, chunk))
                read.ids += repeatElement(stand, count: count)
            }
        }
        return read
    }

    /// Sees the picture `chunk` at position `start` of the conversation's sequence: mtmd
    /// encodes it and reads it into the cache.
    func see(_ chunk: OpaquePointer, at start: Int) throws {
        guard let eyes else { throw LlamaFailed(what: "no eyes") }
        var past: llama_pos = 0
        let status = mtmd_helper_eval_chunk_single(eyes, context, chunk, llama_pos(start), Self.conversation, Int32(batchSize),
                                                   false, &past)
        guard status == 0 else { throw LlamaFailed(what: "seeing a picture returned \(status)") }
    }

    /// Loads what sees pictures, once. A file that won't load is damaged: removed, so its
    /// download is offered again.
    private func loadEyes() throws -> OpaquePointer {
        if let eyes { return eyes }
        let clock = ContinuousClock(), began = clock.now
        var params = mtmd_context_params_default()
        params.use_gpu = true
        params.print_timings = false
        params.warmup = false
        // Gemma 4's own default budget for a picture, so one is always seen whole in a batch.
        params.image_max_tokens = 280
        guard let eyes = mtmd_init_from_file(LlamaModel.eyes.file.path, model, params) else {
            try? FileManager.default.removeItem(at: LlamaModel.eyes.file)
            throw LlamaFailed(what: "the eyes didn't load")
        }
        trialLog("EYES loaded in \(clock.now - began); memory left \(String(format: "%.2f GB", Double(os_proc_available_memory()) / 1e9))")   // TRIAL
        self.eyes = eyes
        return eyes
    }

    /// Forgets what `sequence`'s cache holds (after a failure, when it's no longer known);
    /// the other's is its own, and stays.
    func forget(_ sequence: llama_seq_id) {
        _ = llama_memory_seq_rm(llama_get_memory(context), sequence, -1, -1)   // all of it, which never fails
        cached[Int(sequence)] = []
    }
}

/// A prompt as the model reads it (`Loaded.prompt`): its tokens, with each picture's place in
/// them and its piece from mtmd, kept while the prompt is read.
private final class ReadPrompt {
    var ids: [llama_token]
    var pictures: [(range: Range<Int>, chunk: OpaquePointer)] = []
    private let chunks: OpaquePointer?

    init(ids: [llama_token] = [], chunks: OpaquePointer? = nil) {
        self.ids = ids
        self.chunks = chunks
    }

    deinit { if let chunks { mtmd_input_chunks_free(chunks) } }
}

/// Runs the model: one job at a time, as the phone has one GPU, whichever of the model's
/// sequences the job reads into.
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
    /// The model, as last loaded, has a sequence for filing beside the conversation's.
    private let apart = OSAllocatedUnfairLock(initialState: false)
    var filesApart: Bool { apart.withLock { $0 } }
    /// The model's own thread: loading the model, and waiting on the GPU token by token,
    /// block, which Swift's shared threads are not for.
    private static let thread = ModelThread()

    /// Runs the model on `prompt` (in the chat format, from after `<bos>`) and what it has
    /// `written` of this pass so far, handing each event to `onEvent`, until it ends its turn,
    /// calls a tool or has written `maxNew` tokens. `sequence`: the conversation's, or filing's
    /// own (the conversation's again where the model has only that). `budget`: its thought's cap, in tokens;
    /// `inThought`: the prompt opened its thought. Throws `PromptTooLong` when fewer than
    /// `room` tokens would be left for its output, and `Interrupted` when the author leaves
    /// the app meanwhile.
    func generate(_ prompt: String, pictures: [URL] = [], written: [llama_token], sequence: llama_seq_id = Loaded.conversation,
                  sampling: Sampling?, budget: Int?, inThought: Bool, room: Int, maxNew: Int,
                  onEvent: @escaping @Sendable (Event) -> Void) async throws -> Run {
        // iOS gives a background app no GPU, unless a reply's background task holds it
        // (`BackgroundReply`): a job asked for while the author is away (filing as they leave,
        // the first reply once the download finishes in the background) waits for them,
        // without holding the model.
        if !BackgroundReply.isRunning { try await Self.foreground() }
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
        // GPU work, which would fail in the background, unless a reply's background task
        // holds the GPU; once that ends, so does the job, and it goes on when they're back.
        let away = OSAllocatedUnfairLock(initialState: false)
        let observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                              object: nil, queue: nil) { _ in away.withLock { $0 = true } }
        defer { NotificationCenter.default.removeObserver(observer) }
        if await MainActor.run(body: { UIApplication.shared.applicationState == .background }) {
            away.withLock { $0 = true }
        }
        let stop: @Sendable () -> Bool = { away.withLock { $0 } && !BackgroundReply.isRunning }
        return try await Self.awake {
            guard !stop() else { throw Interrupted() }
            let model: Loaded
            if let loaded {
                model = loaded
            } else {
                model = try await Task(executorPreference: Self.thread) { try Self.load() }.value
                loaded = model
                apart.withLock { $0 = model.cached.count > 1 }
                LlamaModel.removeRetired()
            }
            let job = Task(executorPreference: Self.thread) {
                try Self.run(model, sequence: Int(sequence) < model.cached.count ? sequence : Loaded.conversation,
                             prompt: prompt, pictures: pictures, written: written, sampling: sampling, budget: budget,
                             inThought: inThought, room: room, maxNew: maxNew, stop: { stop() || Task.isCancelled },
                             onEvent: onEvent)
            }
            do {
                return try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
            } catch is Interrupted where Task.isCancelled {
                throw CancellationError()
            }
        }
    }

    /// The pass itself, on the model's thread, reading and writing in `sequence`.
    private static func run(_ model: Loaded, sequence: llama_seq_id, prompt text: String, pictures: [URL],
                            written: [llama_token], sampling: Sampling?, budget limit: Int?, inThought: Bool, room: Int,
                            maxNew: Int, stop: () -> Bool, onEvent: (Event) -> Void) throws -> Run {
        let prompt = try model.prompt(text, pictures: pictures)
        let ids = prompt.ids + written
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
            let cache = Int(sequence)
            var at = model.start(for: ids, pictures: prompt.pictures.map(\.range), sequence: sequence)
            run.cachedTokens = at
            let reading = clock.now
            while at < ids.count {
                guard !stop() else { throw Interrupted() }
                if let picture = prompt.pictures.first(where: { $0.range.lowerBound == at }) {
                    try model.see(picture.chunk, at: at)   // a picture, seen whole
                    model.cached[cache] += ids[picture.range]
                    at = picture.range.upperBound
                } else {
                    let next = prompt.pictures.first { $0.range.lowerBound > at }?.range.lowerBound ?? ids.count
                    let end = min(at + model.batchSize, next)
                    try model.read(ids[at..<end], at: at, sequence: sequence)
                    model.cached[cache] += ids[at..<end]
                    at = end
                }
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
                try model.read([token], at: model.cached[cache].count, sequence: sequence)
                model.cached[cache].append(token)
            }
            run.writeSeconds = (clock.now - writing).seconds
            run.ended = "its length limit"
            return run
        } catch {
            if !(error is Interrupted) { model.forget(sequence) }   // what its cache holds is no longer known
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

    /// Room for a whole conversation, its tools' answers and its reply, in tokens (Kevin,
    /// 2026-11-25: "you WILL lift the limits"; 8,192 before): what each sequence has.
    private static let sequenceRoom: UInt32 = 16384

    /// What must be left to the app once the model is loaded with a sequence for filing: half
    /// a gigabyte more than where a memory warning has it give its memory back (`nearLimit`).
    private static let roomForFiling = 1_500_000_000

    /// Loads the installed model on the GPU, its per-layer embeddings left in storage and read
    /// as needed, with room for a whole conversation, its tools' answers and its reply, and the
    /// same again for filing where the phone has the memory. Logs what the phone offers it (TRIAL).
    private static func load() throws -> Loaded {
        let clock = ContinuousClock()
        let began = clock.now
        let before = os_proc_available_memory()
        _ = Self.backend
        var params = llama_model_default_params()
        params.n_gpu_layers = 999
        params.load_mode = LLAMA_LOAD_MODE_MMAP
        params.lazy_mode = LLAMA_LAZY_MODE_ON
        guard let model = llama_model_load_from_file(LlamaModel.model.file.path, params) else {
            // A file that won't load is damaged: removed, so the download is offered again.
            trialLog("LOAD failed: removed, to download again")   // TRIAL
            try? FileManager.default.removeItem(at: LlamaModel.model.file)
            throw LlamaFailed(what: "the model didn't load")
        }
        let opened = clock.now
        var context = llama_context_default_params()
        context.n_batch = 512
        context.n_ubatch = 512
        // Memory kept small for the 15 Pro (Kevin's phone gives the app about 3.4 GB): its
        // sliding-window layers keep only their window (168 MB of cache a sequence, not 448), and
        // room is made for one token's output a sequence, the only one read (117 MB, not 590).
        context.swa_full = false
        // Two sequences, the conversation's and filing's: filing after every reply reads its
        // prompt into a cache of its own, so the next reply still finds the conversation in its
        // own (with one, filing's prompt went over it, and the conversation was read again). Each
        // has its own cells (not unified), so the context is twice a sequence's room. llama.cpp
        // keeps an output's room for each sequence, and stops the app if it's given less.
        context.kv_unified = false
        context.n_ctx = 2 * sequenceRoom
        context.n_seq_max = 2
        context.n_outputs_max = 2
        var made = llama_init_from_model(model, context)
        // Not made, or too little memory left with it: the conversation's sequence alone, as
        // before there were two.
        var alone: String?
        if let two = made {
            let left = os_proc_available_memory()
            if llama_n_ctx_seq(two) < sequenceRoom {
                alone = "two had \(llama_n_ctx_seq(two)) each"
            } else if left < roomForFiling {
                alone = "two left \(gigabytes(left)), too little"
            }
            if alone != nil {
                llama_free(two)
                made = nil
            }
        } else {
            alone = "two couldn't be made"
        }
        if made == nil {
            context.n_ctx = sequenceRoom
            context.n_seq_max = 1
            context.n_outputs_max = 1
            made = llama_init_from_model(model, context)
        }
        guard let ctx = made else {
            llama_model_free(model)
            throw LlamaFailed(what: "no context")
        }
        let loaded: Loaded
        do {
            loaded = try Loaded(model: model, context: ctx, maxContext: Int(llama_n_ctx_seq(ctx)), batchSize: Int(context.n_batch))
        } catch {
            llama_free(ctx)   // a Loaded that failed to finish never frees them itself
            llama_model_free(model)
            throw error
        }
        trialLog("LOAD \(LlamaModel.name): model \(gigabytes(llama_model_size(model))) in \(opened - began), context "
                 + "\(loaded.maxContext) on " + (alone.map { "one sequence (\($0))" } ?? "each of two sequences (filing has its own)")
                 + " in \(clock.now - opened); memory left \(gigabytes(before)) before, "
                 + "\(gigabytes(os_proc_available_memory())) after; the GPU after leaving the app "
                 + (BGTaskScheduler.supportedResources.contains(.gpu) ? "offered" : "not offered"))   // TRIAL
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

    /// A memory warning: gives back the model's memory now, or once the job at work is done,
    /// if the app is near its own limit or `away` (where iOS closes the largest apps first).
    /// iOS also warns when the phone as a whole runs short, with gigabytes still left to the
    /// app: the Duo's log (2026-11-26) had 11 loads for 13 replies, warned with 3 to 6 GB
    /// left. Unloading then frees little that counts against the app (the weights are read
    /// from storage) and costs the next reply 2 to 3 s.
    func unloadIfIdle(away: Bool) {
        guard away || Self.nearLimit else {
            trialLog("MEMORY WARNING: model kept, \(Self.gigabytes(os_proc_available_memory())) left")   // TRIAL
            return
        }
        guard turns.take() else {
            warned.withLock { $0 = true }
            return
        }
        unload(because: "memory warning")
        turns.next()
    }

    /// Less than a gigabyte left to the app: the model's own memory, about 0.4 GB counted,
    /// with room for the rest of the app.
    private static var nearLimit: Bool { os_proc_available_memory() < 1_000_000_000 }

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
