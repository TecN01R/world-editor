#if DEBUG
import SwiftUI

/// Instructions of the author's own for the companion (Kevin, 2026-11-25: "a settings panel for
/// me to modify instructions myself"; debug builds only), from the companion's menu: iOS's own
/// form and text editor. None by default: the companion is the model stock (Kevin, 2026-11-25).
/// What's shown at first is what the companion reads now; Done keeps it, from the next reply on;
/// Clear goes back to none.
struct CompanionInstructions: View {
    @Environment(Companion.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @State private var instruction = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $instruction)
                        .frame(minHeight: 240)
                        .accessibilityLabel("Instructions")
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("None by default: the companion is the model as its maker ships it. Anything here is read before every reply. Whatever it says, it can’t write into your pages.")
                }
                Section {
                    Button("Clear", role: .destructive) { instruction = "" }
                        .disabled(instruction.isEmpty)
                }
            }
            .navigationTitle("Companion Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark", action: save) }
            }
        }
        .interactiveDismissDisabled(loaded && instruction != (companion.instruction ?? ""))   // a swipe doesn't throw away what's typed
        .onAppear {
            guard !loaded else { return }
            loaded = true
            instruction = companion.instruction ?? ""
        }
    }

    private func save() {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        companion.instruction = text.isEmpty ? nil : text
        dismiss()
    }
}
#endif
