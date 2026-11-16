import DevDevCore
import SwiftUI
import UniformTypeIdentifiers

/// The sidebar: every Project with its status, and add / remove.
struct ProjectsColumn: View {
    let model: WindowModel
    @State private var isPickingFolder = false
    @State private var removing: ProjectSnapshot?

    var body: some View {
        List(
            selection: Binding(
                get: { model.state.selectedProjectID },
                set: { id in Task { await model.select(project: id) } })
        ) {
            ForEach(model.state.projects) { project in
                HStack(spacing: 8) {
                    StatusDot(color: project.status.color)
                    Text(project.name)
                        .lineLimit(1)
                    Spacer()
                }
                .help("\(project.status.label) — \(project.folder)")
                .accessibilityLabel("\(project.name), \(project.status.label)")
                .tag(project.id)
                .contextMenu {
                    Button("Remove Project…", role: .destructive) { removing = project }
                        .disabled(!model.state.canAct)
                }
            }
        }
        .overlay {
            if model.state.projects.isEmpty {
                ContentUnavailableView(
                    "No Projects", systemImage: "folder.badge.plus",
                    description: Text("Add a folder with the + button, or drag one onto the window."))
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    isPickingFolder = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add a Project")
                Button {
                    removing = model.state.selectedProject
                } label: {
                    Image(systemName: "minus")
                }
                .help("Remove the selected Project")
                .disabled(model.state.selectedProject == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .disabled(!model.state.canAct)
            .padding(8)
        }
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await model.addProject(folder: url) }
            }
        }
        .confirmationDialog(
            removing?.removeConfirmation.title ?? "",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { project in
            Button(project.removeConfirmation.confirmLabel, role: .destructive) {
                Task { await model.removeProject(project.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text(project.removeConfirmation.message)
        }
    }
}
