import SwiftUI
import WriterCore

/// Pages list beside the open page. Folded, it's a stack (list, then page);
/// unfolded, the list sits alongside. Controls are standard toolbar items, so
/// on iPhone Duo the system lays them out in the side column.
struct RootView: View {
    @Environment(Library.self) private var library
    @State private var column: NavigationSplitViewColumn = Screenshots.opensList ? .sidebar : .detail
    @State private var focusMode = UserDefaults.standard.bool(forKey: "startInFocus")

    var body: some View {
        @Bindable var library = library
        if UserDefaults.standard.bool(forKey: "iconGallery") { IconGallery() } else {
        // Focus mode takes the whole display: the pages list steps aside when unfolded.
        NavigationSplitView(columnVisibility: .constant(focusMode ? .detailOnly : .automatic),
                            preferredCompactColumn: $column) {
            PageList(selection: $library.selection) {
                library.newPage()
                column = .detail
            }
        } detail: {
            if let id = library.selection {
                EditorView(focusMode: $focusMode).id(id)
            } else {
                ContentUnavailableView("No Page Open", systemImage: "doc.text",
                                       description: Text("Choose a page or start a new one."))
            }
        }
        }
    }
}

/// TEMPORARY: candidate symbols for the Focus button, for Kevin to choose from.
private struct IconGallery: View {
    static let symbols = ["text.viewfinder", "scope", "viewfinder", "eye", "text.magnifyingglass",
                          "doc.text.viewfinder", "rectangle.and.text.magnifyingglass", "text.page",
                          "book.pages", "smallcircle.filled.circle", "circle.circle", "rectangle.center.inset.filled"]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 22) {
            ForEach(Array(Self.symbols.enumerated()), id: \.offset) { i, name in
                VStack(spacing: 8) {
                    Image(systemName: name).font(.system(size: 34)).frame(height: 44)
                    Text("\(i + 1). \(name)").font(.caption).multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .frame(maxHeight: .infinity, alignment: .top)
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

    var body: some View {
        ZStack {
            if focusMode {
                FocusEditor()
                    .ignoresSafeArea(.container, edges: .bottom)
                    .transition(.opacity)
            } else {
                PageEditor()
                    .ignoresSafeArea(.keyboard)   // text scrolls behind the glass format bar, as in Notes
                    .transition(.opacity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.smooth(duration: 0.3)) { focusMode.toggle() }
                } label: {
                    Label(focusMode ? "Edit" : "Focus",
                          systemImage: focusMode ? "doc.plaintext" : "textformat.size")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}
