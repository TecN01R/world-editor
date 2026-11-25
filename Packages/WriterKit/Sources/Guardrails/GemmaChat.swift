import Foundation

/// Gemma 4's chat format, as the companion's model (NVIDIA's Nemotron 3.5 Bolt E4B, a
/// Gemma 4 E4B) renders a conversation with its own chat template, and as it writes back.
/// llama.cpp's server applies that template on the computer; on the phone there is no
/// template engine, so this renders the part of it the companion uses: a system turn
/// (thinking switched on there), its tools declared (`search_pages`, `look_up`), the conversation, and within the reply being written, the calls it has made so far.
/// The tests compare it with what llama.cpp's server renders from the model file's template.
///
/// Everything put in is plain already: the app's texts through `Reasoned.gemmaPlain`, and
/// `PageLookup.results`, so typed control tokens stay words.
public enum GemmaChat {
    /// A tool the model is offered, with one argument (`query`, unless it says otherwise), which
    /// isn't required.
    public struct Tool: Equatable, Sendable {
        public var name: String
        public var description: String
        /// The guide of its argument.
        public var queryGuide: String
        /// Its argument's name.
        public var argument: String

        public init(name: String, description: String, queryGuide: String, argument: String = "query") {
            self.name = name
            self.description = description
            self.queryGuide = queryGuide
            self.argument = argument
        }

        /// It as the template declares it.
        var declaration: String {
            "declaration:\(name){description:" + quoted(description) + ",parameters:{properties:{\(argument):{description:"
                + quoted(queryGuide) + ",type:" + quoted("STRING") + "}},type:" + quoted("OBJECT") + "}}"
        }
    }

    /// Searches the author's pages (`PageLookup`).
    public static let searchPages = Tool(name: PageLookup.toolName, description: PageLookup.toolDescription,
                                         queryGuide: PageLookup.queryGuide)
    /// Lists the author's pages (`PageLookup.list`; the plain model's).
    public static let listPages = Tool(name: PageLookup.listToolName, description: PageLookup.listToolDescription,
                                       queryGuide: PageLookup.listQueryGuide)
    /// Looks up the real world (`WebLookup`).
    public static let lookUp = Tool(name: WebLookup.toolName, description: WebLookup.toolDescription,
                                    queryGuide: WebLookup.queryGuide)
    /// Searches the documents attached to the conversation (`Documents`).
    public static let searchDocument = Tool(name: Documents.toolName, description: Documents.toolDescription,
                                            queryGuide: Documents.queryGuide)
    /// Adds to the writer's standing instructions (`Instructions`).
    public static let addInstruction = Tool(name: Instructions.toolName, description: Instructions.toolDescription,
                                            queryGuide: Instructions.argumentGuide, argument: Instructions.argument)

    /// A call the model made while writing the reply: what it thought and said before it,
    /// which tool it called and with what, and what came back. Replayed in the prompt for the
    /// rest of the reply.
    public struct Search: Equatable, Sendable {
        public var thought: String
        public var said: String
        public var tool: String
        /// nil when it gave none.
        public var query: String?
        public var found: String

        public init(thought: String = "", said: String = "", tool: String = PageLookup.toolName, query: String?, found: String) {
            self.thought = thought
            self.said = said
            self.tool = tool
            self.query = query
            self.found = found
        }
    }

    /// The prompt, from after `<bos>` (the tokenizer adds it): the system turn when there's
    /// one (`system`, thinking or tools), the turns, and the model's turn opened; within it,
    /// the calls (`searches`) made so far, after which the model goes on thinking
    /// (`thinking`) or writing.
    /// - Parameter tools: the tools declared, in order.
    public static func prompt(system: String, turns: [CompanionPrompt.Turn], searches: [Search] = [],
                              tools: [Tool], thinking: Bool) -> String {
        var text = ""
        let system = system.trimmingCharacters(in: .whitespacesAndNewlines)
        if thinking || !tools.isEmpty || !system.isEmpty {
            text = "<|turn>system\n" + (thinking ? "<|think|>\n" : "") + system
                + tools.map { "<|tool>" + $0.declaration + "<tool|>" }.joined() + "<turn|>\n"
        }
        for turn in turns {
            switch turn.speaker {
            case .author: text += "<|turn>user\n" + trimmed(turn.text) + "<turn|>\n"
            case .companion: text += "<|turn>model\n" + withoutThoughts(turn.text) + "<turn|>\n"
            }
        }
        text += "<|turn>model\n"
        guard let last = searches.last else { return text }
        for search in searches {
            if !search.thought.isEmpty { text += "<|channel>thought\n" + search.thought + "\n<channel|>" }
            let argument = tools.first { $0.name == search.tool }?.argument ?? "query"
            text += withoutThoughts(search.said) + call(search.tool, argument, search.query)
                + "<|tool_response>response:\(search.tool){value:" + quoted(search.found) + "}<tool_response|>"
        }
        // The template ends the model's turn after a call only when it said something before
        // it, and opens its thought channel again after any call (as llama.cpp's server renders it).
        if !trimmed(last.said).isEmpty { text += "<turn|>\n" }
        return text + (thinking ? thoughtOpened : "")
    }

    /// The model's thought channel opened: the end of a prompt where it goes on thinking.
    public static let thoughtOpened = "<|channel>thought\n"

    private static func call(_ tool: String, _ argument: String, _ query: String?) -> String {
        "<|tool_call>call:\(tool){" + (query.map { argument + ":" + quoted($0) } ?? "") + "}<tool_call|>"
    }

    /// The chat format's quotation mark, around every string it holds.
    private static let quote = "<|\"|>"

    private static func quoted(_ text: String) -> String { quote + text + quote }

    private static func trimmed(_ text: some StringProtocol) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A model's words as the template replays them: any thought channels taken out, trimmed.
    private static func withoutThoughts(_ text: String) -> String {
        trimmed(text.components(separatedBy: "<channel|>").map { part in
            part.range(of: "<|channel>").map { String(part[..<$0.lowerBound]) } ?? part
        }.joined())
    }

    // MARK: Reading what it wrote

    /// One pass of the model's output, read as llama.cpp's Gemma 4 parser reads it: its
    /// thought (`<|channel>thought …<channel|>`, which it may leave for a tool call without
    /// closing), what it said, and a call it made, if it made one. Whole or so far: an
    /// unfinished thought is all thought so far, and a call still being written is no call yet.
    public struct Output: Equatable, Sendable {
        public var thought = ""
        public var said = ""
        /// The tool it called (`name`), and the `query` it gave (nil when it gave none).
        public var call: (name: String, query: String?)?
        /// It began a call (`<|tool_call>`) and hasn't finished it.
        public var calling = false

        public init() {}

        public static func == (a: Output, b: Output) -> Bool {
            a.thought == b.thought && a.said == b.said && a.calling == b.calling
                && a.call?.name == b.call?.name && a.call?.query == b.call?.query
        }
    }

    /// Reads `raw`, the model's output with its special tokens written out (`<|channel>` and
    /// the like). `thinking`: the prompt ended with its thought channel open (`thoughtOpened`),
    /// so it begins inside its thought.
    public static func read(_ raw: String, thinking: Bool = false) -> Output {
        var output = Output()
        var rest = Substring((thinking ? thoughtOpened : "") + raw)
        // Its thought: empty channels (`<|channel>` not followed by "thought") are skipped.
        while rest.hasPrefix("<|channel>"), !rest.dropFirst("<|channel>".count).hasPrefix("thought") {
            rest = rest.dropFirst("<|channel>".count)
        }
        if rest.hasPrefix("<|channel>thought") {
            rest = rest.dropFirst("<|channel>thought".count)
            let end = [rest.range(of: "<channel|>"), rest.range(of: "<|tool_call>")].compactMap { $0 }
                .min { $0.lowerBound < $1.lowerBound }
            output.thought = trimmed(rest[..<(end?.lowerBound ?? rest.endIndex)])
            guard let end else { return output }
            rest = rest[end.lowerBound...]
            if rest.hasPrefix("<channel|>") { rest = rest.dropFirst("<channel|>".count) }
        }
        // What it said, up to a call; any further thought channels it wrote are left out.
        let callStart = rest.range(of: "<|tool_call>")
        output.said = withoutThoughts(String(rest[..<(callStart?.lowerBound ?? rest.endIndex)]))
            .replacingOccurrences(of: "<|channel>", with: "")
        guard let callStart else { return output }
        let body = rest[callStart.upperBound...]
        guard let close = body.range(of: "<tool_call|>") else {
            output.calling = true
            return output
        }
        output.call = parseCall(body[..<close.lowerBound])
        return output
    }

    /// `call:name{query:<|"|>…<|"|>}`: the name, and its argument, whatever it's called (quoted,
    /// or bare up to a comma or the closing brace).
    private static func parseCall(_ text: Substring) -> (name: String, query: String?) {
        var text = text
        if text.hasPrefix("call:") { text = text.dropFirst("call:".count) }
        let brace = text.firstIndex(of: "{") ?? text.endIndex
        let name = trimmed(text[..<brace])
        var arguments = text[brace...].dropFirst()
        if arguments.hasSuffix("}") { arguments = arguments.dropLast() }
        guard let colon = arguments.firstIndex(of: ":") else { return (name, nil) }
        var value = arguments[arguments.index(after: colon)...]
        if value.hasPrefix(quote) {
            value = value.dropFirst(quote.count)
            return (name, String(value.range(of: quote).map { value[..<$0.lowerBound] } ?? value))
        }
        return (name, trimmed(value.prefix { $0 != "," && $0 != "}" }))
    }
}

/// llama.cpp's thinking budget (its reasoning-budget sampler, `--reasoning-budget N`): once the model's thought has run `budget` tokens, the
/// end of its thought channel is forced, mid-sentence if need be, after any character it's
/// partway through. Each thought gets its own budget (after a search, it thinks again).
/// Counted in tokens; the engine tells it each token and whether that token finishes a
/// character, and asks it which token, if any, must come next.
public struct ThinkingBudget: Sendable {
    public enum State: Sendable { case idle, counting, finishingCharacter, forcing, done }

    public private(set) var state = State.idle
    private let start: [Int32]
    private let ends: [[Int32]]
    private let forced: [Int32]
    private let budget: Int
    private var remaining: Int
    private var forcedSoFar = 0
    /// The tokens since the last sequence it matched, as many as the longest it looks for.
    private var recent: [Int32] = []

    /// - Parameters:
    ///   - start: the tokens that open a thought (`<|channel>thought`).
    ///   - ends: the token sequences that end one naturally (`<channel|>`, or `<|tool_call>`).
    ///   - forced: what's forced when the budget runs out (`<channel|>`).
    public init(start: [Int32], ends: [[Int32]], forced: [Int32], budget: Int) {
        self.start = start
        self.ends = ends
        self.forced = forced
        self.budget = budget
        remaining = budget
    }

    /// The token the model must write next, while the budget forces the thought's end.
    public var forcedToken: Int32? {
        state == .forcing && forcedSoFar < forced.count ? forced[forcedSoFar] : nil
    }

    /// The prompt's last tokens, which the model's turn began with (llama.cpp feeds the
    /// template's generation prompt in the same way): after a search, its thought is open already.
    public mutating func prime(_ tokens: [Int32]) {
        for token in tokens { accept(token, completesCharacter: true) }
    }

    /// The model wrote `token`; `completesCharacter`: its text doesn't end partway through a
    /// UTF-8 character (`ThinkingBudget.completes`).
    public mutating func accept(_ token: Int32, completesCharacter: Bool) {
        switch state {
        case .idle, .done:
            if matches(token, [start]) { begin() }
        case .counting, .finishingCharacter:
            if matches(token, ends) {
                state = .done
            } else if state == .finishingCharacter {
                if completesCharacter { force() }
            } else {
                remaining -= 1
                if remaining <= 0 {
                    if completesCharacter { force() } else { state = .finishingCharacter; recent = [] }
                }
            }
        case .forcing:
            // An end it would have written anyway also ends the forcing.
            let ended = matches(token, ends)
            forcedSoFar += 1
            if ended || forcedSoFar >= forced.count { state = .done }
        }
    }

    private mutating func begin() {
        remaining = budget
        recent = []
        if remaining <= 0 { force() } else { state = .counting }
    }

    private mutating func force() {
        state = .forcing
        forcedSoFar = 0
        recent = []
    }

    /// Adds `token` to what it has seen, and whether that ends one of `sequences` (then it
    /// starts looking afresh, as llama.cpp's matcher does).
    private mutating func matches(_ token: Int32, _ sequences: [[Int32]]) -> Bool {
        recent.append(token)
        let longest = max(start.count, ends.map(\.count).max() ?? 1)
        if recent.count > longest { recent.removeFirst(recent.count - longest) }
        let found = sequences.contains { !$0.isEmpty && recent.ends(with: $0) }
        if found { recent = [] }
        return found
    }

    /// Whether `bytes` (a token's text) ends on a whole UTF-8 character: llama.cpp's
    /// `common_utf8_is_complete`.
    public static func completes(_ bytes: [UInt8]) -> Bool {
        guard !bytes.isEmpty else { return true }
        // From the end, back to the lead byte of the last character (at most 4 bytes).
        for back in 1...min(4, bytes.count) {
            let byte = bytes[bytes.count - back]
            if byte & 0xC0 == 0x80 { continue }   // a continuation byte
            // The lead byte, which says how many bytes its character takes.
            let length = switch byte {
            case 0xF0...: 4
            case 0xE0...: 3
            case 0xC0...: 2
            default: 1
            }
            return back >= length
        }
        return false
    }
}

private extension Array where Element: Equatable {
    func ends(with suffix: [Element]) -> Bool {
        count >= suffix.count && Array(self[(count - suffix.count)...]) == suffix
    }
}
