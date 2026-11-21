import SwiftUI
import WriterCore

/// Pages list beside the open page. Folded, it's a stack (list, then page);
/// unfolded, the list sits alongside. Controls are standard toolbar items, so
/// on iPhone Duo the system lays them out in the side column.
struct RootView: View {
    @Environment(Library.self) private var library
    @State private var column: NavigationSplitViewColumn = Screenshots.opensList ? .sidebar : .detail
    @State private var focusMode = Self.startsInFocus
    @State private var focusControls = false
    @State private var columns: NavigationSplitViewVisibility = Self.startsInFocus ? .detailOnly : .all
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private static var startsInFocus: Bool { UserDefaults.standard.bool(forKey: "startInFocus") }

    /// In Focus mode everything but the writing hides (bars, status, home
    /// indicator, pages list) until a tap outside the text brings it back.
    /// VoiceOver users keep the controls: hidden ones would be unreachable.
    private var chromeHidden: Bool { focusMode && !focusControls && !voiceOver }

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
                EditorView(focusMode: $focusMode, focusControls: $focusControls, chromeHidden: chromeHidden).id(id)
            } else {
                ContentUnavailableView("No Page Open", systemImage: "doc.text",
                                       description: Text("Choose a page or start a new one."))
            }
        }
        // Applied at the root: status bar visibility is decided by the top controller.
        .statusBarHidden(chromeHidden)
        .persistentSystemOverlays(chromeHidden ? .hidden : .automatic)
        // CI shot of revealed controls: reveal after launch, the way a tap would,
        // rather than starting revealed (a path no user ever takes).
        .task {
            guard UserDefaults.standard.bool(forKey: "focusControls") else { return }
            try? await Task.sleep(for: .seconds(1.5))
            focusControls = true
        }
        .onChange(of: focusMode) { _, focus in
            focusControls = false
            withAnimation { columns = focus ? .detailOnly : .all }   // unfolded: list beside the page
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

    var body: some View {
        ZStack {
            if focusMode {
                FocusEditor(showsControls: $focusControls)
                    .ignoresSafeArea()   // the whole display; bars appear over it
                    .transition(.opacity)
            } else {
                PageEditor()
                    .ignoresSafeArea(.keyboard)   // text scrolls behind the glass format bar, as in Notes
                    .transition(.opacity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Focus is a mode you step into, so revealing its controls shows only
        // a close button, as full-screen modes do on iOS; no back arrow or
        // sidebar button. The bar draws over the writing, which ignores the
        // safe area and so never reflows.
        .toolbar(chromeHidden ? .hidden : .automatic, for: .navigationBar)
        .navigationBarBackButtonHidden(focusMode)
        .toolbar(removing: focusMode ? .sidebarToggle : nil)
        .animation(.easeInOut(duration: 0.25), value: chromeHidden)
        .toolbar {
            if focusMode {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close Focus", systemImage: "xmark") {
                        withAnimation(.smooth(duration: 0.3)) { focusMode = false }
                    }
                    .keyboardShortcut(.cancelAction)
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button("Focus", systemImage: "text.viewfinder") {
                        withAnimation(.smooth(duration: 0.3)) { focusMode = true }
                    }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                }
            }
        }
    }
}
