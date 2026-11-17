import DevDevCore
import SwiftUI

/// The right pane: output tabs, the selected Command's bar, and its output.
struct OutputPane: View {
    let model: WindowModel
    let actions: WindowActions

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(model: model)
            if let command = model.state.selectedCommand, let project = model.state.selectedProject {
                CommandBar(command: command, project: project, model: model, actions: actions)
                if let session = model.output {
                    TerminalOutputView(session: session) { columns, rows in
                        Task { await model.outputViewResized(columns: columns, rows: rows) }
                    }
                    // A new session means a new replay: start from an empty terminal.
                    .id(session.id)
                    .padding(.leading, 10)
                    .padding(.top, 6)
                } else {
                    Graphite.canvas
                }
            } else {
                emptyState
            }
        }
        .background(Graphite.canvas)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Graphite.tertiary)
            Text("No Command open")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Graphite.strong)
            Text("Pick one in the tree, or press ⌘K and type its name.")
                .font(.system(size: 11.5))
                .foregroundStyle(Graphite.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One tab per opened Command, from any Project.
private struct TabStrip: View {
    let model: WindowModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(model.state.tabs, id: \.self) { id in
                    if let command = model.state.snapshot.command(id),
                        let project = model.state.snapshot.project(command.projectID)
                    {
                        OutputTab(
                            command: command, projectName: project.name,
                            isActive: model.state.selectedCommandID == id, model: model)
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Graphite.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(Graphite.line).frame(height: 1) }
        .background {
            // Cmd-Shift-[ and ] move between tabs, as in Safari and Xcode. Cmd-W and Cmd-1 to 0 live in
            // `TabCommands`.
            Group {
                Button("Previous Tab") { step(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Next Tab") { step(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private func step(_ delta: Int) {
        let tabs = model.state.tabs
        guard !tabs.isEmpty else { return }
        let current = model.state.selectedCommandID.flatMap(tabs.firstIndex(of:)) ?? 0
        let next = tabs[(current + delta + tabs.count) % tabs.count]
        Task { await model.show(command: next) }
    }
}

private struct OutputTab: View {
    let command: CommandSnapshot
    let projectName: String
    let isActive: Bool
    let model: WindowModel
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            StatusGlyph(command.status)
            Text(command.settings.name)
                .font(.system(size: 12.5, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Graphite.strong : Graphite.secondary)
            Text(projectName)
                .font(.system(size: 11))
                .foregroundStyle(Graphite.tertiary)
            Spacer(minLength: 6)
            Button {
                Task { await model.closeTab(command.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Graphite.tertiary)
            .opacity(isActive || isHovering ? 1 : 0)
            .help("Close Tab")
            .accessibilityLabel("Close \(command.settings.name)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minWidth: 150, maxHeight: .infinity)
        .background(isActive ? Graphite.canvas : isHovering ? Graphite.hover.opacity(0.5) : .clear)
        .overlay(alignment: .top) {
            if isActive { Rectangle().fill(Graphite.accent).frame(height: 2) }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Graphite.line).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture { Task { await model.show(command: command.id) } }
        .onMiddleClick { Task { await model.closeTab(command.id) } }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(command.settings.name) in \(projectName), \(command.statusText)")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

/// Where the Command is, what it runs and how it is doing, with its buttons.
private struct CommandBar: View {
    let command: CommandSnapshot
    let project: ProjectSnapshot
    let model: WindowModel
    let actions: WindowActions

    var body: some View {
        let can = model.state.actions(for: command)
        HStack(spacing: 10) {
            (Text("\(project.name) / ").foregroundStyle(Graphite.secondary)
                + Text(command.settings.name).fontWeight(.semibold).foregroundStyle(Graphite.strong))
                .font(.system(size: 12.5))
                .lineLimit(1)
                .layoutPriority(1)
            Pill(text: command.statusText, color: command.status.graphiteColor)
            if command.settings.runInContainer {
                Label(command.settings.containerName, systemImage: "shippingbox")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Graphite.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .help("Runs inside the Docker container “\(command.settings.containerName)”")
            }
            Text("$ \(command.settings.commandLine)")
                .font(Graphite.mono)
                .foregroundStyle(Graphite.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Graphite.raised))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Graphite.line))
                .help(command.settings.effectiveCommandLine)
            if command.restartToApply {
                Pill(text: "Restart to apply", color: Graphite.amber)
                    .help("This Command was edited while Running. It uses the new settings from its next start.")
            }
            if command.settings.autoRestart {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Graphite.secondary)
                    .help("Auto-restart is on")
            }
            if !command.settings.restartWhenFilesChange.isEmpty {
                Image(systemName: "eye")
                    .font(.system(size: 10))
                    .foregroundStyle(Graphite.secondary)
                    .help("Restarts when these files change: \(command.settings.restartWhenFilesChange.joined(separator: ", "))")
            }
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                segment("play.fill", "Start", enabled: can.start) { await model.start(command.id) }
                Rectangle().fill(Graphite.line).frame(width: 1)
                segment("arrow.clockwise", "Restart", enabled: can.restart) { await model.restart(command.id) }
                Rectangle().fill(Graphite.line).frame(width: 1)
                segment("stop.fill", "Stop", enabled: can.stop) { await model.stop(command.id) }
            }
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Graphite.raised))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Graphite.line))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Menu {
                CommandActionsMenu(command: command, model: model, actions: actions)
                Divider()
                ProjectActionsMenu(project: project, model: model, actions: actions)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Graphite.secondary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Graphite.line.opacity(0.7)).frame(height: 1) }
    }

    private func segment(
        _ symbol: String, _ help: String, enabled: Bool, action: @escaping () async -> Void
    ) -> some View {
        SegmentButton(symbol: symbol, help: help) { Task { await action() } }
            .disabled(!enabled)
            .accessibilityLabel("\(help) \(command.settings.name)")
    }
}

private struct SegmentButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 30, height: 24)
                .foregroundStyle(Graphite.strong)
                .background(isHovering && isEnabled ? Graphite.hover : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.3)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

/// A small tinted label, such as "Running" or "Restart to apply".
struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.14)))
    }
}
