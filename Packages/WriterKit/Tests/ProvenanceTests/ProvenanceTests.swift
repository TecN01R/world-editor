import XCTest
import WriterCore
@testable import Provenance

final class ProvenanceTests: XCTestCase {
    let p1 = Paragraph(text: "Mara had red hair and a scar across her knuckles.")
    let p2 = Paragraph(text: "Maybe the lighthouse is older than the town.")
    lazy var doc = Document(paragraphs: [p1, p2])

    func ref(_ p: Paragraph, _ q: String) -> SourceRef { SourceRef(documentID: doc.id, paragraphID: p.id, quote: q) }

    func testAcceptsFactQuotedFromSource() {
        let f = Fact(subject: "Mara", attribute: "hair", value: "red", certainty: .established,
                     sources: [ref(p1, "Mara had red hair")])
        XCTAssertNoThrow(try ProvenanceValidator().validate(f, in: [doc]).get())
    }

    func testRejectsFactWithoutSource() {
        let f = Fact(subject: "Mara", attribute: "eyes", value: "green", certainty: .established, sources: [])
        XCTAssertEqual(ProvenanceValidator().validate(f, in: [doc]), .failure(.noSource))
    }

    func testRejectsQuoteThatIsNotInTheSource() {
        let f = Fact(subject: "Mara", attribute: "eyes", value: "green", certainty: .established,
                     sources: [ref(p1, "Mara had green eyes")])
        XCTAssertEqual(ProvenanceValidator().validate(f, in: [doc]), .failure(.quoteNotFound("Mara had green eyes")))
    }

    func testRejectsParaphrasedValue() {
        let f = Fact(subject: "Mara", attribute: "hair", value: "crimson", certainty: .established,
                     sources: [ref(p1, "Mara had red hair")])
        XCTAssertEqual(ProvenanceValidator().validate(f, in: [doc]), .failure(.valueNotInQuote("crimson")))
    }

    func testHedgedStatementCannotBeEstablished() {
        let f = Fact(subject: "lighthouse", attribute: "age", value: "older than the town", certainty: .established,
                     sources: [ref(p2, "Maybe the lighthouse is older than the town")])
        XCTAssertEqual(ProvenanceValidator().validate(f, in: [doc]), .failure(.speculationMarkedEstablished("older than the town")))
        var spec = f; spec.certainty = .speculative
        XCTAssertNoThrow(try ProvenanceValidator().validate(spec, in: [doc]).get())
    }

    func testUnknownStaysUnknown() {
        var kb = KnowledgeBase()
        kb.ingest(facts: [Fact(subject: "Mara", attribute: "hair", value: "red", certainty: .established,
                               sources: [ref(p1, "red hair")])], from: [doc])
        XCTAssertEqual(kb.answer(subject: "Mara", attribute: "eyes"), .unknown)
        if case .established(let v, _) = kb.answer(subject: "mara", attribute: "HAIR") { XCTAssertEqual(v, "red") }
        else { XCTFail("expected established") }
    }

    func testEditingSourceParagraphInvalidatesFacts() {
        var kb = KnowledgeBase()
        kb.ingest(facts: [Fact(subject: "Mara", attribute: "hair", value: "red", certainty: .established,
                               sources: [ref(p1, "red hair")])], from: [doc])
        kb.invalidate(paragraph: p1.id)
        XCTAssertEqual(kb.answer(subject: "Mara", attribute: "hair"), .unknown)
    }
}
