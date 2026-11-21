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
                    ForEach(type.fields) { field in
                        Divider()
                        FieldRow(field: field, value: value(field)) { remove(field, from: type) }
                    }
                    Divider()
                    Button("Add Field", systemImage: "plus") { library.fieldsRequest = .addField(type.id) }
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
            ForEach(library.types) { type in
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

    /// Takes the field off the type, for every page of it. Values stay saved
    /// on the pages, unseen, so nothing written is lost.
    private func remove(_ field: FieldDefinition, from type: PageType) {
        var type = type
        type.fields.removeAll { $0.id == field.id }
        library.updateType(type)
    }
}

/// One field: the standard control for its kind.
private struct FieldRow: View {
    let field: FieldDefinition
    @Binding var value: FieldValue?
    let remove: () -> Void

    var body: some View {
        content
            .padding(.vertical, 11)
            .contextMenu { Button("Remove Field", systemImage: "trash", role: .destructive, action: remove) }
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
            Picker(field.name, selection: text) {
                Text("None").tag("")
                ForEach(field.options, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
        case .toggle:
            Toggle(field.name, isOn: Binding { if case .toggle(true)? = value { true } else { false } } set: { value = .toggle($0) })
        }
    }

    private var text: Binding<String> {
        Binding { if case .text(let s)? = value { s } else { "" } } set: { value = $0.isEmpty ? nil : .text($0) }
    }

    private var number: Binding<Double?> {
        Binding { if case .number(let n)? = value { n } else { nil } } set: { value = $0.map(FieldValue.number) }
    }
}

/// Adding a field to a type: a name, a kind and, for a choice, its options.
struct AddFieldSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let typeID: UUID
    @State private var name = ""
    @State private var kind = FieldDefinition.Kind.text
    @State private var options: [String] = [""]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Kind", selection: $kind) {
                    ForEach(FieldDefinition.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if kind == .choice {
                    Section("Choices") {
                        ForEach(options.indices, id: \.self) { i in TextField("Choice", text: $options[i]) }
                        Button("Add Choice", systemImage: "plus") { options.append("") }
                    }
                }
            }
            .navigationTitle("New Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark") { add() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        guard var type = library.types.first(where: { $0.id == typeID }) else { return dismiss() }
        let choices = options.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        type.fields.append(FieldDefinition(name: name.trimmingCharacters(in: .whitespaces), kind: kind,
                                           options: kind == .choice ? choices : []))
        library.updateType(type)
        dismiss()
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
        }
    }
}
