import XCTest
import WriterCore
import Provenance
@testable import Guardrails

final class CreativeRequestTests: XCTestCase {
    func testDetectsCreativeRequests() {
        for m in ["Write the next scene", "Can you suggest a name for her brother?", "brainstorm some magic systems",
                  "What should happen after the storm?", "Give me ideas for the ending"] {
            XCTAssertTrue(CreativeRequest.isCreative(m), m)
        }
    }

    func testAllowsReflectiveRequests() {
        for m in ["Where did I mention the brother?", "Do my notes contradict each other about the island?",
                  "Ask me about Mara's motives", "Help me brainstorm the ending"] {
            XCTAssertFalse(CreativeRequest.isCreative(m), m)
        }
    }
}

final class IllustrationPlanTests: XCTestCase {
    func testOnlyEstablishedFactsAreDrawnAndRestStaysUnknown() {
        let p = Paragraph(text: "Mara had red hair. Maybe she was tall.")
        let doc = Document(paragraphs: [p])
        var kb = KnowledgeBase()
        kb.ingest(facts: [
            Fact(subject: "Mara", attribute: "hair", value: "red hair", certainty: .established,
                 sources: [SourceRef(documentID: doc.id, paragraphID: p.id, quote: "Mara had red hair")]),
            Fact(subject: "Mara", attribute: "build", value: "tall", certainty: .speculative,
                 sources: [SourceRef(documentID: doc.id, paragraphID: p.id, quote: "Maybe she was tall")]),
        ], from: [doc])

        let plan = IllustrationPlan.make(kind: .character, subject: "Mara", knowledge: kb)
        XCTAssertEqual(plan.known.map(\.attribute), ["hair"])
        XCTAssertTrue(plan.unknown.map(\.attribute).contains("build"), "speculation is not drawn")
        XCTAssertTrue(plan.prompt.contains("red hair"))
        XCTAssertFalse(plan.prompt.contains("tall"))
        XCTAssertLessThan(plan.completeness, 0.5)
    }

    func testSeedIsStableAndCompletenessDrivesRendering() {
        let a = IllustrationPlan.make(kind: .place, subject: "The Lighthouse", knowledge: KnowledgeBase())
        let b = IllustrationPlan.make(kind: .place, subject: "the lighthouse", knowledge: KnowledgeBase())
        XCTAssertEqual(a.seed, b.seed)
        XCTAssertEqual(a.completeness, 0)
        XCTAssertLessThan(a.denoiseStrength, 0.5)
    }
}
