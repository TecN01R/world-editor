import Foundation
import WriterCore
import Provenance
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
@Generable
struct ExtractedStatement {
    @Guide(description: "The person, place, object or idea the sentence is about, exactly as written.")
    var subject: String
    @Guide(description: "What aspect is described, in two or three plain words, e.g. hair colour, location, age.")
    var attribute: String
    @Guide(description: "The author's exact words for the value. Copy them; never rephrase or add detail.")
    var value: String
    @Guide(description: "The shortest exact quote from the paragraph that states this. Copy it character for character.")
    var quote: String
    @Guide(description: "True if the author wrote it as uncertain (maybe, might, perhaps, a question).")
    var speculative: Bool
}

@Generable
struct ExtractionResult {
    @Guide(description: "Only what the paragraph explicitly states. Leave anything not stated out entirely.", .maximumCount(12))
    var statements: [ExtractedStatement]
}

/// Extracts what the author has *stated* from their pages, using Apple's
/// on-device model. Output is only a candidate list; `KnowledgeBase.ingest`
/// keeps a fact only if its quote really appears in the paragraph and its
/// value is the author's own words.
struct FactExtractor {
    static let instructions = """
    You record what an author has written about their own fictional world. \
    Copy their words exactly. Never infer, guess, complete, embellish or add \
    anything that is not literally stated in the paragraph. If something is not \
    stated, it is not recorded. Mark anything the author expresses as uncertain \
    as speculative.
    """

    /// Uses the on-device system model only. Server-backed models (which the
    /// iOS 27 framework can also reach) are never used.
    func extract(from paragraph: Paragraph, in document: WriterCore.Document) async throws -> [Fact] {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return [] }
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(
            to: "Paragraph:\n\(paragraph.text)",
            generating: ExtractionResult.self,
            options: GenerationOptions(sampling: .greedy))
        return response.content.statements.map {
            Fact(subject: $0.subject, attribute: $0.attribute, value: $0.value,
                 certainty: $0.speculative ? .speculative : .established,
                 sources: [SourceRef(documentID: document.id, paragraphID: paragraph.id, quote: $0.quote)])
        }
    }
}
#endif
