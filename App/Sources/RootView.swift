import SwiftUI
import UIKit

struct RootView: View {
    @Environment(Library.self) private var library
    @State private var focusMode = UserDefaults.standard.bool(forKey: "startInFocus")
    @State private var showModels = false

    var body: some View {
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
        .overlay { SideRail(focusMode: $focusMode, showModels: $showModels) }
        .sheet(isPresented: $showModels) { ModelsView() }
    }
}

/// App controls live in the Duo's side column, under the system status items,
/// so they never cover the writing. Devices without a side column get the
/// same rail along the trailing edge.
private struct SideRail: View {
    @Binding var focusMode: Bool
    @Binding var showModels: Bool
    @Namespace private var glass

    static let button: CGFloat = 44, spacing: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let column = geo.safeAreaInsets.trailing
            let x = column >= 40 ? geo.size.width + column / 2 : geo.size.width - 28
            let count: CGFloat = focusMode ? 1 : 2
            let height = count * Self.button + (count - 1) * Self.spacing
            let top = Self.statusBarBottom(in: geo) + 12

            GlassEffectContainer(spacing: Self.spacing) {
                VStack(spacing: Self.spacing) {
                    Button {
                        withAnimation(.smooth(duration: 0.3)) { focusMode.toggle() }
                    } label: {
                        Image(systemName: focusMode ? "text.alignleft" : "arrow.up.left.and.arrow.down.right")
                            .frame(width: 22, height: 22)
                    }
                    .glassEffectID("mode", in: glass)
                    .accessibilityLabel(focusMode ? "Page view" : "Focus mode")
                    .keyboardShortcut("f", modifiers: [.command, .shift])

                    if !focusMode {
                        Button { showModels = true } label: {
                            Image(systemName: "cpu").frame(width: 22, height: 22)
                        }
                        .glassEffectID("models", in: glass)
                        .accessibilityLabel("On-device models")
                    }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            .fixedSize()
            .position(x: x, y: top + height / 2)
        }
    }

    /// Bottom of the system status area within this view. On the Duo the
    /// status bar is a strip at the top of the side column.
    @MainActor
    static func statusBarBottom(in geo: GeometryProxy) -> CGFloat {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        let status = scene?.statusBarManager?.statusBarFrame ?? .zero
        return max(12, status.maxY - geo.frame(in: .global).minY)
    }
}
