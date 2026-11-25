import Foundation
import Guardrails
import WriterCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Something that can write the companion's next reply.
protocol CompanionModel: Sendable {
    /// Why it can't run here, or nil if it can.
    var unavailableReason: String? { get async }
    /// The reply so far, growing as the model writes it, with any reasoning
    /// before it; the last is the whole reply. `tools`: what it may call while replying
    /// (search_pages, look_up), if it `canSearch`; `thinking`: reason first, if the model
    /// can. Throws `PromptTooLong` when the prompt doesn't fit the model.
    func stream(_ prompt: CompanionPrompt, tools: ReplyTools, thinking: Bool) -> AsyncThrowingStream<ReplySoFar, Error>
    // Declared here, not only defaulted below, so a model's own versions are the
    // ones called through `any CompanionModel` (a default that isn't a
    // requirement is always the one used, whatever the model).
    /// It can use tools: search the author's pages (search_pages) and look up the real world
    /// (look_up). Its prompt says so.
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

extension Reasoned {
    /// The reply as shown: its thoughts with its calls between them (in its collapsed
    /// thinking), what it said, around its calls and after, and what it looked up.
    static func shown(_ made: [GemmaChat.Search], _ lookups: [LookedUp], _ now: GemmaChat.Output) -> Reasoned {
        var thoughts: [String] = [], said: [String] = []
        for call in made {
            thoughts.append(call.thought)
            let query = call.query ?? ""
            switch call.tool {
            case WebLookup.toolName: thoughts.append("Searched Wikipedia for \u{201C}\(query)\u{201D}.")
            case PageLookup.listToolName: thoughts.append(query.isEmpty ? "Listed your pages." : "Listed your pages: \u{201C}\(query)\u{201D}.")
            default: thoughts.append("Searched your pages for \u{201C}\(query)\u{201D}.")
            }
            said.append(call.said)
        }
        thoughts.append(now.thought)
        said.append(now.said)
        func joined(_ parts: [String]) -> String { parts.filter { !$0.isEmpty }.joined(separator: "\n\n") }
        return Reasoned(reasoning: joined(thoughts), reply: joined(said),
                        searches: made.filter { $0.tool == PageLookup.toolName }.compactMap(\.query), lookups: lookups)
    }
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

/// What one pass of a model wrote: its output, a line about it for the TRIAL log, and how
/// often it went on after the author came back.
struct PassDone {
    var output: GemmaChat.Output
    var summary: String
    var resumed: Int
}

/// each pass of the model reads the prompt with the calls made so far and writes until it ends
/// its turn or calls a tool (search_pages, look_up), whose answer goes in the next pass's prompt:
/// at most three calls, after which, or if it says nothing at all, it's asked once more without
/// the tools. `pass` runs a pass of the model on `text` (`inThought`: the prompt opened its
/// thought), showing what it has written so far and, while it reads, how much of the prompt
/// it has read (0 to 1). `model` and `state`: its name, and the memory and heat, for the
/// TRIAL log.
func replyWithTools(_ prompt: CompanionPrompt, tools: ReplyTools, thinking: Bool, template: GemmaChat.Template,
                    model name: String, state: @autoclosure () -> String,
                    to continuation: AsyncThrowingStream<ReplySoFar, Error>.Continuation,
                    pass: (_ text: String, _ inThought: Bool,
                           _ show: @escaping (GemmaChat.Output, Double?) -> Void) async throws -> PassDone) async throws {
    let began = ContinuousClock.now
    var tools = tools
    var offered = tools.offered
    var made: [GemmaChat.Search] = []
    var summaries: [String] = []
    var firstWords: Duration?
    var resumed = 0
    while true {
        let text = GemmaChat.prompt(system: prompt.system, turns: prompt.turns, searches: made, tools: offered,
                                    thinking: thinking, template: template)
        // After a call Nemotron's template opens its thought for it; Google's leaves that to the model.
        let inThought = template == .nemotron && thinking && !made.isEmpty
        let soFar = made, lookups = tools.lookups
        let done = try await pass(text, inThought) { output, reading in
            let reply = Reasoned.shown(soFar, lookups, output)
            if reading == nil, firstWords == nil, !reply.reply.isEmpty { firstWords = ContinuousClock.now - began }
            continuation.yield(ReplySoFar(reply: reply, reading: reading))
        }
        summaries.append(done.summary)
        resumed += done.resumed
        let output = done.output
        if !offered.isEmpty, let call = output.call {
            guard made.count < 3 else { (offered, made) = ([], []); continue }   // a fourth: without the tools
            var search = GemmaChat.Search(thought: output.thought, said: output.said, tool: call.name, query: call.query, found: "")
            // Shown as it's made: a look-up is what leaves the phone.
            continuation.yield(ReplySoFar(reply: Reasoned.shown(made + [search], tools.lookups, GemmaChat.Output())))
            search.found = await tools.answer(call.name, query: call.query) { try await WebLookup.lookUp($0) }
            made.append(search)
            continue
        }
        let reply = Reasoned.shown(made, tools.lookups, output)
        if !offered.isEmpty, reply.reply.isEmpty { (offered, made) = ([], []); continue }   // nothing said: once without the tools
        continuation.yield(ReplySoFar(reply: reply))
        // TRIAL: speed on the phone, pass by pass, and what's left.
        func count(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }
        trialLog("SPEED \(name)\(thinking ? ", thinking" : ""): \(summaries.joined(separator: "; ")); "
            + "first words after \(firstWords ?? .zero) (\(count(reply.reasoning)) words of thinking, "
            + "calls: \(made.map { "\($0.tool) \u{201C}\($0.query ?? "")\u{201D}" }.joined(separator: ", ")), "
            + "\(reply.lookups.count) look-ups), whole reply (\(count(reply.reply)) words) "
            + "in \(ContinuousClock.now - began); "
            + (resumed > 0 ? "went on after the author came back \(resumed) times; " : "") + state())
        return
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

    func stream(_ prompt: CompanionPrompt, tools: ReplyTools, thinking: Bool) -> AsyncThrowingStream<ReplySoFar, Error> {
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
