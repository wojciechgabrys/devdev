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
        public var lastExit: ProcessExit?
        public var startedAt: Date?

        /// How long it has run, how it ended, or "stopped".
        public func detail(now: Date) -> String {
            CommandDetail.short(status: status, lastExit: lastExit, startedAt: startedAt, now: now)
        }
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
                        actions: CommandActions.available(for: command),
                        lastExit: command.lastExit,
                        startedAt: command.startedAt)
                })
        }
    }

    /// Commands Running right now, in every Project.
    public var runningCount: Int { rows.reduce(0) { $0 + $1.commands.count { $0.status == .running } } }
    /// Commands Crashed right now, in every Project.
    public var crashedCount: Int { rows.reduce(0) { $0 + $1.commands.count { $0.status == .crashed } } }

    /// The panel narrowed by the filter field. A Project whose name matches keeps all its Commands;
    /// otherwise it keeps the Commands whose name, together with the Project's name, holds every word.
    /// Projects left with no Commands are dropped. A blank filter changes nothing.
    public func filtered(by query: String) -> MenubarPanel {
        let words = CommandSearch.words(query)
        guard !words.isEmpty else { return self }
        var copy = self
        copy.rows = rows.compactMap { row in
            let project = row.name.lowercased()
            if words.allSatisfy(project.contains) { return row }
            var kept = row
            kept.commands = row.commands.filter { command in
                let name = command.name.lowercased()
                return words.allSatisfy { name.contains($0) || project.contains($0) }
            }
            return kept.commands.isEmpty ? nil : kept
        }
        return copy
    }

    /// The icon shows a badge while any Command is Crashed.
    public var showsCrashBadge: Bool {
        rows.contains { $0.commands.contains { $0.status == .crashed } }
    }
}
