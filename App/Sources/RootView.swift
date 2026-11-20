import SwiftUI

struct RootView: View {
    @Environment(Library.self) private var library
    @State private var focusMode = false
    @State private var showModels = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if focusMode {
                FocusEditor()
                    .ignoresSafeArea(.container, edges: .bottom)
                    .transition(.opacity)
            } else {
                PageEditor()
                    .transition(.opacity)
            }
            HStack(spacing: 8) {
                if !focusMode {
                    Button { showModels = true } label: { Image(systemName: "cpu") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("On-device models")
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { focusMode.toggle() }
                } label: {
                    Label(focusMode ? "Page" : "Focus",
                          systemImage: focusMode ? "text.alignleft" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            .padding(.trailing, 12)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showModels) { ModelsView() }
    }
}
