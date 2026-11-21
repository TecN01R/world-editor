import SwiftUI
import WriterCore

/// The open page's type and its fields, under the title in Edit mode. The
/// type is a small line under the title, as Contacts puts a company under a
/// name ("Add Type" on a plain page). Fields float on the page, without a
/// card: a quiet name, then its value; the values you tap (choices, dates,
/// page links) sit in Liquid Glass capsules like the app's other controls.
struct PageFields: View {
    @Environment(Library.self) private var library
    /// Its height, so the writing below starts after it.
    let onHeight: (CGFloat) -> Void

    var body: some View {
        let page = library.document
        let type = library.type(of: page)
        let fields = library.fields(of: page)
        VStack(alignment: .leading, spacing: 10) {
            typeMenu(Label(type?.name ?? "Add Type", systemImage: "square.text.square"))
            if let type {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {   // each row centred on its control
                    ForEach(fields) { field in
                        GridRow {
                            Text(field.name).foregroundStyle(.secondary).gridColumnAlignment(.leading)
                            FieldValueView(field: field, value: value(field))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contextMenu {
                            Button("Edit Field…", systemImage: "pencil") { library.fieldsRequest = .editField(field.id) }
                            Button("Remove from \(type.name)", systemImage: "minus.circle", role: .destructive) {
                                library.remove(field.id, from: type.id)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                Button("Add Field", systemImage: "plus") { library.fieldsRequest = .addField(type: type.id) }
                    .font(.subheadline)
                    .tint(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(duration: 0.35), value: type?.id)
        .animation(.spring(duration: 0.35), value: fields.map(\.id))
        .fixedSize(horizontal: false, vertical: true)   // its own height, whatever the frame
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
    }

    private func typeMenu(_ label: some View) -> some View {
        Menu {
            ForEach(library.schema.types) { type in
                Button(type.name) { library.update { $0.type = type.id } }
            }
            Button("New Type…", systemImage: "plus") { library.fieldsRequest = .newType }
            if library.document.type != nil {
                Divider()
                Button("No Type", role: .destructive) { library.update { $0.type = nil } }
            }
        } label: {
            label.padding(.vertical, 4).contentShape(.rect)
        }
        .font(.subheadline)
        .tint(.secondary)
        .accessibilityLabel("Type")
        .sensoryFeedback(.selection, trigger: library.document.type)
    }

    private func value(_ field: FieldDefinition) -> Binding<FieldValue?> {
        Binding { library.document.values[field.id] } set: { value in library.update { $0.values[field.id] = value } }
    }
}

/// A field's value: the standard control for its kind, without its label
/// (the name sits beside it).
private struct FieldValueView: View {
    @Environment(Library.self) private var library
    let field: FieldDefinition
    @Binding var value: FieldValue?

    var body: some View {
        switch field.kind {
        case .text:
            TextField(field.name, text: text, prompt: Text("Add")).glassField()
        case .longText:
            TextField(field.name, text: text, prompt: Text("Add"), axis: .vertical).glassField(in: .rect(cornerRadius: 16))
        case .number:
            TextField(field.name, value: number, format: .number, prompt: Text("Add"))
                .keyboardType(.decimalPad)
                .fixedSize()
                .glassField()
        case .date:
            if case .date(let date)? = value {
                DatePicker(field.name, selection: Binding { date } set: { value = .date($0) }, displayedComponents: .date)
                    .labelsHidden()
                    .sensoryFeedback(.selection, trigger: date)
            } else {
                Button("Add Date") { value = .date(Date()) }.buttonStyle(.glass)
            }
        case .choice:
            dropdown(text, current: text.wrappedValue.isEmpty ? "Choose" : text.wrappedValue) {
                Text("None").tag("")
                ForEach(field.options, id: \.self) { Text($0).tag($0) }
            }
        case .toggle:
            Toggle(field.name, isOn: Binding { if case .toggle(true)? = value { true } else { false } } set: { value = .toggle($0) })
                .labelsHidden()
                .sensoryFeedback(.selection, trigger: value)
        case .page:
            HStack(spacing: 8) {
                let name = page.wrappedValue.flatMap { id in library.pages.first { $0.id == id }?.heading }
                dropdown(page, current: name ?? "Choose") {
                    Text("None").tag(UUID?.none)
                    ForEach(candidates) { Text($0.heading).tag(Optional($0.id)) }
                }
                if let id = page.wrappedValue {
                    Button("Open", systemImage: "arrow.up.right") { library.selection = id }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                }
            }
        }
    }

    /// A dropdown like a menu-style Picker, but its value stays on one line
    /// (truncated), so a long page name never wraps the row.
    private func dropdown<Value: Hashable>(_ selection: Binding<Value>, current: String,
                                           @ViewBuilder options: () -> some View) -> some View {
        Menu {
            Picker(field.name, selection: selection, content: options).pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(current).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
        .buttonStyle(.glass)
        .sensoryFeedback(.selection, trigger: selection.wrappedValue)
        .accessibilityLabel(field.name)
        .accessibilityValue(current)
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
                                LabeledContent(field.name, value: field.kind.label)
                            }
                            .tint(.primary)
                        }
                    }
                }
                Section(editing == nil ? "New Field" : "Field") {
                    TextField("Name", text: $name)
                    Picker("Kind", selection: $kind) {
                        ForEach(FieldDefinition.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .disabled(editing != nil)   // values already saved keep their kind
                    if kind == .page {
                        Picker("Pages of Type", selection: $pageType) {
                            Text("Any").tag(UUID?.none)
                            ForEach(library.schema.types) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
                if kind == .choice {
                    Section("Choices") {
                        ForEach(options.indices, id: \.self) { i in TextField("Choice", text: $options[i]) }
                        Button("Add Choice", systemImage: "plus") { options.append("") }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add Field" : "Edit Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", action: save).disabled(trimmed(name).isEmpty)
                }
            }
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

extension View {
    /// A text or number value in glass, like the glass buttons beside it, so
    /// every value you can change looks changeable. (iOS has a glass button
    /// style but no glass text field style; the padding matches the buttons.)
    func glassField(in shape: some Shape = .capsule) -> some View {
        padding(.horizontal, 12).padding(.vertical, 7)
            .glassEffect(.regular.interactive(), in: shape)
    }
}
