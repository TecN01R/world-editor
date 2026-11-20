import XCTest
import WriterCore
import Provenance
@testable import Guardrails

final class CompanionGuardTests: XCTestCase {
    let author = "Mara keeps the lighthouse alone. She never leaves the island, even when her brother Tomas writes."
    let guardrail = CompanionGuard()

    func testAcceptsOpenQuestionsInTheAuthorsTerms() {
        XCTAssertEqual(guardrail.check("Why does Mara never leave the island?", authorText: author), [])
        XCTAssertEqual(guardrail.check("What does Tomas want from her? What does she believe he wants?", authorText: author), [])
    }

    func testAcceptsVerbatimRestatementFollowedByQuestion() {
        let r = "You wrote \u{201C}She never leaves the island\u{201D}. What keeps her there?"
        XCTAssertEqual(guardrail.check(r, authorText: author), [])
    }

    func testAllowsReflectionAndCritiqueOfTheAuthorsOwnMaterial() {
        let r = "You wrote that Mara never leaves the island, but Tomas writes to her. Those two threads haven't met yet. Which matters more to you?"
        XCTAssertEqual(guardrail.check(r, authorText: author), [])
    }

    func testRejectsStatementsThatAddContent() {
        XCTAssertTrue(guardrail.check("Mara is lonely.", authorText: author).contains(.inventedConcept("lonely")))
    }

    func testRejectsSuggestionsDisguisedAsQuestions() {
        XCTAssertFalse(guardrail.isAcceptable("What if Mara found a letter in the lamp room?", authorText: author))
        XCTAssertFalse(guardrail.isAcceptable("Have you considered giving Tomas a secret?", authorText: author))
        XCTAssertFalse(guardrail.isAcceptable("Could she be hiding from someone?", authorText: author))
    }

    func testRejectsInventedNamesAndDetails() {
        XCTAssertTrue(guardrail.check("Does Mara trust Elias?", authorText: author).contains(.inventedName("Elias")))
        XCTAssertFalse(guardrail.isAcceptable("Is the lighthouse haunted?", authorText: author))
    }

    func testRejectsEmptyAndOverlong() {
        XCTAssertEqual(guardrail.check("   ", authorText: author), [.empty])
        let long = Array(repeating: "Why does Mara stay?", count: 80).joined(separator: " ")
        XCTAssertTrue(guardrail.check(long, authorText: author).contains(.tooLong))
    }

    func testFallbackQuestionsAlwaysPass() {
        for seed in 0..<8 {
            XCTAssertTrue(guardrail.isAcceptable(FallbackQuestion.make(about: nil, seed: seed), authorText: author))
            XCTAssertTrue(guardrail.isAcceptable(FallbackQuestion.make(about: "the island", seed: seed), authorText: author))
        }
    }
}

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
