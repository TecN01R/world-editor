import Foundation
import Provenance

/// What an illustration may show, derived only from established facts.
/// Every slot the author hasn't filled stays explicitly unknown, and the
/// renderer must leave it neutral, blank or unfinished.
public struct IllustrationPlan: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable { case character, place, object, scene }

    public struct Slot: Sendable, Equatable {
        public var attribute: String
        /// The author's own words, or nil if unknown.
        public var value: String?
        public var region: Region
    }

    /// Normalised layout region (0...1) the slot governs. Unknown slots become
    /// masked areas that diffusion is not allowed to paint into.
    public struct Region: Sendable, Equatable {
        public var x, y, w, h: Double
    }

    public var kind: Kind
    public var subject: String
    public var slots: [Slot]
    /// Deterministic per subject, so the composition stays put as the author
    /// adds details and the picture fills in rather than reshuffling.
    public var seed: UInt32

    public var completeness: Double {
        slots.isEmpty ? 0 : Double(slots.filter { $0.value != nil }.count) / Double(slots.count)
    }
    public var known: [Slot] { slots.filter { $0.value != nil } }
    public var unknown: [Slot] { slots.filter { $0.value == nil } }

    /// Prompt built only from the author's words. No adjectives are added
    /// except the fixed, content-free style line.
    public var prompt: String {
        let parts = known.compactMap { s in s.value.map { "\(s.attribute): \($0)" } }
        return ([Self.styleLine, subject] + parts).joined(separator: ", ")
    }

    public static let styleLine =
        "restrained ink and wash illustration, muted neutral palette, unfinished study, generous negative space"
    public static let negativePrompt =
        "photorealistic, highly detailed, intricate, ornate, text, logo, watermark, saturated colours, " +
        "busy background, extra objects, extra people, decorations, patterns, jewellery, tattoos"

    /// How far diffusion is allowed to go. Sparse knowledge gives a faint,
    /// mostly unfinished study; more established detail gives a fuller one.
    public var denoiseStrength: Double { 0.35 + 0.45 * completeness }
    public var steps: Int { 12 + Int((18 * completeness).rounded()) }

    /// Attributes a picture of each kind would otherwise have to invent.
    public static let template: [Kind: [(String, Region)]] = [
        .character: [
            ("build", .init(x: 0.25, y: 0.30, w: 0.50, h: 0.65)),
            ("face", .init(x: 0.38, y: 0.08, w: 0.24, h: 0.20)),
            ("hair", .init(x: 0.34, y: 0.02, w: 0.32, h: 0.14)),
            ("clothing", .init(x: 0.26, y: 0.30, w: 0.48, h: 0.55)),
            ("age", .init(x: 0.34, y: 0.02, w: 0.32, h: 0.40)),
            ("posture", .init(x: 0.20, y: 0.25, w: 0.60, h: 0.75)),
        ],
        .place: [
            ("terrain", .init(x: 0, y: 0.60, w: 1, h: 0.40)),
            ("structures", .init(x: 0.15, y: 0.25, w: 0.70, h: 0.45)),
            ("sky", .init(x: 0, y: 0, w: 1, h: 0.30)),
            ("weather", .init(x: 0, y: 0, w: 1, h: 0.45)),
            ("time of day", .init(x: 0, y: 0, w: 1, h: 0.30)),
            ("vegetation", .init(x: 0, y: 0.45, w: 1, h: 0.40)),
        ],
        .object: [
            ("shape", .init(x: 0.25, y: 0.25, w: 0.50, h: 0.50)),
            ("material", .init(x: 0.25, y: 0.25, w: 0.50, h: 0.50)),
            ("colour", .init(x: 0.25, y: 0.25, w: 0.50, h: 0.50)),
            ("size", .init(x: 0.20, y: 0.20, w: 0.60, h: 0.60)),
        ],
        .scene: [
            ("setting", .init(x: 0, y: 0, w: 1, h: 1)),
            ("figures", .init(x: 0.20, y: 0.30, w: 0.60, h: 0.65)),
            ("lighting", .init(x: 0, y: 0, w: 1, h: 0.35)),
            ("action", .init(x: 0.25, y: 0.30, w: 0.50, h: 0.55)),
        ],
    ]

    /// Build from the knowledge base. Speculative facts are *not* drawn.
    public static func make(kind: Kind, subject: String, knowledge: KnowledgeBase) -> IllustrationPlan {
        let slots = (template[kind] ?? []).map { attr, region -> Slot in
            if case .established(let v, _) = knowledge.answer(subject: subject, attribute: attr) {
                return Slot(attribute: attr, value: v, region: region)
            }
            return Slot(attribute: attr, value: nil, region: region)
        }
        return IllustrationPlan(kind: kind, subject: subject, slots: slots, seed: stableSeed(subject))
    }

    static func stableSeed(_ s: String) -> UInt32 {
        // FNV-1a: stable across launches (Swift's Hasher is randomised per process).
        var h: UInt32 = 2166136261
        for b in s.lowercased().utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return h
    }
}
