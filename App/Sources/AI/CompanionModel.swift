import Foundation
import Guardrails
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Something that can write the companion's next reply.
protocol CompanionModel: Sendable {
    /// Why it can't run here, or nil if it can.
    var unavailableReason: String? { get async }
    /// The reply so far, growing as the model writes it, with any reasoning
    /// before it; the last is the whole reply. `lookup`: the author's pages, which it
    /// searches with search_pages (if it `canSearch`); `thinking`: reason first, if the
    /// model can. Throws `PromptTooLong` when the prompt doesn't fit the model.
    func stream(_ prompt: CompanionPrompt, lookup: PageLookup?, thinking: Bool) -> AsyncThrowingStream<ReplySoFar, Error>
    // Declared here, not only defaulted below, so a model's own versions are the
    // ones called through `any CompanionModel` (a default that isn't a
    // requirement is always the one used, whatever the model).
    /// It can look things up in the author's pages (search_pages): its prompt says so.
    var canSearch: Bool { get }
    var isInstalled: Bool { get }
    func downloadSize() async -> Int64?
    /// Downloads the model if it isn't on the phone yet; nothing else.
    func prepare() async throws
    var version: String? { get }
    /// What the author's message states, read out for filing (types, fields,
    /// new pages); `Filer` then keeps only what's in their words.
    func file(_ prompt: FilingPrompt) async throws -> Filings
}

extension CompanionModel {
    var canSearch: Bool { false }
    /// The model is on the phone (or part of iOS): it can reply without downloading anything.
    var isInstalled: Bool { true }
    /// How much the model's download is, if it has one; asked whenever the download is offered.
    func downloadSize() async -> Int64? { nil }
    func prepare() async throws {}
    /// When the model on the phone was downloaded, in words; nil if it hasn't been, or it's part of iOS.
    var version: String? { nil }
    /// Files nothing: only the companion's own model has been measured at it (Apple's runs only on the simulator).
    func file(_ prompt: FilingPrompt) async throws -> Filings { Filings() }
}

/// The prompt is more than the model can read at once.
struct PromptTooLong: Error {}

/// The model's download can't go ahead, for a reason the author can do something
/// about (too little free space): shown with the download's offer.
struct DownloadBlocked: Error {
    var reason: String
}

/// A model's first download: bytes so far and in all, and Foundation's
/// description of it (sizes, speed, time left).
struct Download: Equatable, Sendable {
    var done: Int64
    var total: Int64
    var detail: String
}

/// A reply as far as the model has got: what it has written (with any reasoning)
/// and, while it reads its prompt before writing more, how much of the prompt it has
/// read (0 to 1): seconds, shown rather than left to look stuck (Kevin, 2026-11-24).
struct ReplySoFar: Sendable {
    var reply: Reasoned
    var reading: Double? = nil
}

/// Runs `body`, which yields the reply so far, as a stream; ending the stream
/// cancels it.
func streaming(_ body: @escaping @Sendable (AsyncThrowingStream<ReplySoFar, Error>.Continuation) async throws -> Void)
    -> AsyncThrowingStream<ReplySoFar, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do { try await body(continuation); continuation.finish() } catch { continuation.finish(throwing: error) }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Apple's on-device model (never its server ones: `SystemLanguageModel.default`).
/// Used only where llama.cpp isn't (the simulator).
struct AppleModel: CompanionModel {
    var unavailableReason: String? {
        get async {
            #if canImport(FoundationModels)
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to use the companion."
            case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready. Try again in a little while."
            case .unavailable: return "Apple Intelligence isn't available on this phone."
            }
            #else
            return "Needs iOS 26 or later."
            #endif
        }
    }

    func stream(_ prompt: CompanionPrompt, lookup: PageLookup?, thinking: Bool) -> AsyncThrowingStream<ReplySoFar, Error> {
        streaming { continuation in   // Apple's model has no thinking step, nor search
            #if canImport(FoundationModels)
            let session = LanguageModelSession(model: .default, instructions: prompt.system)
            for try await snapshot in session.streamResponse(to: prompt.flattened, options: GenerationOptions(temperature: 0.7)) {
                continuation.yield(ReplySoFar(reply: Reasoned(reply: snapshot.content)))
            }
            #else
            throw CancellationError()
            #endif
        }
    }
}
