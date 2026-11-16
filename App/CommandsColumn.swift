import DevDevCore
import SwiftUI

/// The Commands of the selected Project, with the "All" buttons above the list.
struct CommandsColumn: View {
    let model: WindowModel
    @State private var form: CommandFormTarget?
    @State private var deleting: CommandSnapshot?

    var body: some View {
        if let project = model.state.selectedProject {
            VStack(spacing: 0) {
                allButtons(project)
                Divider()
                list(project)
            }
            .navigationTitle(project.name)
            .navigationSubtitle(project.status.label)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        form = .add(projectID: project.id)
                    } label: {
                        Label("Add Command", systemImage: "plus")
                    }
                    Button {
                        if let command = model.state.selectedCommand { form = .edit(command) }
                    } label: {
                        Label("Edit Command", systemImage: "pencil")
                    }
                    .disabled(model.state.selectedCommand == nil)
                    Button {
                        deleting = model.state.selectedCommand
                    } label: {
                        Label("Delete Command", systemImage: "trash")
                    }
                    .disabled(model.state.selectedCommand == nil)
                }
            }
            .disabled(!model.state.canAct)
            .sheet(item: $form) { target in
                CommandForm(target: target, model: model)
            }
            .confirmationDialog(
                deleting?.deleteConfirmation.title ?? "",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                presenting: deleting
            ) { command in
                Button(command.deleteConfirmation.confirmLabel, role: .destructive) {
                    Task { await model.deleteCommand(command.id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { command in
                Text(command.deleteConfirmation.message)
            }
        } else {
            ContentUnavailableView("No Project selected", systemImage: "sidebar.left")
        }
    }

    private func allButtons(_ project: ProjectSnapshot) -> some View {
        let actions = model.state.actions(for: project)
        return HStack {
            Button("Start All") { Task { await model.startAll(project.id) } }
                .disabled(!actions.startAll)
            Button("Restart All") { Task { await model.restartAll(project.id) } }
                .disabled(!actions.restartAll)
            Button("Stop All") { Task { await model.stopAll(project.id) } }
                .disabled(!actions.stopAll)
            Spacer()
        }
        .padding(10)
    }

    private func list(_ project: ProjectSnapshot) -> some View {
        List(
            selection: Binding(
                get: { model.state.selectedCommandID },
                set: { id in Task { await model.select(command: id) } })
        ) {
            ForEach(project.commands) { command in
                CommandRow(command: command, actions: model.state.actions(for: command), model: model)
                    .tag(command.id)
                    .contextMenu {
                        Button("Edit…") { form = .edit(command) }
                        Button("Delete…", role: .destructive) { deleting = command }
                    }
            }
            .onMove { from, toOffset in
                guard let index = from.first else { return }
                Task { await model.moveCommand(project.commands[index].id, from: index, toOffset: toOffset) }
            }
        }
        .overlay {
            if project.commands.isEmpty {
                ContentUnavailableView(
                    "No Commands", systemImage: "terminal",
                    description: Text("Add one with the + button in the toolbar."))
            }
        }
    }
}

/// One Command: name, command line, status, the Helper's "restart to apply" hint, and its buttons.
struct CommandRow: View {
    let command: CommandSnapshot
    let actions: CommandActions
    let model: WindowModel

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(color: command.status.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(command.settings.name)
                    .fontWeight(.medium)
                Text(command.settings.commandLine)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(command.statusText)
                        .font(.caption)
                        .foregroundStyle(command.status.color)
                    if command.restartToApply {
                        Text("restart to apply")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("This Command was edited while Running. It uses the new settings from its next start.")
                    }
                }
            }
            Spacer()
            Button {
                Task { await model.start(command.id) }
            } label: {
                Image(systemName: "play.fill")
            }
            .help("Start")
            .accessibilityLabel("Start \(command.settings.name)")
            .disabled(!actions.start)
            Button {
                Task { await model.restart(command.id) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Restart")
            .accessibilityLabel("Restart \(command.settings.name)")
            .disabled(!actions.restart)
            Button {
                Task { await model.stop(command.id) }
            } label: {
                Image(systemName: "stop.fill")
            }
            .help("Stop")
            .accessibilityLabel("Stop \(command.settings.name)")
            .disabled(!actions.stop)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 3)
    }
}
