#if DEBUG
import Foundation
import Guardrails
import WriterCore

/// The companion's model in a scene (`LaunchScene`): nothing to download, no inference, a script
/// that puts the companion in the state the scene shows and, where that state is one it would
/// pass through (thinking, a reply half written, filing, downloading), holds it there.
struct ScriptedModel: CompanionModel {
    enum Script: Sendable {
        /// Installed and able to reply. It's never asked unless the conversation in front is
        /// waiting on the companion: then it writes its reply and finishes.
        case ready
        /// It thinks, and goes on thinking.
        case thinking
        /// It thinks, then writes half its reply, and goes on writing.
        case streaming
        /// The reply fails.
        case failed
        /// It isn't on the phone: the download is offered.
        case downloadOffer
        /// It isn't on the phone, and its download, once started, stays at 40%.
        case downloading
        /// Filing the author's words goes on and on, so what's still to be filed shows as
        /// being filed.
        case filing
    }

    let script: Script
    /// Where the download's progress goes (`Companion.download`).
    let progress: @MainActor @Sendable (Download) -> Void

    private static let size: Int64 = 3_106_000_000   // the companion's model, as ModelCatalog has it
    private static let thought = "They stopped on Mara's mother. Ask who she was, and what happened when she tried to land."
    private static let reply = "Mara's mother tried to land in the south cove? What happened to her when she did?"

    var unavailableReason: String? { get async { nil } }
    var isInstalled: Bool { script != .downloadOffer && script != .downloading }
    func downloadSize() async -> Int64? { Self.size }

    func prepare() async throws {
        guard script == .downloading else { return }
        let done = Self.size * 2 / 5, bytesPerSecond = 14_000_000
        // Worded as the real download words it (`LlamaModel`), from Foundation.
        let worded = Progress(totalUnitCount: Self.size)
        worded.kind = .file
        worded.fileOperationKind = .downloading
        worded.completedUnitCount = done
        worded.throughput = bytesPerSecond
        worded.estimatedTimeRemaining = Double(Self.size - done) / Double(bytesPerSecond)
        await progress(Download(done: done, total: Self.size, detail: worded.localizedAdditionalDescription))
        try await Self.hold()
    }

    func stream(_ prompt: CompanionPrompt, tools: ReplyTools, thinking: Bool) -> AsyncThrowingStream<ReplySoFar, Error> {
        let script = script
        return streaming { continuation in
            switch script {
            case .thinking:
                continuation.yield(ReplySoFar(reply: Reasoned(reasoning: Self.thought)))
                try await Self.hold()
            case .streaming:
                let words = Self.reply.split(separator: " ")
                let half = words.prefix(words.count / 2).joined(separator: " ")
                continuation.yield(ReplySoFar(reply: Reasoned(reasoning: Self.thought, reply: half)))
                try await Self.hold()
            case .failed:
                await SceneStage.report(.held)
                throw Failed()
            case .ready, .downloadOffer, .downloading, .filing:
                // Word by word, as a model writes.
                var written: [Substring] = []
                for word in Self.reply.split(separator: " ") {
                    written.append(word)
                    continuation.yield(ReplySoFar(reply: Reasoned(reasoning: Self.thought, reply: written.joined(separator: " "))))
                    try await Task.sleep(for: .milliseconds(40))
                }
            }
        }
    }

    /// Nothing found, at once; in `filing`, never done. The companion marks the message as being
    /// read before it asks (`filingTurn`), so "Adding to your pages…" is under its reply by the
    /// time the hold tells the scene, which waits half a second more.
    func file(_ prompt: FilingPrompt) async throws -> Filings {
        guard script == .filing else { return Filings() }
        try await Self.hold()
    }

    /// The reply failing, as a model's can.
    private struct Failed: Error {}

    /// Holds the state now on screen until the scene ends (or the companion lets it go), once
    /// the scene knows it's there.
    private static func hold() async throws -> Never {
        await SceneStage.report(.held)
        while true { try await Task.sleep(for: .seconds(3600)) }
    }
}
#endif
