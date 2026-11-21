import Foundation

/// Every model the app may download, with the licence facts we validated
/// before integrating it (see docs/models.md). The app refuses to download a
/// model whose entry lacks a licence or a pinned checksum.
public struct ModelDescriptor: Identifiable, Hashable, Sendable {
    public enum Role: String, Sendable { case embedding, reranking, conversation, extraction, illustration, illustrationControl }
    public enum Runtime: String, Sendable { case llamaCpp, coreMLDiffusion, appleFoundationModels }

    public var id: String
    public var displayName: String
    public var role: Role
    public var runtime: Runtime
    /// nil for system models that ship with iOS.
    public var downloadURL: URL?
    /// SHA-256 of the downloaded file; nil until pinned (download disabled).
    public var sha256: String?
    public var approximateBytes: Int64
    public var license: String
    public var licenseURL: URL
    /// Obligations we must meet when the app downloads and uses it.
    public var obligations: [String]

    public var isDownloadable: Bool { downloadURL != nil && sha256 != nil }
}

public enum ModelCatalog {
    public static let all: [ModelDescriptor] = [
        ModelDescriptor(
            id: "qwen3-embedding-0.6b-q8",
            displayName: "Qwen3-Embedding 0.6B",
            role: .embedding, runtime: .llamaCpp,
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/main/Qwen3-Embedding-0.6B-Q8_0.gguf"),
            sha256: nil,
            approximateBytes: 639_000_000,
            license: "Apache-2.0",
            licenseURL: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!,
            obligations: ["Include Apache-2.0 notice in Acknowledgements"]),
        ModelDescriptor(
            id: "qwen3-reranker-0.6b-q8",
            displayName: "Qwen3-Reranker 0.6B (optional)",
            role: .reranking, runtime: .llamaCpp,
            downloadURL: nil, sha256: nil,
            approximateBytes: 640_000_000,
            license: "Apache-2.0",
            licenseURL: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!,
            obligations: ["Include Apache-2.0 notice in Acknowledgements"]),
        ModelDescriptor(
            id: "qwen3.5-4b-q4km",
            displayName: "Qwen3.5 4B",
            role: .conversation, runtime: .llamaCpp,
            downloadURL: nil, sha256: nil,       // pinned once a GGUF build is verified on device
            approximateBytes: 2_700_000_000,
            license: "Apache-2.0",
            licenseURL: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!,
            obligations: ["Include Apache-2.0 notice in Acknowledgements"]),
        ModelDescriptor(
            id: "apple-foundation-model",
            displayName: "Apple on-device model",
            role: .extraction, runtime: .appleFoundationModels,
            downloadURL: nil, sha256: nil,
            approximateBytes: 0,
            license: "Apple SDK (system framework)",
            licenseURL: URL(string: "https://developer.apple.com/foundation-models-framework/")!,
            obligations: ["Use SystemLanguageModel only; never a server model"]),
        ModelDescriptor(
            id: "sd15-coreml-controlnet",
            displayName: "Stable Diffusion 1.5 (Core ML)",
            role: .illustration, runtime: .coreMLDiffusion,
            downloadURL: nil, sha256: nil,
            approximateBytes: 2_100_000_000,
            license: "CreativeML OpenRAIL-M",
            licenseURL: URL(string: "https://huggingface.co/spaces/CompVis/stable-diffusion-license")!,
            obligations: [
                "Pass the licence's use restrictions (Attachment A) to users before first download",
                "Include a copy of the licence in the app",
            ]),
        ModelDescriptor(
            id: "controlnet11-scribble-coreml",
            displayName: "ControlNet 1.1 Scribble (Core ML)",
            role: .illustrationControl, runtime: .coreMLDiffusion,
            downloadURL: nil, sha256: nil,
            approximateBytes: 720_000_000,
            license: "CreativeML OpenRAIL-M",
            licenseURL: URL(string: "https://huggingface.co/lllyasviel/ControlNet-v1-1")!,
            obligations: ["Same as Stable Diffusion 1.5"]),
    ]
}

/// A loaded model that can release its memory.
public protocol ResidentModel: AnyObject, Sendable {
    var footprintBytes: Int64 { get }
    func unload() async
}

/// Keeps at most a memory budget's worth of models resident and unloads the
/// least recently used first, so a heavy model (diffusion) can evict all the others.
public actor ModelResidency {
    private var loaded: [(id: String, model: any ResidentModel, lastUse: Date)] = []
    public let budgetBytes: Int64

    public init(budgetBytes: Int64) { self.budgetBytes = budgetBytes }

    public var residentIDs: [String] { loaded.map(\.id) }

    /// Returns the resident model, loading it with `load` if needed.
    public func use(_ id: String, load: @Sendable () async throws -> any ResidentModel) async throws -> any ResidentModel {
        if let i = loaded.firstIndex(where: { $0.id == id }) {
            loaded[i].lastUse = Date()
            return loaded[i].model
        }
        let model = try await load()
        while !loaded.isEmpty, total + model.footprintBytes > budgetBytes {
            await evictOldest()
        }
        loaded.append((id, model, Date()))
        return model
    }

    public func unloadAll() async {
        for m in loaded { await m.model.unload() }
        loaded.removeAll()
    }

    public func unload(_ id: String) async {
        guard let i = loaded.firstIndex(where: { $0.id == id }) else { return }
        await loaded[i].model.unload()
        loaded.remove(at: i)
    }

    private var total: Int64 { loaded.reduce(0) { $0 + $1.model.footprintBytes } }

    private func evictOldest() async {
        guard let i = loaded.indices.min(by: { loaded[$0].lastUse < loaded[$1].lastUse }) else { return }
        await loaded[i].model.unload()
        loaded.remove(at: i)
    }
}
