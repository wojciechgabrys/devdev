import DevDevCore
import SwiftUI

/// The Settings window. The Helper stores every setting; this only shows and forwards them.
/// Later phases add notifications and MCP.
struct SettingsView: View {
    let model: WindowModel

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
            } else {
                Text("Settings show once devdev is connected to the Helper.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
