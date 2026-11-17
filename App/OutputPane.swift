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

/// One tab per opened Command, from any Project. A tab can be dragged left and right to a new place.
private struct TabStrip: View {
    let model: WindowModel
    /// The drag in progress, if any. The tab order itself lives in the model and changes live.
    @State private var drag: TabDrag?
    /// The tab drawn above the others: the dragged one, also while it settles after the drop.
    @State private var raisedTab: UUID?
    /// Each tab's real width, as laid out.
    @State private var widths: [UUID: Double] = [:]
    /// The visible part of the strip: how far it is scrolled and how wide it is.
    @State private var viewport = TabStripViewport(scrollX: 0, width: 0)
    /// Scrolls the strip by itself while a dragged tab is held at a visible edge.
    @State private var scrollPosition = ScrollPosition()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The short slide of the neighbours and of the dropped tab. With Reduce Motion they jump.
    private var slide: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(model.state.tabs, id: \.self) { id in
                    if let command = model.state.snapshot.command(id),
                        let project = model.state.snapshot.project(command.projectID)
                    {
                        OutputTab(
                            command: command, projectName: project.name,
                            isActive: model.state.selectedCommandID == id,
                            showsHover: drag == nil, model: model,
                            onDrag: { pressX, pointerX in dragged(id, pressX: pressX, pointerX: pointerX) },
                            onDrop: drop, onCancel: cancel
                        )
                        .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { widths[id] = $0 }
                        .offset(x: offset(of: id))
                        .zIndex(raisedTab == id ? 1 : 0)
                        // The dragged tab follows the pointer at once. Only its neighbours slide.
                        .transaction { if drag?.tab == id { $0.animation = nil } }
                    }
                }
            }
            .animation(slide, value: model.state.tabs)
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: TabStripViewport.self) {
            TabStripViewport(scrollX: Double($0.contentOffset.x), width: Double($0.containerSize.width))
        } action: { _, viewport in
            scrolled(to: viewport)
        }
        // Runs only while the dragged tab is held at an edge with tabs out of view on that side.
        // Any end of the drag clears `drag`, which stops it.
        .task(id: drag?.isScrolling ?? false) { await scrollAtEdge() }
        // The dragged tab's Command was deleted or its Project removed: the drag ends quietly.
        .onChange(of: model.state.tabs) { _, tabs in
            guard let drag, !drag.continues(in: tabs) else { return }
            self.drag = nil
            raisedTab = nil
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

    /// How far the dragged tab is drawn from the slot the tab order gives it. Other tabs stay put.
    private func offset(of id: UUID) -> CGFloat {
        guard let drag, drag.tab == id, let place = model.state.tabs.firstIndex(of: id) else { return 0 }
        return CGFloat(drag.offsetFromSlot(place: place))
    }

    /// The pointer moved with the left button held on a tab, past the click threshold.
    /// The first call starts the drag. Each new place goes to the model right away.
    private func dragged(_ id: UUID, pressX: Double, pointerX: Double) {
        var current =
            drag ?? TabDrag(tab: id, tabs: model.state.tabs, widths: widths, pressX: pressX, viewport: viewport)
        guard current?.tab == id, let place = current?.follow(pointerX: pointerX, in: viewport) else { return }
        drag = current
        raisedTab = id
        model.moveTab(id, to: place)
    }

    /// The strip scrolled, by itself or by the user. During a drag the tabs moved under the
    /// dragged tab, so it may take a new place.
    private func scrolled(to viewport: TabStripViewport) {
        self.viewport = viewport
        guard var current = drag else { return }
        let place = current.scrolled(to: viewport)
        drag = current
        model.moveTab(current.tab, to: place)
    }

    /// Scrolls the strip a little on every frame while the dragged tab is held at a visible edge.
    /// It ends when the tab leaves the edge, the first or last tab comes into view, or the drag ends.
    private func scrollAtEdge() async {
        let clock = ContinuousClock()
        var last = clock.now
        while drag?.isScrolling == true {
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            let now = clock.now
            let elapsed = last.duration(to: now) / .seconds(1)
            last = now
            guard let step = drag?.scrollStep(elapsed: elapsed), step != 0 else { return }
            let scrollX = viewport.scrollX + step
            scrollPosition.scrollTo(x: scrollX)
            scrolled(to: TabStripViewport(scrollX: scrollX, width: viewport.width))
        }
    }

    /// The left button was released: the tab settles into the slot it holds.
    private func drop() {
        withAnimation(slide) { drag = nil }
    }

    /// Esc during a drag: the tab goes back to the place it started. The selection stays.
    private func cancel() {
        guard let drag else { return }
        withAnimation(slide) {
            model.moveTab(drag.tab, to: drag.startPlace)
            self.drag = nil
        }
    }

    private func step(_ delta: Int) {
        guard let next = model.state.tab(steppingBy: delta) else { return }
        Task { await model.show(command: next) }
    }
}

private struct OutputTab: View {
    let command: CommandSnapshot
    let projectName: String
    let isActive: Bool
    /// False while any tab is dragged: tabs the pointer passes over get no hover highlight.
    let showsHover: Bool
    let model: WindowModel
    let onDrag: (_ pressX: Double, _ pointerX: Double) -> Void
    let onDrop: () -> Void
    let onCancel: () -> Void
    @State private var isHovering = false

    /// The close button's side, and its gap to the tab's right edge.
    private static let closeButton = TabPress.CloseButton(side: 16, trailing: 8)

    private var isHighlighted: Bool { isHovering && showsHover }

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
                    .frame(width: CGFloat(Self.closeButton.side), height: CGFloat(Self.closeButton.side))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Graphite.tertiary)
            .opacity(isActive || isHighlighted ? 1 : 0)
            .help("Close Tab")
            .accessibilityLabel("Close \(command.settings.name)")
        }
        .padding(.leading, 14)
        .padding(.trailing, CGFloat(Self.closeButton.trailing))
        .frame(minWidth: 150, maxHeight: .infinity)
        .background(isActive ? Graphite.canvas : isHighlighted ? Graphite.hover.opacity(0.5) : .clear)
        // The strip's own colour, so a dragged tab hides the tabs it passes over.
        .background(Graphite.chrome)
        .overlay(alignment: .top) {
            if isActive { Rectangle().fill(Graphite.accent).frame(height: 2) }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Graphite.line).frame(width: 1) }
        .contentShape(Rectangle())
        // A click selects, a sideways drag moves the tab, a middle click closes it. The close button
        // keeps its own clicks.
        .onTabPointer(
            closeButton: Self.closeButton,
            onClick: { Task { await model.show(command: command.id) } },
            onClose: { Task { await model.closeTab(command.id) } },
            onDrag: onDrag, onDrop: onDrop, onCancel: onCancel
        )
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(command.settings.name) in \(projectName), \(command.statusText)")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { Task { await model.show(command: command.id) } }
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
