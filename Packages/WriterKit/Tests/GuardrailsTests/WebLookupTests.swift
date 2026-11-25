import Foundation
import XCTest
@testable import Guardrails
import WriterCore

/// The companion's look-ups of the real world (`WebLookup`) and the tools of one reply
/// (`ReplyTools`). Wikipedia's answers here are made up in its API's shape; nothing is sent.
final class WebLookupTests: XCTestCase {
    private let search = Data("""
        {"batchcomplete":true,"query":{"searchinfo":{"totalhits":3},"search":[
          {"ns":0,"title":"Galley","pageid":1,"snippet":"Galley <span class=\\"searchmatch\\">rowers</span> were mostly free men, &quot;paid&quot; by the day"},
          {"ns":0,"title":"Trireme","pageid":2,"snippet":"A trireme was a ship"},
          {"ns":0,"title":"Missing","pageid":3,"snippet":"not returned below"}]}}
        """.utf8)
    private let page = Data("""
        {"batchcomplete":true,"query":{"pages":[{"pageid":1,"ns":0,"title":"Galley",
          "extract":"A galley is a ship propelled mainly by oars.\\nHistory\\nMore text here.","fullurl":"https://en.wikipedia.org/wiki/Galley"}]}}
        """.utf8)

    private let galley = WebLookup.Article(text: """
        A galley is a ship propelled mainly by oars, used for war and trade in the Mediterranean.
        History
        Galleys were rowed by free men for most of antiquity, paid by the day; slaves rowed only when free rowers ran short.
        The first galleys appeared in the Bronze Age, long before the trireme, and were narrow open boats.
        """, url: URL(string: "https://en.wikipedia.org/wiki/Galley")!)
    private let trireme = WebLookup.Article(text: """
        A trireme was a ship of the ancient Mediterranean with three banks of oars.
        Its crew was about 170 rowers, mostly free citizens of the city, with a few marines and archers.
        """, url: URL(string: "https://en.wikipedia.org/wiki/Trireme")!)

    /// The two best articles are read: how each opens, and the paragraphs that answer the
    /// question; the third gives the passage the search matched.
    func testWhatItFindsIsTheArticlesOpeningsAndTheParagraphsThatAnswer() throws {
        let hits = try WebLookup.hits(search).prefix(2) + [WebLookup.Hit(title: "Galley slave", passage: "slaves were used when manpower was short")]
        let (text, found) = WebLookup.answer("were galley rowers free or slaves", hits: Array(hits),
                                             articles: ["Galley": galley, "Trireme": trireme])
        XCTAssertEqual(text, """
            From Wikipedia, for “were galley rowers free or slaves”:

            [1] Galley: A galley is a ship propelled mainly by oars, used for war and trade in the Mediterranean.
               Galleys were rowed by free men for most of antiquity, paid by the day; slaves rowed only when free rowers ran short.

            [2] Trireme: A trireme was a ship of the ancient Mediterranean with three banks of oars.
               Its crew was about 170 rowers, mostly free citizens of the city, with a few marines and archers.

            [3] Galley slave: …slaves were used when manpower was short…
            """)
        XCTAssertEqual(found.query, "were galley rowers free or slaves")
        XCTAssertEqual(found.sources.map(\.title), ["Galley", "Trireme", "Galley slave"])
        XCTAssertEqual(found.sources.last?.url, URL(string: "https://en.wikipedia.org/wiki/Galley_slave"))
    }

    func testAnArticleIsReadFromWikipediasAnswer() throws {
        let article = try XCTUnwrap(try WebLookup.article(page))
        XCTAssertEqual(article.url, URL(string: "https://en.wikipedia.org/wiki/Galley"))
        XCTAssertTrue(article.text.hasPrefix("A galley is a ship"))
        XCTAssertNil(try WebLookup.article(Data(#"{"query":{"pages":[{"title":"Gone","missing":true}]}}"#.utf8)))
    }

    /// A long paragraph is shown from the sentence its answer is in.
    func testALongParagraphIsShownFromTheSentenceThatAnswers() {
        let filler = String(repeating: "Ships were built along the coast in many sizes. ", count: 15)
        let text = "An opening paragraph about ships, long enough to count as the opening.\n" + filler + "A trireme carried 170 rowers. " + filler
        let passage = WebLookup.passages(text, query: "trireme rowers")
        XCTAssertEqual(passage.count, 1)
        XCTAssertTrue(passage[0].hasPrefix("\u{2026}A trireme carried 170 rowers."))
        XCTAssertLessThanOrEqual(passage[0].count, WebLookup.passageCharacters + 2)
        XCTAssertEqual(WebLookup.passages(text, query: "galley slaves"), [])
    }

    func testNothingFound() {
        let (text, found) = WebLookup.answer("zzz", hits: [], articles: [:])
        XCTAssertEqual(text, WebLookup.nothingFound("zzz"))
        XCTAssertEqual(found.sources, [])
    }

    func testAnArticleOpensWithItsWholeSentences() {
        let long = String(repeating: "A sentence about ships. ", count: 40)
        let opening = WebLookup.opening(long)
        XCTAssertLessThanOrEqual(opening.count, 400)
        XCTAssertTrue(opening.hasSuffix("ships."))
    }

    func testItAsksForTheSearchAndEachArticle() {
        let search = WebLookup.searchURL("trireme crew").absoluteString
        XCTAssertTrue(search.hasPrefix("https://en.wikipedia.org/w/api.php?"))
        XCTAssertTrue(search.contains("list=search") && search.contains("srsearch=trireme%20crew") && search.contains("srlimit=3"))
        let article = WebLookup.articleURL("Galley slave").absoluteString
        XCTAssertTrue(article.contains("titles=Galley%20slave") && article.contains("explaintext=1"))
        XCTAssertFalse(article.contains("exintro"))
    }

    // MARK: Their world stays theirs

    func testANameFromTheirPagesIsNeverSent() {
        let names = ["Port Vell", "Ilsa", "The Kestrel"]
        XCTAssertEqual(WebLookup.theirName(in: "how big was port vell", names: names), "Port Vell")
        XCTAssertEqual(WebLookup.theirName(in: "Ilsa's ship", names: names), "Ilsa")
        XCTAssertNil(WebLookup.theirName(in: "trireme crew size", names: names))
        XCTAssertNil(WebLookup.theirName(in: "portrait painting", names: names))   // whole words only
    }

    func testTheirNamesAreTheirPagesAndTheNamesTheyWrote() {
        let pages = PageLookup(pages: [.init(heading: "Ilsa", fields: ["Home: Port Vell"],
                                             paragraphs: [(UUID(), "She rows for the Abbey of Hollin. Monks live there, near Athens.")])],
                               answers: [.init(place: "", text: "her brother Tomas writes")])
        let names = WebLookup.theirNames(pages: pages, said: ["what do the monks at Hollin Abbey eat?"]) { $0 == "Athens" }
        XCTAssertEqual(names.first, "Ilsa")
        XCTAssertTrue(names.contains("Hollin") && names.contains("Abbey") && names.contains("Vell"))
        XCTAssertFalse(names.contains("Athens"))   // a word of the language: a real place
        XCTAssertFalse(names.contains("She") || names.contains("Monks") || names.contains("Home"))   // a sentence's or a field's first word
        XCTAssertEqual(WebLookup.theirName(in: "monks at hollin abbey", names: names), "Abbey")
        XCTAssertNil(WebLookup.theirName(in: "monks in medieval abbeys", names: names))
        XCTAssertNil(WebLookup.theirName(in: "history of Athens", names: names))
    }

    // MARK: The tools of one reply

    private func pages() -> PageLookup {
        PageLookup(pages: [.init(heading: "Ilsa", paragraphs: [(UUID(), "A rower on the Kestrel.")])])
    }

    func testLookUpsAreAnsweredUpToTheirBudgetAndKept() async {
        var tools = ReplyTools(pages: pages(), lookingUp: true)
        XCTAssertEqual(tools.offered.map(\.name), ["search_pages", "look_up"])
        var sent: [String] = []
        let fetch: (String) async throws -> (text: String, found: LookedUp) = { query in
            sent.append(query)
            return ("found \(query)", LookedUp(query: query, sources: []))
        }
        let first = await tools.answer("look_up", query: " trireme ", lookUp: fetch)
        XCTAssertEqual(first, "found trireme")
        let theirs = await tools.answer("look_up", query: "Ilsa rowing", lookUp: fetch)
        XCTAssertEqual(theirs, Reasoned.gemmaPlain(WebLookup.theirs("Ilsa")))
        let last = await tools.answer("look_up", query: "galley", lookUp: fetch)
        XCTAssertEqual(last, WebLookup.lastLookUp)
        let empty = await tools.answer("look_up", query: nil, lookUp: fetch)
        XCTAssertEqual(empty, WebLookup.needsQuery)
        XCTAssertEqual(sent, ["trireme"])   // never their name, never past the budget
        XCTAssertEqual(tools.lookups.map(\.query), ["trireme"])
        let page = await tools.answer("search_pages", query: "Ilsa", lookUp: fetch)
        XCTAssertTrue(page.contains("A rower on the Kestrel"))
        XCTAssertEqual(tools.queries, ["Ilsa"])
    }

    /// The plain model can list their pages: all of them, or one type's.
    func testThePlainModelCanListTheirPages() async {
        let pages = PageLookup(pages: [
            .init(heading: "Wren Hollis", type: "Character", paragraphs: [(UUID(), "A courier, seventeen.")], modified: Date(timeIntervalSince1970: 2)),
            .init(heading: "Saltmarsh", type: "Place", paragraphs: [(UUID(), "Flat, grey, wet.")], modified: Date(timeIntervalSince1970: 1)),
        ])
        var tools = ReplyTools(pages: pages, lookingUp: true, listing: true)
        XCTAssertEqual(tools.offered.map(\.name), ["list_pages", "search_pages", "look_up"])
        XCTAssertEqual(ReplyTools(pages: pages, lookingUp: false).offered.map(\.name), ["search_pages"])
        let all = await tools.answer("list_pages", query: nil) { _ in XCTFail("sent"); throw URLError(.badURL) }
        XCTAssertEqual(all, "Their pages (2):\n- Wren Hollis (Character): A courier, seventeen.\n- Saltmarsh (Place): Flat, grey, wet.")
        XCTAssertEqual(pages.list("characters"), "Their pages of that type (1):\n- Wren Hollis (Character): A courier, seventeen.")
        XCTAssertEqual(pages.list("salt"), "Their pages with that in the name (1):\n- Saltmarsh (Place): Flat, grey, wet.")
        XCTAssertTrue(pages.list("dragons").hasPrefix("Their pages (2):"))
        XCTAssertEqual(PageLookup(pages: []).list(nil), "They have no pages yet.")
    }

    func testWithLookingUpOffItIsNoToolOfItsAndAFailureIsSaid() async {
        var off = ReplyTools(pages: pages(), lookingUp: false)
        XCTAssertEqual(off.offered.map(\.name), ["search_pages"])
        let missing = await off.answer("look_up", query: "trireme") { _ in XCTFail("sent"); throw URLError(.badURL) }
        XCTAssertEqual(missing, "Tool not found: look_up")
        var on = ReplyTools(pages: nil, lookingUp: true)
        let failed = await on.answer("look_up", query: "trireme") { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertEqual(failed, WebLookup.unreachable)
        XCTAssertEqual(on.lookups, [])
    }

    func testTheInstructionsSayToLookUpWhenItIs() {
        let both = CompanionPrompt.instructions(searching: true, lookingUp: true)
        XCTAssertTrue(both.contains("say that.\n" + CompanionPrompt.lookUpInstruction + "\n" + CompanionPrompt.searchInstruction
                                    + "\n- If they asked what you think"))
        XCTAssertFalse(CompanionPrompt.instructions(searching: true).contains(WebLookup.toolName))
        XCTAssertEqual(CompanionPrompt.instructions(searching: true, lookingUp: true),
                       CompanionPrompt.instructions(lookup: .init(pages: pages(), retrieving: false, searching: true, lookingUp: true)))
    }
}
