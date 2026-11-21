import SwiftUI
import WriterCore

/// The open page's type and its fields, under the title in Edit mode: a
/// grouped section of standard controls, label on the left, value on the
/// right, as in Contacts. A plain page shows only a small "Add Type".
struct PageFields: View {
    @Environment(Library.self) private var library
    /// Its height, so the writing below starts after it.
    let onHeight: (CGFloat) -> Void

    var body: some View {
        let page = library.document
        Group {
            if let type = library.type(of: page) {
                VStack(spacing: 0) {
                    typeMenu(LabeledContent("Type") { Text(type.name) })
                    ForEach(library.fields(of: page)) { field in
                        Divider()
                        FieldRow(field: field, value: value(field))
                            .contextMenu {
                                Button("Edit Field…", systemImage: "pencil") { library.fieldsRequest = .editField(field.id) }
                                Button("Remove from \(type.name)", systemImage: "minus.circle", role: .destructive) {
                                    library.remove(field.id, from: type.id)
                                }
                            }
                    }
                    Divider()
                    Button("Add Field", systemImage: "plus") { library.fieldsRequest = .addField(type: type.id) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 11)
                }
                .padding(.horizontal, 16)
                .background(.background.secondary, in: .rect(cornerRadius: 16))
            } else {
                typeMenu(Label("Add Type", systemImage: "square.text.square"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
            label.padding(.vertical, 11).contentShape(.rect)
        }
        .tint(.primary)
    }

    private func value(_ field: FieldDefinition) -> Binding<FieldValue?> {
        Binding { library.document.values[field.id] } set: { value in library.update { $0.values[field.id] = value } }
    }
}

/// One field: the standard control for its kind.
private struct FieldRow: View {
    @Environment(Library.self) private var library
    let field: FieldDefinition
    @Binding var value: FieldValue?

    var body: some View {
        content.padding(.vertical, 11)
    }

    @ViewBuilder private var content: some View {
        switch field.kind {
        case .text:
            LabeledContent(field.name) {
                TextField(field.name, text: text).multilineTextAlignment(.trailing)
            }
        case .longText:
            VStack(alignment: .leading, spacing: 4) {
                Text(field.name).font(.subheadline).foregroundStyle(.secondary)
                TextField(field.name, text: text, axis: .vertical)
            }
        case .number:
            LabeledContent(field.name) {
                TextField(field.name, value: number, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        case .date:
            if case .date(let date)? = value {
                DatePicker(field.name, selection: Binding { date } set: { value = .date($0) }, displayedComponents: .date)
            } else {
                LabeledContent(field.name) { Button("Add Date") { value = .date(Date()) } }
            }
        case .choice:
            LabeledContent(field.name) {
                Picker(field.name, selection: text) {
                    Text("None").tag("")
                    ForEach(field.options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        case .toggle:
            Toggle(field.name, isOn: Binding { if case .toggle(true)? = value { true } else { false } } set: { value = .toggle($0) })
        case .page:
            LabeledContent(field.name) {
                HStack(spacing: 4) {
                    Picker(field.name, selection: page) {
                        Text("None").tag(UUID?.none)
                        ForEach(candidates) { Text($0.heading).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    if let id = page.wrappedValue {
                        Button("Open", systemImage: "arrow.up.right") { library.selection = id }
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
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
