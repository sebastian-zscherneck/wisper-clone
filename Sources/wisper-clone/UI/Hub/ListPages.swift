import SwiftUI

struct DictionaryPage: View {
    @ObservedObject var coordinator: DictationCoordinator

    var body: some View {
        EditableListPane(
            placeholder: "Add a word or phrase",
            emptyText: "No entries yet.",
            footer: "Names and technical terms the AI cleanup should spell exactly like this.",
            items: coordinator.dictionaryTerms,
            add: coordinator.addDictionaryTerm,
            remove: coordinator.removeDictionaryTerm
        )
    }
}

struct RulesPage: View {
    @ObservedObject var coordinator: DictationCoordinator

    var body: some View {
        EditableListPane(
            placeholder: "Add a rule, e.g. never use exclamation marks",
            emptyText: "No rules yet.",
            footer: "Rules apply to every AI cleanup and every Command Mode edit.",
            items: coordinator.rules,
            add: coordinator.addRule,
            remove: coordinator.removeRule
        )
    }
}

/// An add field on top and the entries below, each with a delete button.
private struct EditableListPane: View {
    let placeholder: String
    let emptyText: String
    let footer: String
    let items: [String]
    let add: (String) -> Void
    let remove: (String) -> Void
    @State private var input = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField(placeholder, text: $input)
                        .labelsHidden()
                        .onSubmit(submit)
                    Button("Add", action: submit)
                        .disabled(trimmedInput.isEmpty)
                }
            } footer: {
                Text(footer)
            }

            Section {
                if items.isEmpty {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                }
                ForEach(items, id: \.self) { item in
                    HStack {
                        Text(item)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            remove(item)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(item)")
                    }
                }
            }
        }
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedInput.isEmpty else { return }
        add(input)
        input = ""
    }
}
