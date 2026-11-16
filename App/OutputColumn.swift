import DevDevCore
import SwiftUI

/// The output of the selected Command, with its status and exit code.
struct OutputColumn: View {
    let model: WindowModel

    var body: some View {
        if let command = model.state.selectedCommand {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    StatusDot(color: command.status.color)
                    Text(command.settings.name)
                        .fontWeight(.medium)
                    Text(command.statusText)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
                #if canImport(SwiftTerm)
                    if let session = model.output {
                        TerminalOutputView(session: session) { columns, rows in
                            Task { await model.outputViewResized(columns: columns, rows: rows) }
                        }
                        // A new session means a new replay: start from an empty terminal.
                        .id(session.id)
                    } else {
                        Color(nsColor: .textBackgroundColor)
                    }
                #else
                    // SwiftTerm draws the output and there is no fallback for it.
                    ContentUnavailableView(
                        "Output is not shown in this build", systemImage: "terminal",
                        description: Text("SwiftTerm is not part of this build. See docs/spike-results.md."))
                #endif
            }
        } else {
            ContentUnavailableView("No Command selected", systemImage: "terminal")
        }
    }
}
