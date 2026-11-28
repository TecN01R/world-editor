import XCTest
@testable import Guardrails
import WriterCore

/// The self-check debug builds run on the phone (`FilingSelfCheck`): with the right reading of
/// each message all five exchanges pass, and a typical wrong reading fails the one it gets wrong.
final class FilingSelfCheckTests: XCTestCase {
    /// What a model reading each exchange rightly writes, by its letter.
    private let right: [String: Filings] = [
        "a": Filings(facts: [.init(page: "Old Tamsin", field: "Trade", value: "clockmaker"),
                             .init(page: "Old Tamsin", field: "Guild", value: "Clockmakers' Guild")],
                     pages: [.init(title: "Old Tamsin", type: "Character"), .init(title: "Clockmakers' Guild", type: "Group")]),
        "b": Filings(facts: [.init(page: "Old Tamsin", field: "Expelled for", value: "mending clocks for free")]),
        "c": Filings(facts: [.init(page: "The Clockmakers' Guild", field: "Meets in", value: "the old customs house")]),
        "d": Filings(),
        "e": Filings(facts: [.init(page: "Old Tamsin", field: "Age", value: "71")]),
    ]

    /// Runs the check, each exchange read as `wrong` has it, or rightly where it has none.
    private func run(_ wrong: [String: Filings] = [:]) async -> [FilingSelfCheck.Outcome] {
        let readings = right.merging(wrong) { $1 }
        return await FilingSelfCheck.run { prompt in
            let exchange = FilingSelfCheck.exchanges.first { prompt.message.hasSuffix("Their message: \u{201C}\($0.message)\u{201D}") }
            return exchange.flatMap { readings[$0.letter] } ?? Filings()
        }
    }

    private func failures(_ outcomes: [FilingSelfCheck.Outcome]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: outcomes.filter { !$0.passed }.map { ($0.letter, $0.reason) })
    }

    func testWithTheRightReadingAllFivePass() async {
        let outcomes = await run()
        XCTAssertEqual(outcomes.map(\.letter), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(failures(outcomes), [:])
        XCTAssertEqual(outcomes.map(\.reason), ["", "", "", "", ""])
        // However the model names the page they mean: by the pronoun, or by part of its name.
        let named = await run(["b": Filings(facts: [.init(page: "she", field: "Expelled for", value: "mending clocks for free")]),
                               "c": Filings(facts: [.init(page: "the guild", field: "Meets in", value: "the old customs house")])])
        XCTAssertEqual(failures(named), [:])
    }

    /// A model that puts the pronoun's fact on a page it calls "She" (and lists one): no such
    /// page is made, and "She" is who they were last talking about, so it still lands on her page.
    func testAFactOnAPageCalledSheStillLandsOnHerPage() async {
        let outcomes = await run(["b": Filings(facts: [.init(page: "She", field: "Expelled for", value: "mending clocks for free")],
                                               pages: [.init(title: "She", type: "Character")])])
        XCTAssertEqual(failures(outcomes), [:])
    }

    /// The pronoun's fact put on another page (the guild she was expelled from) fails it, saying where it went.
    func testThePronounsFactOnAnotherPageFailsIt() async {
        let outcomes = await run(["b": Filings(facts: [.init(page: "the guild", field: "Expelled", value: "mending clocks for free")])])
        XCTAssertEqual(failures(outcomes), ["b": "it went on \u{201C}The Clockmakers' Guild\u{201D}, not \u{201C}Old Tamsin\u{201D}"])
    }

    /// A model that reads nothing out of any of them: only the question passes.
    func testNothingReadFailsAllButTheQuestion() async {
        let outcomes = await run(Dictionary(uniqueKeysWithValues: right.keys.map { ($0, Filings()) }))
        XCTAssertEqual(failures(outcomes), ["a": "nothing was filed from a plain statement", "b": "it wasn't filed",
                                            "c": "it wasn't filed", "e": "Old Tamsin's Age is 61, not 71"])
    }

    /// Her Age given by guess (on "she", or on part of her name) corrects nothing: a guess only adds.
    func testAnAgeGivenByGuessFailsTheCorrection() async {
        for name in ["she", "Tamsin"] {
            let outcomes = await run(["e": Filings(facts: [.init(page: name, field: "Age", value: "71")])])
            XCTAssertEqual(failures(outcomes), ["e": "Old Tamsin's Age is 61, not 71"], name)
        }
    }

    /// Whatever a model reads out of the question, the code files none of it.
    func testNothingIsFiledFromTheQuestionWhateverTheModelReads() async {
        let outcomes = await run(["d": Filings(facts: [.init(page: "The Clockmakers' Guild", field: "Takes back", value: "anyone")],
                                               pages: [.init(title: "anyone", type: "Character")])])
        XCTAssertEqual(failures(outcomes), [:])
    }

    /// Each exchange is asked of the model as the app asks: with who was in focus when it was
    /// sent, and what they said just before.
    func testEachExchangeIsAskedWithItsFocus() async {
        let prompts = Prompts()
        _ = await FilingSelfCheck.run { prompt in
            await prompts.add(prompt)
            return Filings()
        }
        let asked = await prompts.all
        XCTAssertEqual(asked.map(\.system), Array(repeating: FilingPrompt.instructions, count: 5))
        XCTAssertFalse(asked[0].message.contains("They were last talking about"))   // nobody yet
        // Named in the first message, though nothing was filed from it.
        XCTAssertTrue(asked[1].message.hasPrefix("No page is open: they're talking about their world as a whole. "
            + "They were last talking about \u{201C}Old Tamsin\u{201D} (type: Character): when they say"))
        XCTAssertTrue(asked[1].message.contains("Their pages: Old Tamsin (Age: 61), The Clockmakers' Guild"))
        XCTAssertTrue(asked[1].message.hasSuffix("""
            Just before, they said (only to show who and what they mean; file nothing from it): \u{201C}\(FilingSelfCheck.exchanges[0].message)\u{201D}

            Their friend said: \u{201C}Forty years at one bench.\u{201D}

            Their message: \u{201C}she was expelled from the guild for mending clocks for free\u{201D}
            """))
    }

    private actor Prompts {
        var all: [FilingPrompt] = []
        func add(_ prompt: FilingPrompt) { all.append(prompt) }
    }

    /// The correction is two sentences here. Run into its question with a comma, as it's often
    /// written, it is one sentence and a question: it states nothing, so none of it would be filed.
    func testTheCorrectionRunIntoItsQuestionStatesNothing() {
        XCTAssertTrue(Filer.states(FilingSelfCheck.exchanges[4].message))
        XCTAssertFalse(Filer.states("Actually Old Tamsin is 71 not 61, does that change anything?"))
        XCTAssertFalse(Filer.states(FilingSelfCheck.exchanges[3].message))   // the question itself
    }
}
