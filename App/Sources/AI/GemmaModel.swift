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
final class GemmaModel: QuestionModel, @unchecked Sendable {
    static let name = "Gemma 4 E2B (Q4_K_M)"

    /// Downloaded once (about 3 GB) with Hugging Face's client into its cache, so
    /// the download can show progress (AnyLanguageModel's own download can't), then
    /// loaded by path. Text only for now: the 1 GB image projector comes with images.
    private static let repo = Repo.ID(namespace: "unsloth", name: "gemma-4-E2B-it-GGUF")
    private static let file = "gemma-4-E2B-it-Q4_K_M.gguf"

    /// The download's bytes so far and in all, while it runs; nil when it ends.
    private let onProgress: @Sendable (Download?) -> Void
    private let loaded = OSAllocatedUnfairLock<LlamaLanguageModel?>(initialState: nil)

    init(onProgress: @escaping @Sendable (Download?) -> Void) { self.onProgress = onProgress }

    /// Gemma's recommended sampling (its model card): temperature 1, top-p 0.95, top-k 64.
    private static var options: GenerationOptions {
        var options = GenerationOptions(temperature: 1.0, maximumResponseTokens: 600)
        options[custom: LlamaLanguageModel.self] = .init(contextSize: 8192, topK: 64, topP: 0.95)
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
        let path = try await HubClient.default.downloadFile(at: Self.file, from: Self.repo, progress: progress, transport: .lfs)
        let model = LlamaLanguageModel(modelPath: path.path)
        loaded.withLock { $0 = model }
        return model
    }

    func stream(_ prompt: Interviewer.Prompt) -> AsyncThrowingStream<String, Error> {
        streaming { continuation in
            let model = try await self.model()
            // The conversation so far as a transcript: the instructions, then the
            // turns before the author's last, which is the prompt being answered.
            var entries: [Transcript.Entry] = [
                .instructions(.init(segments: [.text(.init(content: prompt.system))], toolDefinitions: []))
            ]
            for turn in prompt.turns.dropLast() {
                let segments: [Transcript.Segment] = [.text(.init(content: turn.text))]
                entries.append(turn.speaker == .author
                    ? .prompt(.init(segments: segments))
                    : .response(.init(assetIDs: [], segments: segments)))
            }
            let session = LanguageModelSession(model: model, transcript: Transcript(entries: entries))
            let began = ContinuousClock.now   // TRIAL: speed on the phone
            var first: Duration?, text = ""
            for try await snapshot in session.streamResponse(to: prompt.turns.last?.text ?? "", options: Self.options) {
                if first == nil { first = ContinuousClock.now - began }
                text = snapshot.content
                continuation.yield(text)
            }
            trialLog("SPEED \(Self.name): first words after \(first ?? .zero), whole reply (\(text.split(separator: " ").count) words) in \(ContinuousClock.now - began); memory left \(String(format: "%.2f GB", Double(os_proc_available_memory()) / 1e9))")   // TRIAL
        }
    }
}
#endif
