import SwiftUI

/// The Settings window. Later phases fill it: the menubar icon, launch at login, notifications and MCP.
struct SettingsView: View {
    var body: some View {
        Form {
            Text("There are no settings yet.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 200)
    }
}
