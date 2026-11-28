import SwiftUI
import DesignTokens
import WriterCore

/// The open page's type and its fields, under the title in Edit mode. The
/// type is a small line under the title, as Contacts puts a company under a
/// name ("Add Type" on a plain page). Fields float on the page, without a
/// card: a quiet name, then its value, stacked when the two columns don't fit.
/// Only fields with something in them show, as Contacts shows a contact (Kevin,
/// 2026-11-24: not every field of a type fits every page); Add Field's menu
/// lists the empty ones. Stock controls throughout, without glass: the HIG
/// keeps Liquid Glass out of the content layer. They sit down the page as where
/// it is read (`EntryView`), and each thing tapped is a touch target tall
/// (`pageKindLine`, `inFactRow`).
struct PageFields: View {
    /// Where the fields end, for the writing under them: how tall they are, and the room to
    /// leave between them and it.
    struct Extent: Equatable {
        var height: CGFloat = 0
        var gapBelow: CGFloat = PageMetrics.aboveWriting
    }

    @Environment(Library.self) private var library
    /// Where it ends, so the writing below starts after it.
    let onExtent: (Extent) -> Void
    /// Empty fields shown anyway until the page closes: picked from Add Field's menu,
    /// added to the type here, or emptied here (so none vanishes under the cursor).
    @State private var shown: Set<UUID> = []
    @FocusState private var focused: UUID?

    var body: some View {
        let page = library.document
        let type = library.type(of: page)
        let all = library.fields(of: page)
        let filled = Set(all.lazy.map(\.id).filter { page.values[$0] != nil })
        let visible = filled.union(shown)
        let fields = all.filter { visible.contains($0.id) }
        // The writing starts `aboveWriting` under the last row; under the kind's line alone,
        // which keeps part of that room under itself (`pageKindLine`).
        let gapBelow = type == nil ? PageMetrics.kindLineToWriting : PageMetrics.aboveWriting
        VStack(alignment: .leading, spacing: 0) {
            typeMenu(Label {
                if let type { Text(type.name) } else { Text("Add Type") }
            } icon: {
                Image(systemName: "square.text.square")
            })
            if let type {
                if !fields.isEmpty {
                    ViewThatFits(in: .horizontal) {   // HIG layout: stack only where the columns don't fit
                        // Each row a touch target tall, its name and value centred on it.
                        Grid(alignment: .leading, horizontalSpacing: PageMetrics.factColumnSpacing,
                             verticalSpacing: PageMetrics.factRowSpacing) {
                            ForEach(fields) { field in
                                GridRow { name(field); valueView(field) }
                                    .modifier(FieldRow(field: field, type: type))
                            }
                        }
                        VStack(alignment: .leading, spacing: PageMetrics.factRowSpacing) {
                            ForEach(fields) { field in
                                VStack(alignment: .leading, spacing: Spacing.tight) {
                                    name(field, alignment: .bottomLeading)   // by its own value
                                    valueView(field)
                                }
                                .modifier(FieldRow(field: field, type: type))
                            }
                        }
                    }
                }
                addField(type, empty: all.filter { !visible.contains($0.id) })   // the last row
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: filled, initial: true) { shown.formUnion(filled) }
        .onChange(of: type) { old, new in   // a field just added to this type, not a type just chosen
            if let old, let new, old.id == new.id { shown.formUnion(Set(new.fields).subtracting(old.fields)) }
        }
        // Not animated: the page's writing below moves to the fields' new height at once, so
        // rows growing or fading in overlapped it until they settled.
        .fixedSize(horizontal: false, vertical: true)   // its own height, whatever the frame
        .onGeometryChange(for: Extent.self) { Extent(height: $0.size.height, gapBelow: gapBelow) } action: { onExtent($0) }
    }

    /// Add Field, a row under the fields: a menu of the type's empty fields (one picked shows,
    /// ready to fill in), then New Field…; just New Field when none is empty.
    @ViewBuilder private func addField(_ type: PageType, empty: [FieldDefinition]) -> some View {
        let newField = { library.fieldsRequest = .addField(type: type.id) }
        let label = Label("Add Field", systemImage: "plus").role(.label).inFactRow()
        if empty.isEmpty {
            Button(action: newField) { label }
        } else {
            Menu {
                ForEach(empty) { field in
                    Button(field.name) {
                        shown.insert(field.id)
                        Task { focused = field.id }   // once its row exists
                    }
                }
                Divider()
                Button("New Field…", systemImage: "plus", action: newField)
            } label: {
                label
            }
        }
    }

    private func typeMenu(_ label: some View) -> some View {
        Menu {
            // Chooses this page's type, ticked; types are renamed and deleted
            // in the pages list.
            Picker("Type", selection: Binding { library.document.type } set: { new in library.update { $0.type = new } }) {
                ForEach(library.schema.types) { Text($0.name).tag(Optional($0.id)) }   // menus keep the system font
                Text("No Type").tag(UUID?.none)
            }
            Button("New Type…", systemImage: "plus") { library.fieldsRequest = .newType }
            // Removing, reordering and editing a type's fields, for all its pages (Kevin,
            // 2026-11-24: removing one was hidden in a field name's long-press menu).
            if let type = library.type(of: library.document) {
                Button("Edit \(type.name) Fields…", systemImage: "list.bullet") {
                    library.fieldsRequest = .editFields(type: type.id)
                }
            }
        } label: {
            label.role(.label).pageKindLine().contentShape(.rect)
        }
        .accessibilityLabel("Type")
        .sensoryFeedback(.selection, trigger: library.document.type)
    }

    /// The field's name: tap to edit the field (Kevin, 2026-11-24); hold for the row's
    /// menu, which also removes it from the type.
    private func name(_ field: FieldDefinition, alignment: Alignment = .leading) -> some View {
        Button { library.fieldsRequest = .editField(field.id) } label: {
            Text(field.name).role(.label).inFactRow(alignment: alignment)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(field.name)
        .accessibilityHint("Edits this field. Touch and hold for more.")
    }

    private func valueView(_ field: FieldDefinition) -> some View {
        FieldValueView(field: field, value: value(field), focused: $focused, inRow: true)
            .inFactRow()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func value(_ field: FieldDefinition) -> Binding<FieldValue?> {
        Binding { library.document.values[field.id] } set: { value in library.update { $0.values[field.id] = value } }
    }
}

/// A field row's menu: edit, or remove from the type.
private struct FieldRow: ViewModifier {
    @Environment(Library.self) private var library
    let field: FieldDefinition
    let type: PageType

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Edit Field…", systemImage: "pencil") { library.fieldsRequest = .editField(field.id) }
                Button("Remove from \(type.name)", systemImage: "minus.circle", role: .destructive) {
                    library.remove(field.id, from: type.id)
                }
            }
    }
}

/// A field's value: the standard control for its kind, without its label
/// (the name sits beside it).
private struct FieldValueView: View {
    @Environment(Library.self) private var library
    let field: FieldDefinition
    @Binding var value: FieldValue?
    let focused: FocusState<UUID?>.Binding
    /// In a fact's row on a page, where each of its buttons and menus is a row tall to the
    /// touch. A sample of the control (the Kind picker's) keeps its own size.
    var inRow = false

    var body: some View {
        switch field.kind {
        case .text:
            TextField(field.name, text: text, prompt: Text("Add").font(.body))
                .role(.value)
                .focused(focused, equals: field.id)
        case .longText:
            TextField(field.name, text: text, prompt: Text("Add").font(.body), axis: .vertical)
                .role(.value)
                .focused(focused, equals: field.id)
        case .number:
            TextField(field.name, value: number, format: .number, prompt: Text("Add").font(.body))
                .role(.value)
                .keyboardType(.decimalPad)
                .focused(focused, equals: field.id)
        case .date:
            if case .date(let date)? = value {
                DatePicker(field.name, selection: Binding { date } set: { value = .date($0) }, displayedComponents: .date)
                    .labelsHidden()
                    .sensoryFeedback(.selection, trigger: date)
            } else {
                Button { value = .date(Date()) } label: { target(Text("Add Date")) }
            }
        case .choice:
            dropdown(text, current: text.wrappedValue.isEmpty ? nil : text.wrappedValue) {
                Text("None").tag("")
                ForEach(field.options, id: \.self) { Text($0).tag($0) }
            }
        case .toggle:
            Toggle(field.name, isOn: Binding { if case .toggle(true)? = value { true } else { false } } set: { value = .toggle($0) })
                .labelsHidden()
                .stockSwitch()   // iOS's own colour when on: in white, as the other controls are, on looked like off
                .sensoryFeedback(.selection, trigger: value)
        case .page:
            HStack(spacing: Spacing.gap) {
                let name = page.wrappedValue.flatMap { id in library.pages.first { $0.id == id }?.heading }
                dropdown(page, current: name) {
                    Text("None").tag(UUID?.none)
                    ForEach(candidates) { Text($0.heading).tag(Optional($0.id)) }
                } more: {
                    Button("New \(library.schema.type(field.pageType)?.name ?? "Page")…", systemImage: "plus") {
                        library.fieldsRequest = .newPage(field: field.id)
                    }
                }
                if let id = page.wrappedValue {
                    Button { library.selection = id } label: {
                        target(Label("Open", systemImage: "arrow.up.right").labelStyle(.iconOnly))
                    }
                }
            }
        }
    }

    /// A button's or menu's label: a row tall to the touch where it's in a fact's row.
    @ViewBuilder private func target(_ label: some View) -> some View {
        if inRow { label.inFactRow() } else { label }
    }

    /// A pull-down like a menu-style Picker (value in the tint, white here, per
    /// the HIG), but its value stays on one line (truncated), so a long page
    /// name never wraps the row. `current` is the user's value, nil for none.
    private func dropdown<Value: Hashable, More: View>(_ selection: Binding<Value>, current: String?,
                                                      @ViewBuilder options: () -> some View,
                                                      @ViewBuilder more: () -> More = { EmptyView() }) -> some View {
        Menu {
            Picker(field.name, selection: selection, content: options).pickerStyle(.inline)
            more()
        } label: {
            target(HStack(spacing: Spacing.tight) {
                if let current { Text(current).role(.value).lineLimit(1) } else { Text("Choose") }
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            })
        }
        .sensoryFeedback(.selection, trigger: selection.wrappedValue)
        .accessibilityLabel(field.name)
        .accessibilityValue(current ?? "None")
    }

    /// Pages this field may link to: of its type, if it names one.
    private var candidates: [WriterCore.Document] {
        library.pages.filter { page in
            page.id != library.document.id && !page.heading.isEmpty
                && (field.pageType == nil || page.type == field.pageType)
        }
    }

    private var text: Binding<String> {
        Binding { if case .text(let s)? = value { s } else { "" } } set: { value = $0.isEmpty ? nil : .text($0) }
    }

    private var number: Binding<Double?> {
        Binding { if case .number(let n)? = value { n } else { nil } } set: { value = $0.map(FieldValue.number) }
    }

    private var page: Binding<UUID?> {
        Binding { if case .page(let id)? = value { id } else { nil } } set: { value = $0.map(FieldValue.page) }
    }
}

/// A type's fields, from the type line's menu: stock list editing. Swipe or Edit
/// to remove one from every page of the type (what's filled in stays saved, and
/// comes back if it's added again), drag to reorder, tap to edit, Add Field below.
struct TypeFieldsSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let type: UUID
    @State private var editing: FieldDefinition?
    @State private var adding = false

    var body: some View {
        let type = library.schema.type(type)
        let fields = library.schema.fields(of: type)
        NavigationStack {
            List {
                Section {
                    ForEach(fields) { field in
                        Button { editing = field } label: {
                            LabeledContent(field.name) { Text(field.kind.label) }
                        }
                        .tint(.primary)
                        .accessibilityHint("Edits this field.")
                    }
                    .onDelete { offsets in
                        for i in offsets { library.remove(fields[i].id, from: self.type) }
                    }
                    .onMove { library.moveFields(in: self.type, from: $0, to: $1) }
                } footer: {
                    let name = type?.name ?? ""
                    if fields.isEmpty {
                        Text("Add a field to give every \(name) page a place for it.")
                    } else {
                        Text("Removing a field takes it off every \(name) page. What's filled in is kept, and comes back if you add the field again.")
                    }
                }
                Section {
                    Button("Add Field", systemImage: "plus") { adding = true }
                }
            }
            .lookBackground()
            .navigationTitle("\(type?.name ?? "") Fields")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Changes apply at once, so Close (as Mentions), and Edit for removing and reordering.
                ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
            .toolbarVerticalBehavior(.disabled)   // its bar across the top, not in the folded Duo's side column
            .sheet(item: $editing) { FieldSheet(editing: $0) }
            .sheet(isPresented: $adding) { FieldSheet(type: self.type) }
        }
    }
}

/// Adding a field to a type, either one already shared by other types or a
/// new one; or, given `editing`, changing a shared field for every type.
struct FieldSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let type: UUID?
    let editing: FieldDefinition?
    @State private var name = ""
    @State private var kind = FieldDefinition.Kind.text
    @State private var options: [String] = [""]
    @State private var pageType: UUID?

    init(type: UUID? = nil, editing: FieldDefinition? = nil) {
        self.type = type
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _kind = State(initialValue: editing?.kind ?? .text)
        _options = State(initialValue: (editing?.options ?? []) + [""])
        _pageType = State(initialValue: editing?.pageType)
    }

    var body: some View {
        NavigationStack {
            Form {
                if editing == nil, !shared.isEmpty {
                    Section("Shared Fields") {
                        ForEach(shared) { field in
                            Button { add(field) } label: {
                                LabeledContent(field.name) { Text(field.kind.label) }
                            }
                            .tint(.primary)
                        }
                    }
                }
                Section(editing == nil ? "New Field" : "Field") {
                    TextField("Name", text: $name)
                }
                // Its own section, titled Kind; each kind shows a sample of
                // how a page shows it.
                Picker("Kind", selection: $kind) {
                    ForEach(FieldDefinition.Kind.allCases, id: \.self) { KindRow(kind: $0).tag($0) }
                }
                .pickerStyle(.inline)
                .disabled(editing != nil)   // values already saved keep their kind
                if kind == .page {
                    Section {
                        Picker("Pages of Type", selection: $pageType) {
                            Text("Any").tag(UUID?.none)
                            ForEach(library.schema.types) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
                if kind == .choice {
                    Section("Choices") {
                        ForEach(options.indices, id: \.self) { i in TextField("Choice", text: $options[i]).font(.authored(.body)) }
                        Button("Add Choice", systemImage: "plus") { options.append("") }
                    }
                }
            }
            .lookBackground()
            .navigationTitle(editing == nil ? "Add Field" : "Edit Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", action: save).disabled(trimmed(name).isEmpty)
                }
            }
            .toolbarVerticalBehavior(.disabled)   // its bar across the top, not in the folded Duo's side column
        }
        .presentationDetents([.medium, .large])
    }

    /// Shared fields this type doesn't have yet.
    private var shared: [FieldDefinition] {
        let has = library.schema.type(type)?.fields ?? []
        return library.schema.fields.filter { !has.contains($0.id) }
    }

    private func add(_ field: FieldDefinition) {
        if let type { library.add(field, to: type) }
        dismiss()
    }

    private func save() {
        var field = editing ?? FieldDefinition(name: "", kind: kind)
        field.name = trimmed(name)
        field.options = kind == .choice ? options.map(trimmed).filter { !$0.isEmpty } : []
        field.pageType = kind == .page ? pageType : nil
        if editing != nil { library.updateField(field) } else { add(field) }
        dismiss()
    }

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
}

/// A kind in the Kind picker: its name, and a sample of how a page shows it.
/// Text kinds show their value as lists do (grey, on the right); the others
/// show their real control, for show only (not tappable). VoiceOver reads
/// just the name.
private struct KindRow: View {
    let kind: FieldDefinition.Kind
    private static let option = "Option"
    @FocusState private var focused: UUID?   // never set: the samples aren't tappable

    var body: some View {
        Group {
            switch kind {
            // Samples of what the user would write, so New York.
            case .text: LabeledContent(kind.label) { Text("A line").font(.authored(.body)) }
            case .longText:
                LabeledContent(kind.label) {
                    Text("A paragraph,\nover lines").font(.authored(.body)).multilineTextAlignment(.trailing)
                }
            case .number: LabeledContent(kind.label) { Text(42, format: .number).font(.authored(.body)) }
            default:
                LabeledContent(kind.label) {
                    FieldValueView(field: FieldDefinition(name: kind.label, kind: kind, options: [Self.option]),
                                   value: .constant(sample), focused: $focused)
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.label)
    }

    private var sample: FieldValue? {
        switch kind {
        case .date: .date(.now)
        case .choice: .text(Self.option)
        case .toggle: .toggle(false)
        default: nil
        }
    }
}

extension FieldDefinition.Kind {
    var label: String {
        switch self {
        case .text: "Text"
        case .longText: "Long Text"
        case .number: "Number"
        case .date: "Date"
        case .choice: "Choice"
        case .toggle: "Yes or No"
        case .page: "Page"
        }
    }
}
