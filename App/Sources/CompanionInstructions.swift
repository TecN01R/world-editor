import Guardrails
import SwiftUI

/// The companion's instructions and example exchanges, for the author to change (Kevin,
/// 2026-11-25: "a settings panel for me to modify instructions myself"), from the companion's
/// menu: iOS's own form and text editors. What's shown at first is what the companion reads
/// now; Done keeps it, from the next reply on; Restore Defaults puts back the app's own.
/// Text left as the app's is kept as the app's, so it follows the app's when they change.
struct CompanionInstructions: View {
    @Environment(Companion.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @State private var instructions = ""
    @State private var examples = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 320)
                        .accessibilityLabel("Instructions")
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("Who the companion is and how it replies, read before every reply. Whatever they say, it can’t write into your pages.")
                }
                Section {
                    TextEditor(text: $examples)
                        .frame(minHeight: 240)
                        .accessibilityLabel("Examples")
                } header: {
                    Text("Examples")
                } footer: {
                    Text("Sample exchanges showing the kind of reply you want. Leave it empty for none.")
                }
                Section {
                    Button("Restore Defaults") {
                        (instructions, examples) = (companion.defaultTexts.instructions, companion.defaultTexts.examples)
                    }
                    .disabled(instructions == companion.defaultTexts.instructions && examples == companion.defaultTexts.examples)
                }
            }
            .navigationTitle("Companion Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark", action: save) }
            }
        }
        .interactiveDismissDisabled(changed)   // a swipe doesn't throw away what's typed
        .onAppear {
            guard !loaded else { return }
            loaded = true
            instructions = companion.texts.instructions ?? companion.defaultTexts.instructions
            examples = companion.texts.examples ?? companion.defaultTexts.examples
        }
    }

    /// Something differs from what the companion reads now.
    private var changed: Bool {
        loaded && (instructions != (companion.texts.instructions ?? companion.defaultTexts.instructions)
            || examples != (companion.texts.examples ?? companion.defaultTexts.examples))
    }

    private func save() {
        let defaults = companion.defaultTexts
        companion.texts = CompanionPrompt.Texts(instructions: instructions == defaults.instructions ? nil : instructions,
                                                examples: examples == defaults.examples ? nil : examples)
        dismiss()
    }
}
