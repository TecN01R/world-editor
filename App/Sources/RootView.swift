import SwiftUI

/// Controls are standard toolbar items. On iPhone Duo (iOS 27.1 SDK) the
/// system lays them out in the side column under the status items, sized and
/// spaced like every other app; elsewhere they sit in the navigation bar.
struct RootView: View {
    @Environment(Library.self) private var library
    @State private var focusMode = UserDefaults.standard.bool(forKey: "startInFocus")
    @State private var showModels = false

    var body: some View {
        NavigationStack {
            ZStack {
                if focusMode {
                    FocusEditor()
                        .ignoresSafeArea(.container, edges: .bottom)
                        .transition(.opacity)
                } else {
                    PageEditor()
                        .transition(.opacity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.smooth(duration: 0.3)) { focusMode.toggle() }
                    } label: {
                        Label(focusMode ? "Page View" : "Focus",
                              systemImage: focusMode ? "text.alignleft" : "arrow.up.left.and.arrow.down.right")
                    }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                }
                if !focusMode {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showModels = true } label: {
                            Label("On-device Models", systemImage: "cpu")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showModels) { ModelsView() }
    }
}
