import AppKit
import DevDevCore
import SwiftUI

/// The Settings window. The Helper stores every setting; this only shows and forwards them.
struct SettingsView: View {
    let model: WindowModel

    /// Which `devdev` binary the line names is decided in `DevDevCore` (`MCPSetup`).
    private let mcpLine = MCPSetup.line(flavor: BuildFlavor.current(), appBundle: Bundle.main.bundleURL)

    var body: some View {
        Form {
            if let settings = model.settings {
                Section {
                    Toggle(
                        "Show menubar icon",
                        isOn: Binding(
                            get: { settings.showMenubarIcon },
                            set: { on in Task { await model.setShowMenubarIcon(on) } }))
                    Text("When off, the Helper keeps running and your Processes carry on. It just has no icon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(
                        "Launch at login",
                        isOn: Binding(
                            get: { settings.launchAtLogin },
                            set: { on in Task { await model.setLaunchAtLogin(on) } }))
                    Text("Starts the Helper from /Applications/devdev.app when you log in. It never starts a Process.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Notifications") {
                    ForEach(NotificationKind.allCases, id: \.self) { kind in
                        Toggle(
                            kind.settingsLabel,
                            isOn: Binding(
                                get: { settings.notifications[kind] },
                                set: { on in Task { await model.setNotification(kind, on: on) } }))
                    }
                    Text("A click in devdev never sends Started, Restarted or Stopped. Crashed and Finished always do.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Settings show once devdev is connected to the Helper.")
                    .foregroundStyle(.secondary)
            }
            Section("MCP") {
                Text("Run this in Terminal to let Claude Code control and read your Commands:")
                HStack(alignment: .top) {
                    Text(mcpLine)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(mcpLine, forType: .string)
                    }
                }
                Text("Agents can start, stop, restart and read output. They cannot add, edit or delete anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension NotificationKind {
    fileprivate var settingsLabel: String {
        switch self {
        case .crashed: "Crashed"
        case .started: "Started"
        case .restarted: "Restarted"
        case .stoppedOrFinished: "Stopped or Finished"
        }
    }
}
