import DevDevCore
import SwiftUI

/// What the Command form is open for.
enum CommandFormTarget: Identifiable {
    case add(projectID: UUID)
    case edit(CommandSnapshot)

    var id: UUID {
        switch self {
        case .add(let projectID): projectID
        case .edit(let command): command.id
        }
    }
}

/// The form with every Command field of `docs/spec.md` section 4. The Helper checks what is typed.
struct CommandForm: View {
    let target: CommandFormTarget
    let model: WindowModel
    @State private var draft: CommandDraft
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    init(target: CommandFormTarget, model: WindowModel) {
        self.target = target
        self.model = model
        switch target {
        case .add: _draft = State(initialValue: CommandDraft())
        case .edit(let command): _draft = State(initialValue: CommandDraft(command.settings))
        }
    }

    private var title: String {
        switch target {
        case .add: "Add Command"
        case .edit: "Edit Command"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Queue"))
                    TextField("Command line", text: $draft.commandLine, prompt: Text("npm run dev"))
                        .font(.system(.body, design: .monospaced))
                    TextField("Subfolder", text: $draft.subfolder, prompt: Text("Project folder"))
                }
                Section("Environment variables") {
                    ForEach(draft.environment.indices, id: \.self) { index in
                        HStack {
                            TextField("Name", text: $draft.environment[index].name)
                                .labelsHidden()
                            Text("=")
                            TextField("Value", text: $draft.environment[index].value)
                                .labelsHidden()
                            Button {
                                draft.environment.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove variable")
                        }
                        .font(.system(.body, design: .monospaced))
                    }
                    Button("Add Variable") {
                        draft.environment.append(EnvironmentVariable(name: "", value: ""))
                    }
                }
                Section {
                    Toggle("Included in Start All", isOn: $draft.includedInStartAll)
                    Toggle("Auto-restart", isOn: $draft.autoRestart)
                }
                Section("Restart when files change") {
                    TextEditor(text: $draft.restartWhenFilesChange)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 70)
                    Text("One glob pattern per line, relative to the Project folder. Empty means off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
            .padding()
        }
        .frame(width: 520, height: 560)
        .navigationTitle(title)
    }

    private func save() {
        isSaving = true
        Task {
            let saved =
                switch target {
                case .add(let projectID): await model.addCommand(to: projectID, draft: draft)
                case .edit(let command): await model.updateCommand(command.id, draft: draft)
                }
            isSaving = false
            if saved { dismiss() }
        }
    }
}
