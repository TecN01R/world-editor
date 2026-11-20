import SwiftUI

struct RootView: View {
    @Environment(Library.self) private var library
    @State private var focusMode = UserDefaults.standard.bool(forKey: "startInFocus")
    @State private var showModels = false
    @Namespace private var glass

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
            // System Liquid Glass controls, morphing between modes.
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if !focusMode {
                        Button { showModels = true } label: {
                            Image(systemName: "cpu").frame(width: 22, height: 22)
                        }
                        .buttonStyle(.glass)
                        .glassEffectID("models", in: glass)
                        .accessibilityLabel("On-device models")
                    }
                    Button {
                        withAnimation(.smooth(duration: 0.3)) { focusMode.toggle() }
                    } label: {
                        Label(focusMode ? "Page" : "Focus",
                              systemImage: focusMode ? "text.alignleft" : "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("mode", in: glass)
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                }
            }
            .padding(.trailing, 12)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showModels) { ModelsView() }
    }
}
