import SwiftUI
import ModelCatalog

/// Lists every model the app may use, what it's for, its licence and the
/// obligations that come with it. Nothing downloads until a model's file is
/// pinned to a verified checksum.
struct ModelsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Everything runs on this device. Models are downloaded only when you ask, verified, and unloaded from memory when not in use. None of them can change your writing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(ModelCatalog.all) { m in
                    Section(m.displayName) {
                        LabeledContent("Role", value: role(m.role))
                        LabeledContent("Licence", value: m.license)
                        if m.approximateBytes > 0 {
                            LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: m.approximateBytes, countStyle: .file))
                        }
                        LabeledContent("Status", value: status(m))
                        ForEach(m.obligations, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                        Link("Licence text", destination: m.licenseURL).font(.footnote)
                    }
                }
            }
            .navigationTitle("On-device models")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func role(_ r: ModelDescriptor.Role) -> String {
        switch r {
        case .embedding: "Search by meaning"
        case .reranking: "Rank search results"
        case .conversation: "Writing companion"
        case .extraction: "Facts & continuity"
        case .illustration: "Source-grounded illustration"
        case .illustrationControl: "Illustration layout control"
        }
    }

    private func status(_ m: ModelDescriptor) -> String {
        switch m.runtime {
        case .appleFoundationModels: FoundationModelStatus.description
        default: m.isDownloadable ? "Available to download" : "Not yet enabled"
        }
    }
}
