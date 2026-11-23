#if canImport(AnyLanguageModel)
import AnyLanguageModel
import Foundation
import Guardrails
import HuggingFace
import os

/// The companion's model: Gemma 4 E2B through llama.cpp, with Hugging Face's
/// AnyLanguageModel on top (Foundation Models' session API, Gemma's own chat
/// format). Not on the simulator, which llama.cpp doesn't ship for: the
/// companion uses Apple's model there.
final class GemmaModel: CompanionModel, @unchecked Sendable {
    /// A build of Gemma: where it downloads from, and what it's called.
    private struct Build {
        let repo: Repo.ID
        let file: String
        let name: String
        var isTrial = false
    }

    /// Downloaded once (about 3 GB) with Hugging Face's client into its cache, so
    /// the download can show progress (AnyLanguageModel's own download can't), then
    /// loaded by path. Text only for now: the image projector comes with images.
    private static let standard = Build(repo: Repo.ID(namespace: "unsloth", name: "gemma-4-E2B-it-GGUF"),
                                        file: "gemma-4-E2B-it-Q4_K_M.gguf", name: "Gemma 4 E2B (Q4_K_M)")

    // TRIAL: a line in Documents/companion-trial.txt, put there from the computer
    // ("namespace/repository file.gguf"), names another build of Gemma to download
    // and use instead: a way to try one on the phone without a new app. While it
    // loads and writes a reply a marker sits beside the line, taken away however
    // the reply ends; a marker still there at the next launch means the app died
    // in the middle (too big for the phone, most likely), and the trial is passed
    // over from then on.
    private static let trialNote = URL.documentsDirectory.appendingPathComponent("companion-trial.txt")
    private static let trialLoading = trialNote.appendingPathExtension("loading")
    private static let trialFailed = trialNote.appendingPathExtension("failed")
    private static let build: Build = {
        let files = FileManager.default
        if files.fileExists(atPath: trialLoading.path) { try? files.moveItem(at: trialLoading, to: trialFailed) }
        guard !files.fileExists(atPath: trialFailed.path),
              let words = (try? String(contentsOf: trialNote, encoding: .utf8))?.split(whereSeparator: \.isWhitespace),
              words.count == 2, case let repo = words[0].split(separator: "/"), repo.count == 2
        else { return standard }
        return Build(repo: Repo.ID(namespace: String(repo[0]), name: String(repo[1])), file: String(words[1]),
                     name: words[1].replacing(".gguf", with: "") + " (trial)", isTrial: true)
    }()

    static var name: String { build.name }

    /// The download's bytes so far and in all, while it runs; nil when it ends.
    private let onProgress: @Sendable (Download?) -> Void
    private let loaded = OSAllocatedUnfairLock<LlamaLanguageModel?>(initialState: nil)

    init(onProgress: @escaping @Sendable (Download?) -> Void) { self.onProgress = onProgress }

    /// Gemma's recommended sampling (its model card): temperature 1, top-p 0.95,
    /// top-k 64, and no repetition penalty (the library's default of 1.1 otherwise
    /// applies). Room for its reasoning as well as the reply: the longest it took
    private static var options: GenerationOptions {
        var options = GenerationOptions(temperature: 1.0, maximumResponseTokens: 1500)
        options[custom: LlamaLanguageModel.self] = .init(contextSize: 8192, topK: 64, topP: 0.95, repeatPenalty: 1.0)
        return options
    }

    var unavailableReason: String? { get async { nil } }

    /// The model, downloading it first if it isn't on the phone yet.
    private func model() async throws -> LlamaLanguageModel {
        if let model = loaded.withLock({ $0 }) { return model }
        // A file download, so Foundation words its progress the way Apple's apps do
        // ("1.5 GB of 3.1 GB (12 MB/sec) — About 2 minutes remaining").
        let progress = Progress()
        progress.kind = .file
        progress.fileOperationKind = .downloading
        let report = onProgress
        let start = OSAllocatedUnfairLock<(date: Date, bytes: Int64)?>(initialState: nil)
        let watch = progress.observe(\.fractionCompleted, options: [.initial, .new]) { p, _ in
            guard p.totalUnitCount > 0 else { return }
            // Speed since this download (or its resumption) began, for the time left.
            let first = start.withLock { state in
                if state == nil { state = (date: Date(), bytes: p.completedUnitCount) }
                return state!
            }
            let seconds = Date().timeIntervalSince(first.date)
            if seconds > 2 {
                let rate = Double(p.completedUnitCount - first.bytes) / seconds
                p.throughput = Int(rate)
                p.estimatedTimeRemaining = rate > 0 ? Double(p.totalUnitCount - p.completedUnitCount) / rate : nil
            }
            report(Download(done: p.completedUnitCount, total: p.totalUnitCount, detail: p.localizedAdditionalDescription))
        }
        defer { watch.invalidate(); report(nil) }
        // A plain HTTPS download (LFS): Hugging Face's newer Xet transfer rebuilds the
        // file from chunks on the phone, which was slow here.
        let path = try await HubClient.default.downloadFile(at: Self.build.file, from: Self.build.repo, progress: progress, transport: .lfs)
        Self.markTrial()   // from here on (loading it, then replying) is what might end the app
        let model = LlamaLanguageModel(modelPath: path.path)
        loaded.withLock { $0 = model }
        return model
    }

    /// TRIAL: sets the marker that says a trial build is at work.
    private static func markTrial() {
        if build.isTrial { FileManager.default.createFile(atPath: trialLoading.path, contents: nil) }
    }

    func stream(_ prompt: CompanionPrompt, thinking thinks: Bool) -> AsyncThrowingStream<Reasoned, Error> {
        streaming { continuation in
            let model = try await self.model()
            Self.markTrial()
            defer { try? FileManager.default.removeItem(at: Self.trialLoading) }   // TRIAL: it got through this reply
            // The conversation so far as a transcript: the instructions, then the
            // turns before the author's last, which is the prompt being answered.
            // Its earlier reasoning is never among them (its makers' advice). To
            // have it think first, its makers' format is `<|think|>` opening the
            // system turn. AnyLanguageModel takes the thoughts out of what it
            // streams, so for now they can't be shown: the wait before the first
            // words is the thinking.
            let system = (thinks ? "<|think|>\n" : "") + Reasoned.gemmaPlain(prompt.system)
            var entries: [Transcript.Entry] = [
                .instructions(.init(segments: [.text(.init(content: system))], toolDefinitions: []))
            ]
            for turn in prompt.turns.dropLast() {
                let segments: [Transcript.Segment] = [.text(.init(content: Reasoned.gemmaPlain(turn.text)))]
                entries.append(turn.speaker == .author
                    ? .prompt(.init(segments: segments))
                    : .response(.init(assetIDs: [], segments: segments)))
            }
            let session = LanguageModelSession(model: model, transcript: Transcript(entries: entries))
            // TRIAL: speed on the phone. When it began to think (the prompt read),
            // when its first words came (the thinking done), and the whole reply.
            let began = ContinuousClock.now
            var thinking: Duration?, words: Duration?, reply = Reasoned(reply: ""), raw = ""
            do {
                let last = Reasoned.gemmaPlain(prompt.turns.last?.text ?? "")
                for try await snapshot in session.streamResponse(to: last, options: Self.options) {
                    raw = snapshot.content
                    reply = Reasoned.gemma(raw)
                    if thinking == nil { thinking = ContinuousClock.now - began }
                    if words == nil, !reply.reply.isEmpty { words = ContinuousClock.now - began }
                    continuation.yield(reply)
                }
            } catch LlamaLanguageModelError.promptExceedsContextWindow {
                throw PromptTooLong()
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                throw PromptTooLong()
            }
            func count(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }
            let memory = String(format: "%.2f GB", Double(os_proc_available_memory()) / 1e9)
            let timing = "read \(prompt.system.count) characters and began after \(thinking ?? .zero), "
                + "first words after \(words ?? .zero) (\(count(reply.reasoning)) words of thinking), "
                + "whole reply (\(count(reply.reply)) words) in \(ContinuousClock.now - began)"
            let output = "its output (\(raw.count) characters) began \(String(reflecting: String(raw.prefix(48))))"
            trialLog("SPEED \(Self.name)\(thinks ? ", thinking" : ""): \(timing); memory left \(memory); \(output)")   // TRIAL
        }
    }
}
#endif
