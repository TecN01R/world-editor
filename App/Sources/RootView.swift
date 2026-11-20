import SwiftUI
import WriterCore

/// Pages list beside the open page. Folded, it's a stack (list, then page);
/// unfolded, the list sits alongside. Controls are standard toolbar items, so
/// on iPhone Duo the system lays them out in the side column.
struct RootView: View {
    @Environment(Library.self) private var library
    @State private var column: NavigationSplitViewColumn = Screenshots.opensList ? .sidebar : .detail
    @State private var focusMode = UserDefaults.standard.bool(forKey: "startInFocus")
    @State private var focusControls = UserDefaults.standard.bool(forKey: "focusControls")   // CI shot
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    /// In Focus mode everything but the writing hides (bars, status, home
    /// indicator, pages list) until a tap outside the text brings it back.
    /// VoiceOver users keep the controls: hidden ones would be unreachable.
    private var chromeHidden: Bool { focusMode && !focusControls && !voiceOver }
    @State private var columns: NavigationSplitViewVisibility =
        UserDefaults.standard.bool(forKey: "startInFocus") ? .detailOnly : .automatic

    var body: some View {
        @Bindable var library = library
        // Focus mode takes the whole display: the pages list steps aside when unfolded.
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $column) {
            PageList(selection: $library.selection) {
                library.newPage()
                column = .detail
            }
        } detail: {
            if let id = library.selection {
                EditorView(focusMode: $focusMode, focusControls: $focusControls, chromeHidden: chromeHidden,
                           showPages: showPages).id(id)
            } else {
                ContentUnavailableView("No Page Open", systemImage: "doc.text",
                                       description: Text("Choose a page or start a new one."))
            }
        }
        // Applied at the root: status bar visibility is decided by the top controller.
        .statusBarHidden(chromeHidden)
        .persistentSystemOverlays(chromeHidden ? .hidden : .automatic)
        .onChange(of: focusMode) { _, focus in
            focusControls = false
            withAnimation { columns = focus ? .detailOnly : (columns == .detailOnly ? .automatic : columns) }
        }
    }

    /// Leaves Focus mode for the pages list: back to it when folded, beside the page when unfolded.
    private func showPages() {
        withAnimation(.smooth(duration: 0.3)) {
            columns = .all
            column = .sidebar
            focusMode = false
        }
    }
}

struct PageList: View {
    @Environment(Library.self) private var library
    @Binding var selection: UUID?
    let newPage: () -> Void
    @State private var showModels = false

    var body: some View {
        List(selection: $selection) {
            ForEach(library.pages) { page in
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.heading.isEmpty ? "New Page" : page.heading)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(page.modified, format: .relative(presentation: .named))
                        if !page.preview.isEmpty { Text(page.preview).lineLimit(1) }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { library.delete(page.id) }
                }
            }
        }
        .navigationTitle("Pages")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Page", systemImage: "square.and.pencil", action: newPage)
                    .keyboardShortcut("n")
            }
            // Its own glass capsule, apart from New Page.
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("On-device Models", systemImage: "cpu") { showModels = true }
            }
        }
        .sheet(isPresented: $showModels) { ModelsView() }
    }
}

/// One page, in Edit mode or Focus mode.
struct EditorView: View {
    @Binding var focusMode: Bool
    @Binding var focusControls: Bool
    let chromeHidden: Bool
    let showPages: () -> Void
    @Environment(\.horizontalSizeClass) private var width

    var body: some View {
        ZStack {
            if focusMode {
                FocusEditor(showsControls: $focusControls)
                    .ignoresSafeArea(.container, edges: [.bottom, .trailing])
                    .transition(.opacity)
            } else {
                PageEditor()
                    .ignoresSafeArea(.keyboard)   // text scrolls behind the glass format bar, as in Notes
                    .transition(.opacity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Focus mode never shows the bar (on the Duo, the side column), so
        // nothing reserves space or reflows the text when controls appear.
        .toolbar(focusMode ? .hidden : .automatic, for: .navigationBar)
        .overlay(alignment: .topTrailing) {
            if focusMode && !chromeHidden {
                // Float over the writing when revealed: back to the pages, or out to Edit.
                GlassEffectContainer {
                    VStack(spacing: 12) {
                        Button(action: showPages) {
                            Label("Pages", systemImage: width == .compact ? "chevron.backward" : "sidebar.leading")
                        }
                        Button { withAnimation(.smooth(duration: 0.3)) { focusMode = false } } label: {
                            Label("Edit", systemImage: "doc.plaintext")
                        }
                        .keyboardShortcut("f", modifiers: [.command, .shift])
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.extraLarge)
                }
                .padding(.trailing, 12)
                .padding(.top, 64)
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: chromeHidden)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.smooth(duration: 0.3)) { focusMode = true }
                } label: {
                    Label("Focus", systemImage: "text.viewfinder")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}
