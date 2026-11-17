import AppKit
import DevDevCore
import SwiftUI

/// The left pane: every Project as a folder you expand into its Commands.
struct ProjectTree: View {
    let model: WindowModel
    let actions: WindowActions
    @State private var collapsed: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PROJECTS")
                    .font(Graphite.sectionLabel)
                    .kerning(0.8)
                    .foregroundStyle(Graphite.tertiary)
                Spacer()
                GraphiteIconButton("plus", help: "Add a Project") { actions.isPickingFolder = true }
                    .disabled(!model.state.canAct)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if model.state.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(model.state.projects) { project in
                            ProjectNode(
                                project: project, model: model, actions: actions,
                                isExpanded: !collapsed.contains(project.id)
                            ) {
                                if collapsed.contains(project.id) {
                                    collapsed.remove(project.id)
                                } else {
                                    collapsed.insert(project.id)
                                }
                            }
                            if !collapsed.contains(project.id) {
                                ForEach(Array(project.commands.enumerated()), id: \.element.id) { index, command in
                                    CommandLeaf(
                                        command: command, index: index, project: project, model: model,
                                        actions: actions)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 10)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Graphite.chrome)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Graphite.tertiary)
            Text("No Projects yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Graphite.strong)
            Text("Drop a project folder here, or add one.")
                .font(.system(size: 11.5))
                .foregroundStyle(Graphite.secondary)
                .multilineTextAlignment(.center)
            Button("Add Project…") { actions.isPickingFolder = true }
                .controlSize(.small)
                .disabled(!model.state.canAct)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A Project row: chevron, folder, name, and how many of its Commands run. Hovering swaps the count
/// for the "All" buttons.
private struct ProjectNode: View {
    let project: ProjectSnapshot
    let model: WindowModel
    let actions: WindowActions
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        let all = model.state.actions(for: project)
        let running = project.commands.count { $0.status == .running }
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Graphite.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 12)
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(Graphite.projectTint(project.id))
            Text(project.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Graphite.strong)
                .lineLimit(1)
            if model.discoveringProjectID == project.id {
                ProgressView().controlSize(.mini)
            }
            Spacer(minLength: 4)
            if isHovering {
                HStack(spacing: 0) {
                    GraphiteIconButton("play.fill", help: "Start All", size: 20) {
                        Task { await model.startAll(project.id) }
                    }
                    .disabled(!all.startAll)
                    GraphiteIconButton("arrow.clockwise", help: "Restart All", size: 20) {
                        Task { await model.restartAll(project.id) }
                    }
                    .disabled(!all.restartAll)
                    GraphiteIconButton("stop.fill", help: "Stop All", size: 20) {
                        Task { await model.stopAll(project.id) }
                    }
                    .disabled(!all.stopAll)
                }
            } else {
                Text("\(running)/\(project.commands.count)")
                    .font(Graphite.monoSmall)
                    .foregroundStyle(project.status == .crashed ? Graphite.red : Graphite.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 5).fill(isHovering ? Graphite.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { isHovering = $0 }
        .help("\(project.status.label) — \(project.folder)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(project.status.label)")
        .accessibilityAddTraits(.isButton)
        .contextMenu { ProjectActionsMenu(project: project, model: model, actions: actions) }
    }
}

/// The Project actions, shared by the tree's context menu and the output pane's menu.
struct ProjectActionsMenu: View {
    let project: ProjectSnapshot
    let model: WindowModel
    let actions: WindowActions

    var body: some View {
        let all = model.state.actions(for: project)
        Button("Start All") { Task { await model.startAll(project.id) } }.disabled(!all.startAll)
        Button("Restart All") { Task { await model.restartAll(project.id) } }.disabled(!all.restartAll)
        Button("Stop All") { Task { await model.stopAll(project.id) } }.disabled(!all.stopAll)
        Divider()
        Button("Add Command…") { actions.form = .add(projectID: project.id) }
            .disabled(!model.state.canAct)
        Button("Rescan") { Task { await model.rescan(project.id) } }
            .help("Read the Project folder again and propose Commands to add or remove")
            .disabled(model.discoveringProjectID != nil || !model.state.canAct)
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.folder)])
        }
        Divider()
        Button("Remove Project…", role: .destructive) { actions.removing = project }
            .disabled(!model.state.canAct)
    }
}

/// A Command row inside its Project: status, name, and how long it ran or how it ended.
private struct CommandLeaf: View {
    let command: CommandSnapshot
    let index: Int
    let project: ProjectSnapshot
    let model: WindowModel
    let actions: WindowActions
    @State private var isHovering = false

    var body: some View {
        let isSelected = model.state.selectedCommandID == command.id
        HStack(spacing: 8) {
            StatusGlyph(command.status)
            Text(command.settings.name)
                .font(.system(size: 12.5))
                .foregroundStyle(isSelected ? Graphite.strong : Graphite.text)
                .lineLimit(1)
            if command.settings.runInContainer {
                Image(systemName: "shippingbox")
                    .font(.system(size: 10))
                    .foregroundStyle(Graphite.secondary)
                    .help("Runs inside the Docker container “\(command.settings.containerName)”")
                    .accessibilityLabel("In container \(command.settings.containerName)")
            }
            if command.restartToApply {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Graphite.amber)
                    .help("Edited while Running. It uses the new settings from its next start.")
            }
            Spacer(minLength: 4)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(command.status == .stopped ? "" : command.detail(now: context.date))
                    .font(Graphite.monoSmall)
                    .foregroundStyle(command.status == .crashed ? Graphite.red : Graphite.tertiary)
            }
        }
        .padding(.leading, 30)
        .padding(.trailing, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Graphite.selection : isHovering ? Graphite.hover : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { Task { await model.show(command: command.id) } }
        .onHover { isHovering = $0 }
        .help(command.settings.effectiveCommandLine)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(command.settings.name), \(command.statusText)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contextMenu {
            CommandActionsMenu(command: command, model: model, actions: actions)
            Divider()
            Button("Move Up") {
                Task { await model.moveCommand(command.id, from: index, toOffset: index - 1) }
            }
            .disabled(index == 0 || !model.state.canAct)
            Button("Move Down") {
                Task { await model.moveCommand(command.id, from: index, toOffset: index + 2) }
            }
            .disabled(index == project.commands.count - 1 || !model.state.canAct)
        }
    }
}

/// The Command actions, shared by the tree's context menu and the output pane's menu.
struct CommandActionsMenu: View {
    let command: CommandSnapshot
    let model: WindowModel
    let actions: WindowActions

    var body: some View {
        let can = model.state.actions(for: command)
        Button("Start") { Task { await model.start(command.id) } }.disabled(!can.start)
        Button("Restart") { Task { await model.restart(command.id) } }.disabled(!can.restart)
        Button("Stop") { Task { await model.stop(command.id) } }.disabled(!can.stop)
        Divider()
        Button("Edit Command…") { actions.form = .edit(command) }
            .disabled(!model.state.canAct)
        Button("Delete Command…", role: .destructive) { actions.deleting = command }
            .disabled(!model.state.canAct)
    }
}
