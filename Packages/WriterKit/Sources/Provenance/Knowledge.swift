import Foundation
import WriterCore

/// Where a piece of knowledge came from: an exact quote in one paragraph of
/// one document (or one turn of a conversation). Every established fact must
/// carry at least one of these, and the quote must really be there.
public struct SourceRef: Codable, Hashable, Sendable {
    public enum Origin: String, Codable, Sendable { case note, conversation }
    public var origin: Origin
    public var documentID: UUID
    public var paragraphID: UUID
    /// Verbatim text from the source. Verified against the source before a
    /// fact is accepted, so a model can't cite something that isn't there.
    public var quote: String

    public init(origin: Origin = .note, documentID: UUID, paragraphID: UUID, quote: String) {
        self.origin = origin; self.documentID = documentID
        self.paragraphID = paragraphID; self.quote = quote
    }
}

/// How sure the record is. There is deliberately no "inferred" status that
/// could pass for established: anything the author didn't state is either
/// speculation the author wrote as such, or unknown.
public enum Certainty: String, Codable, Sendable {
    /// The author stated it as true in their writing.
    case established
    /// The author wrote it as a possibility ("maybe", "might", "I'm not sure if").
    case speculative
}

/// One statement about an entity: (subject, attribute) -> value.
/// An attribute with no fact is *unknown*; the system never fills it in.
public struct Fact: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var subject: String          // "Mara", "the lighthouse"
    public var attribute: String        // "hair colour", "located in"
    public var value: String            // as the author wrote it
    public var certainty: Certainty
    public var sources: [SourceRef]

    public init(id: UUID = UUID(), subject: String, attribute: String, value: String,
                certainty: Certainty, sources: [SourceRef]) {
        self.id = id; self.subject = subject; self.attribute = attribute
        self.value = value; self.certainty = certainty; self.sources = sources
    }
}

/// A relationship between two entities, with the same provenance rules.
public struct Relationship: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var from: String, relation: String, to: String
    public var certainty: Certainty
    public var sources: [SourceRef]
    public init(id: UUID = UUID(), from: String, relation: String, to: String,
                certainty: Certainty, sources: [SourceRef]) {
        self.id = id; self.from = from; self.relation = relation; self.to = to
        self.certainty = certainty; self.sources = sources
    }
}

/// Why a candidate was rejected. Rejections are kept for diagnostics, never
/// silently "fixed" by guessing.
public enum Rejection: Error, Equatable, Sendable {
    case noSource
    case quoteNotFound(String)
    case valueNotInQuote(String)
    case speculationMarkedEstablished(String)
}

/// Gatekeeper between model output and the knowledge base. Model output is a
/// *candidate*; it becomes knowledge only if it passes these deterministic checks.
public struct ProvenanceValidator: Sendable {
    /// Words that mark the author's own uncertainty. A fact whose quote contains
    /// one of these can't be recorded as established.
    public static let hedges = ["maybe", "perhaps", "might", "possibly", "probably",
                                "i think", "not sure", "could be", "or maybe", "what if", "?"]

    public init() {}

    public func validate(_ fact: Fact, in documents: [Document]) -> Result<Fact, Rejection> {
        guard !fact.sources.isEmpty else { return .failure(.noSource) }
        for src in fact.sources {
            guard let text = paragraphText(src, documents) else { return .failure(.quoteNotFound(src.quote)) }
            guard Self.normalized(text).contains(Self.normalized(src.quote)) else {
                return .failure(.quoteNotFound(src.quote))
            }
        }
        // The value must be the author's words, not a paraphrase that could
        // smuggle in detail ("red" must appear, not "crimson").
        let quotes = fact.sources.map { Self.normalized($0.quote) }.joined(separator: " ")
        guard quotes.contains(Self.normalized(fact.value)) else {
            return .failure(.valueNotInQuote(fact.value))
        }
        if fact.certainty == .established, Self.hedges.contains(where: { quotes.contains($0) }) {
            return .failure(.speculationMarkedEstablished(fact.value))
        }
        return .success(fact)
    }

    public func validate(_ rel: Relationship, in documents: [Document]) -> Result<Relationship, Rejection> {
        let asFact = Fact(subject: rel.from, attribute: rel.relation, value: rel.to,
                          certainty: rel.certainty, sources: rel.sources)
        return validate(asFact, in: documents).map { _ in rel }
    }

    private func paragraphText(_ src: SourceRef, _ docs: [Document]) -> String? {
        docs.first { $0.id == src.documentID }?.paragraph(src.paragraphID)?.text
    }

    static func normalized(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// The knowledge base for one body of work. Lookups that have no fact return
/// `.unknown` explicitly, so callers (the illustrator, the companion) are
/// forced to handle "the author hasn't said".
public struct KnowledgeBase: Codable, Sendable {
    public private(set) var facts: [Fact] = []
    public private(set) var relationships: [Relationship] = []
    public private(set) var rejected: [String] = []

    public init() {}

    public enum Answer: Equatable, Sendable {
        case established(String, [SourceRef])
        case speculative([String], [SourceRef])
        case unknown
    }

    /// Adds candidates that pass validation; returns how many were rejected.
    @discardableResult
    public mutating func ingest(facts candidates: [Fact], relationships rels: [Relationship] = [],
                                from documents: [Document]) -> Int {
        let v = ProvenanceValidator()
        var dropped = 0
        for c in candidates {
            switch v.validate(c, in: documents) {
            case .success(let f): facts.removeAll { $0.subject == f.subject && $0.attribute == f.attribute && $0.value == f.value }; facts.append(f)
            case .failure(let r): dropped += 1; rejected.append("\(c.subject).\(c.attribute): \(r)")
            }
        }
        for r in rels {
            switch v.validate(r, in: documents) {
            case .success(let ok): relationships.append(ok)
            case .failure(let why): dropped += 1; rejected.append("\(r.from) \(r.relation) \(r.to): \(why)")
            }
        }
        return dropped
    }

    /// Drop everything sourced from a paragraph (the author edited or deleted it).
    public mutating func invalidate(paragraph id: UUID) {
        facts.removeAll { $0.sources.contains { $0.paragraphID == id } }
        relationships.removeAll { $0.sources.contains { $0.paragraphID == id } }
    }

    public func answer(subject: String, attribute: String) -> Answer {
        let matches = facts.filter {
            $0.subject.caseInsensitiveCompare(subject) == .orderedSame
                && $0.attribute.caseInsensitiveCompare(attribute) == .orderedSame
        }
        if let f = matches.first(where: { $0.certainty == .established }) { return .established(f.value, f.sources) }
        let spec = matches.filter { $0.certainty == .speculative }
        if !spec.isEmpty { return .speculative(spec.map(\.value), spec.flatMap(\.sources)) }
        return .unknown
    }

    public func facts(about subject: String) -> [Fact] {
        facts.filter { $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
    }
}
