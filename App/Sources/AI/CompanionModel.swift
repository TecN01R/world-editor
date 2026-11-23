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
    /// before it; the last is the whole reply. `thinking`: reason first, if the
    /// model can. Throws `PromptTooLong` when the prompt doesn't fit the model.
    func stream(_ prompt: CompanionPrompt, thinking: Bool) -> AsyncThrowingStream<Reasoned, Error>
}

/// The prompt is more than the model can read at once.
struct PromptTooLong: Error {}

/// A model's first download: bytes so far and in all, and Foundation's
/// description of it (sizes, speed, time left).
struct Download: Equatable, Sendable {
    var done: Int64
    var total: Int64
    var detail: String
}

/// Runs `body`, which yields the reply so far, as a stream; ending the stream
/// cancels it.
func streaming(_ body: @escaping @Sendable (AsyncThrowingStream<Reasoned, Error>.Continuation) async throws -> Void)
    -> AsyncThrowingStream<Reasoned, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do { try await body(continuation); continuation.finish() } catch { continuation.finish(throwing: error) }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Apple's on-device model (never its server ones: `SystemLanguageModel.default`).
/// Used only where llama.cpp isn't (the simulator); otherwise kept for comparing it
/// with the companion's model on the phone.
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

    func stream(_ prompt: CompanionPrompt, thinking: Bool) -> AsyncThrowingStream<Reasoned, Error> {
        streaming { continuation in   // Apple's model has no thinking step
            #if canImport(FoundationModels)
            let session = LanguageModelSession(model: .default, instructions: prompt.system)
            for try await snapshot in session.streamResponse(to: prompt.flattened, options: GenerationOptions(temperature: 0.7)) {
                continuation.yield(Reasoned(reply: snapshot.content))
            }
            #else
            throw CancellationError()
            #endif
        }
    }
}
