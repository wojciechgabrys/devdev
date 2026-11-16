import DevDevCore
import SwiftUI

/// The panel under the menubar icon: Projects you expand into Commands. No output.
/// Rows, statuses and which buttons work come from `MenubarPanel`.
struct MenubarPanelView: View {
    let model: MenubarModel
    let opener: AppOpener
    let close: () -> Void
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.panel.rows.isEmpty {
                Text("No Projects yet. Add one in devdev.")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.panel.rows) { row in
                            projectRow(row)
                            if expanded.contains(row.id) {
                                ForEach(row.commands) { command in
                                    commandRow(command)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 420)
            }
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                PanelMenuButton(title: "Open devdev") {
                    close()
                    opener.openApp()
                }
                PanelMenuButton(title: "Stop All and Quit") {
                    close()
                    Task { await model.stopAllAndQuit() }
                }
            }
            .padding(6)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func projectRow(_ row: MenubarPanel.ProjectRow) -> some View {
        HStack(spacing: 8) {
            Button {
                if expanded.contains(row.id) { expanded.remove(row.id) } else { expanded.insert(row.id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded.contains(row.id) ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .frame(width: 10)
                    PanelDot(color: row.status.panelColor)
                    Text(row.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ActionButton(symbol: "play.fill", help: "Start All", enabled: row.actions.startAll) {
                await model.startAll(row.id)
            }
            ActionButton(symbol: "arrow.clockwise", help: "Restart All", enabled: row.actions.restartAll) {
                await model.restartAll(row.id)
            }
            ActionButton(symbol: "stop.fill", help: "Stop All", enabled: row.actions.stopAll) {
                await model.stopAll(row.id)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    private func commandRow(_ command: MenubarPanel.CommandRow) -> some View {
        HStack(spacing: 8) {
            PanelDot(color: command.status.panelColor)
            Button {
                close()
                opener.open(.command(command.id))
            } label: {
                Text(command.name)
                    .lineLimit(1)
            }
            .buttonStyle(.link)
            .help("Show the output in devdev")
            Spacer(minLength: 4)
            Text(command.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ActionButton(symbol: "play.fill", help: "Start", enabled: command.actions.start) {
                await model.start(command.id)
            }
            ActionButton(symbol: "arrow.clockwise", help: "Restart", enabled: command.actions.restart) {
                await model.restart(command.id)
            }
            ActionButton(symbol: "stop.fill", help: "Stop", enabled: command.actions.stop) {
                await model.stop(command.id)
            }
        }
        .padding(.vertical, 3)
        .padding(.leading, 28)
        .padding(.trailing, 4)
    }
}

private struct ActionButton: View {
    let symbol: String
    let help: String
    let enabled: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(help)
    }
}

private struct PanelMenuButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PanelDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

extension CommandStatus {
    var panelColor: Color {
        switch self {
        case .stopped: .secondary
        case .running: .green
        case .finished: .blue
        case .crashed: .red
        }
    }
}

extension ProjectStatus {
    var panelColor: Color {
        switch self {
        case .stopped: .secondary
        case .running: .green
        case .partlyRunning: .orange
        case .crashed: .red
        }
    }
}
