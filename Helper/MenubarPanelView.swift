import DevDevCore
import SwiftUI

/// The panel under the menubar icon, in the Graphite look: a filter field, then each Project with its
/// Commands. No output. Rows, statuses, filtering and which buttons work come from `MenubarPanel`.
struct MenubarPanelView: View {
    let model: MenubarModel
    let opener: AppOpener
    let close: () -> Void
    @State private var collapsed: Set<UUID> = []
    @State private var filter = ""
    @FocusState private var isFilterFocused: Bool

    var body: some View {
        let panel = model.panel.filtered(by: filter)
        VStack(alignment: .leading, spacing: 0) {
            filterField
            if model.panel.rows.isEmpty {
                Text("No Projects yet. Add one in devdev.")
                    .font(.system(size: 12))
                    .foregroundStyle(Graphite.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else if panel.rows.isEmpty {
                Text("No Command matches “\(filter)”")
                    .font(.system(size: 12))
                    .foregroundStyle(Graphite.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(panel.rows) { row in
                            // While filtering every match shows, so nothing hides behind a collapsed row.
                            let isOpen = !filter.isEmpty || !collapsed.contains(row.id)
                            projectHeader(row, isOpen: isOpen)
                            if isOpen {
                                ForEach(row.commands) { command in
                                    CommandRow(command: command, model: model) {
                                        close()
                                        opener.open(.command(command.id))
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 440)
            }
            Rectangle().fill(Graphite.line).frame(height: 1)
            VStack(spacing: 1) {
                FooterItem(title: "Open devdev", shortcut: "⌘O") {
                    close()
                    opener.openApp()
                }
                .keyboardShortcut("o", modifiers: .command)
                FooterItem(title: "Stop All and Quit", shortcut: "⌥⌘Q") {
                    close()
                    Task { await model.stopAllAndQuit() }
                }
                .keyboardShortcut("q", modifiers: [.command, .option])
            }
            .padding(6)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(Graphite.chrome)
        .foregroundStyle(Graphite.text)
        .onAppear { isFilterFocused = true }
    }

    private var filterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Graphite.secondary)
            TextField("Filter Commands", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isFilterFocused)
                .onKeyPress(.escape) {
                    if filter.isEmpty { close() } else { filter = "" }
                    return .handled
                }
            Spacer(minLength: 4)
            Text("\(model.panel.runningCount) running")
                .font(.system(size: 10.5))
                .foregroundStyle(Graphite.tertiary)
            if model.panel.crashedCount > 0 {
                Text("\(model.panel.crashedCount) crashed")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Graphite.red)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(Graphite.raised))
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func projectHeader(_ row: MenubarPanel.ProjectRow, isOpen: Bool) -> some View {
        ProjectHeader(row: row, isOpen: isOpen, model: model) {
            if collapsed.contains(row.id) { collapsed.remove(row.id) } else { collapsed.insert(row.id) }
        }
    }
}

/// A Project's name as a small heading. Hovering shows its "All" buttons.
private struct ProjectHeader: View {
    let row: MenubarPanel.ProjectRow
    let isOpen: Bool
    let model: MenubarModel
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Graphite.tertiary)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .frame(width: 10)
            if row.status == .crashed {
                StatusGlyph(row.status)
            }
            Text(row.name.uppercased())
                .font(Graphite.sectionLabel)
                .kerning(0.7)
                .foregroundStyle(row.status == .crashed ? Graphite.red : Graphite.tertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                GraphiteIconButton("play.fill", help: "Start All", size: 20) {
                    Task { await model.startAll(row.id) }
                }
                .disabled(!row.actions.startAll)
                GraphiteIconButton("arrow.clockwise", help: "Restart All", size: 20) {
                    Task { await model.restartAll(row.id) }
                }
                .disabled(!row.actions.restartAll)
                GraphiteIconButton("stop.fill", help: "Stop All", size: 20) {
                    Task { await model.stopAll(row.id) }
                }
                .disabled(!row.actions.stopAll)
            }
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { isHovering = $0 }
        .help(row.statusLabel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.name), \(row.statusLabel)")
    }
}

/// One Command: status, name, and how long it ran or how it ended. Hovering shows its buttons.
/// Clicking the name opens the App on its output.
private struct CommandRow: View {
    let command: MenubarPanel.CommandRow
    let model: MenubarModel
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            StatusGlyph(command.status)
            Text(command.name)
                .font(.system(size: 12.5))
                .foregroundStyle(Graphite.strong)
                .lineLimit(1)
            Spacer(minLength: 4)
            if isHovering {
                HStack(spacing: 0) {
                    GraphiteIconButton("play.fill", help: "Start", size: 20) {
                        Task { await model.start(command.id) }
                    }
                    .disabled(!command.actions.start)
                    GraphiteIconButton("arrow.clockwise", help: "Restart", size: 20) {
                        Task { await model.restart(command.id) }
                    }
                    .disabled(!command.actions.restart)
                    GraphiteIconButton("stop.fill", help: "Stop", size: 20) {
                        Task { await model.stop(command.id) }
                    }
                    .disabled(!command.actions.stop)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(command.detail(now: context.date))
                        .font(Graphite.monoSmall)
                        .foregroundStyle(command.status == .crashed ? Graphite.red : Graphite.tertiary)
                }
            }
        }
        .padding(.leading, 26)
        .padding(.trailing, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6).fill(isHovering ? Graphite.hover : .clear))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { isHovering = $0 }
        .help("\(command.statusText). Click to show the output in devdev.")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(command.name), \(command.statusText)")
    }
}

private struct FooterItem: View {
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut)
                    .foregroundStyle(isHovering ? .white.opacity(0.8) : Graphite.tertiary)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(isHovering ? .white : Graphite.text)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(isHovering ? Graphite.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
