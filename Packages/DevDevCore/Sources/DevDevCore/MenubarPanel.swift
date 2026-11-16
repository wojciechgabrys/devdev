import Foundation

/// Everything the menubar icon and its panel show, worked out from the Helper's state.
/// The panel view only draws it (`docs/spec.md` section 8). There is no output in the panel.
public struct MenubarPanel: Sendable, Equatable {
    /// One Command inside an expanded Project row.
    public struct CommandRow: Sendable, Equatable, Identifiable {
        public var id: UUID
        public var name: String
        public var status: CommandStatus
        /// The status word, with the exit code when the Process ended by itself.
        public var statusText: String
        public var actions: CommandActions
    }

    /// One Project: name, status and the three "All" buttons. Expanding it shows its Commands.
    public struct ProjectRow: Sendable, Equatable, Identifiable {
        public var id: UUID
        public var name: String
        public var status: ProjectStatus
        public var statusLabel: String
        public var actions: ProjectActions
        public var commands: [CommandRow]
    }

    public var rows: [ProjectRow]

    public init(snapshot: HelperSnapshot) {
        rows = snapshot.projects.map { project in
            ProjectRow(
                id: project.id,
                name: project.name,
                status: project.status,
                statusLabel: project.status.label,
                actions: ProjectActions.available(for: project),
                commands: project.commands.map { command in
                    CommandRow(
                        id: command.id,
                        name: command.settings.name,
                        status: command.status,
                        statusText: command.statusText,
                        actions: CommandActions.available(for: command))
                })
        }
    }

    /// The icon shows a badge while any Command is Crashed.
    public var showsCrashBadge: Bool {
        rows.contains { $0.commands.contains { $0.status == .crashed } }
    }
}
