import DevDevCore
import SwiftUI
import UniformTypeIdentifiers

/// The three columns: Projects, Commands, Output. It draws `WindowModel.state` and forwards clicks.
struct MainWindow: View {
    @Bindable var model: WindowModel

    var body: some View {
        VStack(spacing: 0) {
            if let notice = model.state.notice {
                NoticeBanner(notice: notice, model: model)
                Divider()
            }
            NavigationSplitView {
                ProjectsColumn(model: model)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            } content: {
                CommandsColumn(model: model)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 400)
            } detail: {
                OutputColumn(model: model)
            }
        }
        .task { await model.connect() }
        // A folder dragged onto the window becomes a Project. The Helper refuses anything else.
        .dropDestination(for: URL.self) { urls, _ in
            Task {
                for url in urls { await model.addProject(folder: url) }
            }
            return !urls.isEmpty
        }
        .sheet(
            item: Binding(
                get: { model.discoveryChecklist },
                set: { if $0 == nil { model.dismissDiscovery() } })
        ) { checklist in
            DiscoveryChecklistView(model: model, checklist: checklist)
        }
        .alert(
            "devdev",
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

/// The outdated-Helper and Helper-died banner. Text, label and action come from `DevDevCore`.
struct NoticeBanner: View {
    let notice: HelperNotice
    let model: WindowModel
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(notice.message)
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
            .disabled(isWorking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.yellow.opacity(0.12))
    }
}

/// The coloured dot beside a status.
struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
    }
}

extension CommandStatus {
    var color: Color {
        switch self {
        case .stopped: .secondary
        case .running: .green
        case .finished: .blue
        case .crashed: .red
        }
    }
}

extension ProjectStatus {
    var color: Color {
        switch self {
        case .stopped: .secondary
        case .running: .green
        case .partlyRunning: .orange
        case .crashed: .red
        }
    }
}
