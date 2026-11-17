import DevDevCore
import SwiftUI
import UniformTypeIdentifiers

/// The sheets and questions any part of the window can raise. Owned by `MainWindow`.
@MainActor @Observable
final class WindowActions {
    var form: CommandFormTarget?
    var deleting: CommandSnapshot?
    var removing: ProjectSnapshot?
    var isPickingFolder = false
    var isGoToOpen = false
}

/// The Graphite window: title strip, project tree beside the tabbed output, status bar.
/// It draws `WindowModel.state` and forwards clicks.
struct MainWindow: View {
    @Bindable var model: WindowModel
    @State private var actions = WindowActions()

    var body: some View {
        VStack(spacing: 0) {
            TitleStrip(model: model, actions: actions)
            if let notice = model.state.notice {
                NoticeBanner(notice: notice, model: model)
            }
            HSplitView {
                ProjectTree(model: model, actions: actions)
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 380)
                OutputPane(model: model, actions: actions)
                    .frame(minWidth: 460, maxWidth: .infinity)
            }
            StatusBar(model: model)
        }
        .background(Graphite.canvas)
        .foregroundStyle(Graphite.text)
        .tint(Graphite.accent)
        .ignoresSafeArea(.container, edges: .top)
        .overlay {
            if actions.isGoToOpen {
                GoToCommand(model: model, isOpen: $actions.isGoToOpen)
            }
        }
        .focusedSceneValue(\.windowModel, model)
        .task { await model.connect() }
        // A folder dragged onto the window becomes a Project. The Helper refuses anything else.
        .dropDestination(for: URL.self) { urls, _ in
            Task {
                for url in urls { await model.addProject(folder: url) }
            }
            return !urls.isEmpty
        }
        .fileImporter(isPresented: $actions.isPickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await model.addProject(folder: url) }
            }
        }
        .sheet(item: $actions.form) { target in
            CommandForm(target: target, model: model)
        }
        .sheet(
            item: Binding(
                get: { model.discoveryChecklist },
                set: { if $0 == nil { Task { await model.dismissDiscovery() } } })
        ) { checklist in
            DiscoveryChecklistView(model: model, checklist: checklist)
        }
        .confirmationDialog(
            actions.deleting?.deleteConfirmation.title ?? "",
            isPresented: Binding(get: { actions.deleting != nil }, set: { if !$0 { actions.deleting = nil } }),
            presenting: actions.deleting
        ) { command in
            Button(command.deleteConfirmation.confirmLabel, role: .destructive) {
                Task { await model.deleteCommand(command.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { command in
            Text(command.deleteConfirmation.message)
        }
        .confirmationDialog(
            actions.removing?.removeConfirmation.title ?? "",
            isPresented: Binding(get: { actions.removing != nil }, set: { if !$0 { actions.removing = nil } }),
            presenting: actions.removing
        ) { project in
            Button(project.removeConfirmation.confirmLabel, role: .destructive) {
                Task { await model.removeProject(project.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text(project.removeConfirmation.message)
        }
        .alert(
            "DevDev",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// The strip where the title bar would be: room for the window buttons, the selected Command's
/// name in the middle, and the Go to Command field on the right. Dragging it moves the window.
struct TitleStrip: View {
    let model: WindowModel
    let actions: WindowActions
    static let height: CGFloat = 40

    var body: some View {
        ZStack {
            title
            HStack {
                Spacer()
                goToField
            }
            .padding(.trailing, 12)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Graphite.chrome)
        .background(TrafficLights(stripHeight: Self.height))
        .overlay(alignment: .bottom) { Rectangle().fill(Graphite.line).frame(height: 1) }
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
    }

    @ViewBuilder private var title: some View {
        if let command = model.state.selectedCommand, let project = model.state.selectedProject {
            (Text(command.settings.name).fontWeight(.semibold).foregroundStyle(Graphite.strong)
                + Text("  —  \(project.name)").foregroundStyle(Graphite.secondary))
                .font(.system(size: 12.5))
                .lineLimit(1)
        } else {
            Text("DevDev").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Graphite.secondary)
        }
    }

    private var goToField: some View {
        Button {
            actions.isGoToOpen = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 10.5, weight: .semibold))
                Text("Go to Command…")
                Spacer(minLength: 8)
                Text("⌘K")
                    .font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Graphite.hover))
            }
            .font(.system(size: 12))
            .foregroundStyle(Graphite.secondary)
            .padding(.horizontal, 9)
            .frame(width: 220, height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Graphite.raised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .keyboardShortcut("k", modifiers: .command)
        .help("Jump to any Command by name")
    }
}

/// The outdated-Helper and Helper-died banner. Text, label and action come from `DevDevCore`.
struct NoticeBanner: View {
    let notice: HelperNotice
    let model: WindowModel
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Graphite.amber)
            Text(notice.message)
                .font(.system(size: 12))
                .foregroundStyle(Graphite.strong)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(notice.actionLabel) {
                isWorking = true
                Task {
                    switch notice.action {
                    case .restartHelper: await model.restartHelper()
                    case .startHelper: await model.connect()
                    }
                    isWorking = false
                }
            }
            .controlSize(.small)
            .disabled(isWorking)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Graphite.amber.opacity(0.12))
        .overlay(alignment: .bottom) { Rectangle().fill(Graphite.line).frame(height: 1) }
    }
}

/// The strip along the bottom: how many Commands run or crashed, the Helper link, and how long
/// the selected Command has run.
struct StatusBar: View {
    let model: WindowModel

    var body: some View {
        let snapshot = model.state.snapshot
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                StatusGlyph(snapshot.runningCount > 0 ? CommandStatus.running : .stopped)
                Text("\(snapshot.runningCount) running")
            }
            .foregroundStyle(snapshot.runningCount > 0 ? Graphite.green : Graphite.secondary)
            if snapshot.crashedCount > 0 {
                HStack(spacing: 5) {
                    StatusGlyph(CommandStatus.crashed)
                    Text("\(snapshot.crashedCount) crashed")
                }
                .foregroundStyle(Graphite.red)
            }
            Text(model.state.linkLabel)
            Spacer()
            if let command = model.state.selectedCommand {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(
                        command.status == .running
                            ? "\(command.settings.name) up \(command.detail(now: context.date))"
                            : "\(command.settings.name) \(command.statusText.lowercased())")
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Graphite.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Graphite.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Graphite.line).frame(height: 1) }
    }
}
