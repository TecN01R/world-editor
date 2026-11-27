import SwiftUI

/// The author's standing instructions for the companion (`Instructions`; Kevin, 2026-11-25:
/// "keep the prompting but keep it blank and the user can fill in instructions over time"), from
/// the companion's menu or the note under a reply that added one: iOS's own form and text
/// editor. Blank at first, so the model runs stock; the companion adds to them when the author
/// tells it how to reply. What's shown is what it reads now; Done keeps it, from the next reply
/// on; Clear empties it.
struct CompanionInstructions: View {
    @Environment(Companion.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @State private var instructions = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 240)
                        .accessibilityLabel("Instructions")
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("The companion reads these before every reply, and adds to them when you tell it how to reply from now on. Blank, it’s the model as its maker ships it.")
                }
                Section {
                    Button("Clear", role: .destructive) { instructions = "" }
                        .disabled(instructions.isEmpty)
                }
            }
            .navigationTitle("Companion Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark", action: save) }
            }
        }
        .interactiveDismissDisabled(loaded && instructions != (companion.instructions ?? ""))   // a swipe doesn't throw away what's typed
        .onAppear {
            guard !loaded else { return }
            loaded = true
            instructions = companion.instructions ?? ""
        }
    }

    private func save() {
        let text = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        companion.instructions = text.isEmpty ? nil : text
        dismiss()
    }
}
