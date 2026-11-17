import DevDevCore
import SwiftUI

/// The checklist Discovery ends in. Nothing changes until the user confirms it.
struct DiscoveryChecklistView: View {
    let model: WindowModel
    @State var checklist: DiscoveryChecklist
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(checklist.title)
                .font(.headline)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)
            if checklist.plan.isEmpty {
                ContentUnavailableView(
                    "Nothing to change", systemImage: "checkmark.circle",
                    description: Text("Discovery proposes no Command this Project lacks, and no Discovery-made Command is stale."))
                    .frame(minHeight: 160)
            } else {
                Form {
                    if checklist.asksAboutContainer {
                        Section {
                            Toggle(isOn: $checklist.runInContainer) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Run these Commands inside a Docker container")
                                    Text("Found \(checklist.dockerFiles.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            if checklist.runInContainer {
                                TextField("Container name", text: $checklist.containerName, prompt: Text("app"))
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                    if !checklist.plan.add.isEmpty {
                        Section("Add these Commands") {
                            ForEach(checklist.plan.add.indices, id: \.self) { index in
                                row(
                                    name: checklist.plan.add[index].settings.name,
                                    commandLine: checklist.plan.add[index].settings.commandLine,
                                    isOn: $checklist.addChecked[index])
                            }
                        }
                    }
                    if !checklist.plan.remove.isEmpty {
                        Section("Remove these Commands, no longer proposed") {
                            ForEach(checklist.plan.remove.indices, id: \.self) { index in
                                row(
                                    name: checklist.plan.remove[index].name,
                                    commandLine: checklist.plan.remove[index].commandLine,
                                    isOn: $checklist.removeChecked[index])
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    model.dismissDiscovery()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(checklist.plan.isEmpty ? "OK" : "Apply") {
                    let confirmed = checklist
                    dismiss()
                    Task { await model.applyDiscovery(confirmed) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!checklist.canApply)
            }
            .padding(16)
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 240)
    }

    private func row(name: String, commandLine: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(commandLine)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .toggleStyle(.checkbox)
    }
}
