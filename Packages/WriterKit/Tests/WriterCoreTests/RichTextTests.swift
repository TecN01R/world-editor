import XCTest
@testable import WriterCore

final class RichTextTests: XCTestCase {
    private let bold = InlineStyle.bold, italic = InlineStyle.italic

    func testRunsAreMergedClampedAndSorted() {
        let p = Paragraph(text: "Hello", runs: [StyleRun(location: 3, length: 9, style: .bold),
                                                StyleRun(location: 0, length: 3, style: .bold)])
        XCTAssertEqual(p.runs, [StyleRun(location: 0, length: 5, style: .bold)])
    }

    func testOverlappingRunsCombine() {
        let p = Paragraph(text: "abcd", runs: [StyleRun(location: 0, length: 3, style: .bold),
                                               StyleRun(location: 2, length: 2, style: .italic)])
        XCTAssertEqual(p.styles, [bold, bold, [.bold, .italic], italic])
    }

    func testTypingContinuesThePrecedingStyle() {
        var p = Paragraph(text: "ab", runs: [StyleRun(location: 0, length: 2, style: .bold)])
        p.replace(2..<2, with: "c", style: p.style(at: 2))
        XCTAssertEqual(p.text, "abc")
        XCTAssertEqual(p.runs, [StyleRun(location: 0, length: 3, style: .bold)])
    }

    func testOffsetsAreUTF16() {
        let p = Paragraph(text: "🙂ab", runs: [StyleRun(location: 2, length: 1, style: .italic)])
        XCTAssertEqual(p.length, 4)
        XCTAssertEqual(p.slice(2..<4).text, "ab")
        XCTAssertEqual(p.slice(2..<4).runs, [StyleRun(location: 0, length: 1, style: .italic)])
    }

    func testSplitKeepsStylesAndContinuesTheList() {
        var d = Document(paragraphs: [Paragraph(text: "one two", kind: .bullet,
                                                runs: [StyleRun(location: 2, length: 3, style: .bold)])])
        let id = d.paragraphs[0].id
        d.split(at: 0, offset: 4)
        XCTAssertEqual(d.paragraphs.map(\.text), ["one ", "two"])
        XCTAssertEqual(d.paragraphs[0].id, id)
        XCTAssertEqual(d.paragraphs.map(\.kind), [.bullet, .bullet])
        XCTAssertEqual(d.paragraphs[0].runs, [StyleRun(location: 2, length: 2, style: .bold)])
        XCTAssertEqual(d.paragraphs[1].runs, [StyleRun(location: 0, length: 1, style: .bold)])
    }

    func testMergeShiftsTheSecondParagraphsRuns() {
        var d = Document(paragraphs: [Paragraph(text: "ab", kind: .numbered),
                                      Paragraph(text: "cd", runs: [StyleRun(location: 0, length: 1, style: .italic)])])
        XCTAssertEqual(d.mergeWithPrevious(1), 2)
        XCTAssertEqual(d.paragraphs.count, 1)
        XCTAssertEqual(d.paragraphs[0].kind, .numbered)
        XCTAssertEqual(d.paragraphs[0].runs, [StyleRun(location: 2, length: 1, style: .italic)])
    }

    func testReplaceWithLineBreaksSplitsAndPlacesTheCaret() {
        var d = Document(paragraphs: [Paragraph(text: "abcd")])
        let caret = d.replace(2..<2, in: 0, with: "X\nY\nZ")
        XCTAssertEqual(d.paragraphs.map(\.text), ["abX", "Y", "Zcd"])
        XCTAssertEqual(caret.index, 2)
        XCTAssertEqual(caret.offset, 1)
    }

    func testReplaceWithoutLineBreak() {
        var d = Document(paragraphs: [Paragraph(text: "abcd")])
        let caret = d.replace(1..<3, in: 0, with: "Q")
        XCTAssertEqual(d.paragraphs.map(\.text), ["aQd"])
        XCTAssertEqual(caret.index, 0)
        XCTAssertEqual(caret.offset, 2)
    }

    func testReturnAtEndMakesAnEmptyParagraph() {
        var d = Document(paragraphs: [Paragraph(text: "ab", kind: .bullet)])
        let caret = d.replace(2..<2, in: 0, with: "\n")
        XCTAssertEqual(d.paragraphs.map(\.text), ["ab", ""])
        XCTAssertEqual(d.paragraphs[1].kind, .bullet)
        XCTAssertEqual(caret.index, 1)
        XCTAssertEqual(caret.offset, 0)
    }

    func testToggleStyleAcrossParagraphs() {
        var d = Document(paragraphs: [Paragraph(text: "abc"), Paragraph(text: "def")])
        // "abc\ndef": select "bc\nde" = 1..<6
        d.toggle(.bold, in: 1..<6)
        XCTAssertTrue(d.has(.bold, in: 1..<6))
        XCTAssertEqual(d.paragraphs[0].runs, [StyleRun(location: 1, length: 2, style: .bold)])
        XCTAssertEqual(d.paragraphs[1].runs, [StyleRun(location: 0, length: 2, style: .bold)])
        d.toggle(.bold, in: 1..<6)
        XCTAssertTrue(d.paragraphs.allSatisfy { $0.runs.isEmpty })
    }

    /// Underline and strikethrough (iOS's Format panel's) are kept with the page like bold.
    func testUnderlineAndStrikethroughAreKept() throws {
        var d = Document(paragraphs: [Paragraph(text: "ab cd")])
        d.toggle(.underline, in: 0..<2)
        d.toggle(.strikethrough, in: 1..<4)
        XCTAssertTrue(d.has(.underline, in: 0..<2))
        XCTAssertTrue(d.has(.strikethrough, in: 1..<4))
        XCTAssertFalse(d.has(.underline, in: 3..<5))
        let saved = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(saved.paragraphs[0].runs, d.paragraphs[0].runs)
    }

    func testTogglePartlyStyledSelectionStylesAll() {
        var d = Document(paragraphs: [Paragraph(text: "abcd", runs: [StyleRun(location: 0, length: 2, style: .italic)])])
        d.toggle(.italic, in: 0..<4)
        XCTAssertEqual(d.paragraphs[0].runs, [StyleRun(location: 0, length: 4, style: .italic)])
    }

    func testToggleKindAppliesThenRemoves() {
        var d = Document(paragraphs: [Paragraph(text: "a"), Paragraph(text: "b"), Paragraph(text: "c")])
        d.toggleKind(.numbered, in: 0..<3)    // "a\nb" touches paragraphs 0 and 1
        XCTAssertEqual(d.paragraphs.map(\.kind), [.numbered, .numbered, .body])
        d.toggleKind(.numbered, in: 0..<0)
        XCTAssertEqual(d.paragraphs.map(\.kind), [.body, .numbered, .body])
    }

    func testSetParagraphsKeepsIdentityAndTakesNewFormatting() {
        var d = Document(paragraphs: [Paragraph(text: "one"), Paragraph(text: "two")])
        let ids = d.paragraphs.map(\.id)
        d.setParagraphs([Paragraph(text: "one", kind: .bullet),
                         Paragraph(text: "two!", runs: [StyleRun(location: 0, length: 3, style: .bold)])])
        XCTAssertEqual(d.paragraphs.map(\.id), ids)
        XCTAssertEqual(d.paragraphs[0].kind, .bullet)
        XCTAssertEqual(d.paragraphs[1].runs.count, 1)
    }

    func testLocate() {
        let d = Document(paragraphs: [Paragraph(text: "abc"), Paragraph(text: ""), Paragraph(text: "de")])
        XCTAssertEqual(d.paragraphStarts, [0, 4, 5])
        XCTAssertEqual(d.locate(3).index, 0)
        XCTAssertEqual(d.locate(4).index, 1)
        XCTAssertEqual(d.locate(6).index, 2)
        XCTAssertEqual(d.locate(6).offset, 1)
    }

    func testHeadingAndPreview() {
        let d = Document(paragraphs: [Paragraph(text: "  "), Paragraph(text: " Title "), Paragraph(text: "Body")])
        XCTAssertEqual(d.heading, "Title")
        XCTAssertEqual(d.preview, "Body")
        XCTAssertTrue(Document().isEmpty)
    }

    func testTitleIsTheHeadingOnceSet() {
        var d = Document(paragraphs: [Paragraph(text: "First line"), Paragraph(text: "Second")])
        d.setTitle(" Harbour ")
        XCTAssertEqual(d.heading, "Harbour")
        XCTAssertEqual(d.preview, "First line")
        XCTAssertFalse(Document(title: "x").isEmpty)
    }

    func testOldFilesDecodeAndPlainParagraphsStayLean() throws {
        let old = #"{"id":"6B29FC40-CA47-1067-B31D-00DD010662DA","text":"hi"}"#
        let p = try JSONDecoder().decode(Paragraph.self, from: Data(old.utf8))
        XCTAssertEqual(p.kind, .body)
        XCTAssertEqual(p.runs, [])
        let json = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        XCTAssertFalse(json.contains("kind"))
        XCTAssertFalse(json.contains("runs"))
        XCTAssertFalse(json.contains("links"))
        let rich = Paragraph(text: "hi", kind: .bullet, runs: [StyleRun(location: 0, length: 1, style: .bold)],
                             links: [PageLink(location: 0, length: 2, page: UUID())])
        XCTAssertEqual(try JSONDecoder().decode(Paragraph.self, from: JSONEncoder().encode(rich)), rich)
    }

    // MARK: @ links

    private let harbour = UUID()

    func testTypingNextToALinkNeverExtendsIt() {
        var p = Paragraph(text: "see Harbour", links: [PageLink(location: 4, length: 7, page: harbour)])
        p.replace(11..<11, with: " now", style: [])
        p.replace(4..<4, with: "the ", style: [])
        XCTAssertEqual(p.links, [PageLink(location: 8, length: 7, page: harbour)])
        XCTAssertEqual(p.link(at: 15)?.page, harbour)   // caret just after the link
        XCTAssertNil(p.link(at: 8))                      // caret just before it
    }

    func testSplitAndMergeCarryLinks() {
        var d = Document(paragraphs: [Paragraph(text: "ab Harbour", links: [PageLink(location: 3, length: 7, page: harbour)])])
        d.split(at: 0, offset: 3)
        XCTAssertEqual(d.paragraphs[1].links, [PageLink(location: 0, length: 7, page: harbour)])
        d.mergeWithPrevious(1)
        XCTAssertEqual(d.paragraphs[0].links, [PageLink(location: 3, length: 7, page: harbour)])
        XCTAssertTrue(d.mentions(harbour))
        XCTAssertFalse(d.mentions(UUID()))
    }

    func testMentionQuery() {
        XCTAssertEqual(Mention.query(in: "see @harb", caret: 9)?.range, 4..<9)
        XCTAssertEqual(Mention.query(in: "@The Black Tower, again", caret: 23)?.query, "The Black Tower, again")
        XCTAssertNil(Mention.query(in: "@" + String(repeating: "x", count: Mention.maxLength + 1),
                                   caret: Mention.maxLength + 2))             // longer than a line: over
        XCTAssertNil(Mention.query(in: "me@mail", caret: 7))                   // not after a space
        XCTAssertNil(Mention.query(in: "@ 5pm", caret: 5))
        XCTAssertEqual(Mention.query(in: "@", caret: 1)?.query, "")            // bare @: recent pages
    }

    func testRenamingAPageRenamesItsLinks() {
        var d = Document(paragraphs: [Paragraph(text: "Ask Mara now", runs: [StyleRun(location: 4, length: 4, style: .bold)],
                                                links: [PageLink(location: 4, length: 4, page: harbour)])])
        XCTAssertTrue(d.retitleLinks(to: harbour, as: "Mara Vey"))
        XCTAssertEqual(d.paragraphs[0].text, "Ask Mara Vey now")
        XCTAssertEqual(d.paragraphs[0].links, [PageLink(location: 4, length: 8, page: harbour)])
        XCTAssertEqual(d.paragraphs[0].runs, [StyleRun(location: 4, length: 8, style: .bold)])
        XCTAssertFalse(d.retitleLinks(to: harbour, as: "Mara Vey"))   // already current
    }
}
