import Foundation

/// The App's connection to the Helper, as the window shows it.
public enum HelperLink: Sendable, Equatable {
    case connecting
    case connected
    /// The connection was lost without the App asking for it. The Helper's Processes died with it.
    case died
    /// The Helper could not be started or reached. The text says why.
    case unavailable(String)
}

/// The banner at the top of the main window.
public struct HelperNotice: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case restartHelper
        case startHelper
    }

    public var message: String
    public var actionLabel: String
    public var action: Action
}

/// A question the App asks before it removes something.
public struct Confirmation: Sendable, Equatable {
    public var title: String
    public var message: String
    public var confirmLabel: String
}

/// Which buttons of one Command do something right now.
public struct CommandActions: Sendable, Equatable {
    public var start: Bool
    public var restart: Bool
    public var stop: Bool

    public init(start: Bool, restart: Bool, stop: Bool) {
        self.start = start
        self.restart = restart
        self.stop = stop
    }
}

/// Which "All" buttons of one Project do something right now.
public struct ProjectActions: Sendable, Equatable {
    public var startAll: Bool
    public var restartAll: Bool
    public var stopAll: Bool

    public init(startAll: Bool, restartAll: Bool, stopAll: Bool) {
        self.startAll = startAll
        self.restartAll = restartAll
        self.stopAll = stopAll
    }
}

/// Everything the main window shows, worked out from what the Helper reports. Views only draw it.
public struct WindowState: Sendable, Equatable {
    public private(set) var link = HelperLink.connecting
    public private(set) var compatibility = HelperCompatibility.current
    public private(set) var snapshot = HelperSnapshot(projects: [])
    public private(set) var selectedProjectID: UUID?
    public private(set) var selectedCommandID: UUID?

    public init() {}

    static func connected(compatibility: HelperCompatibility) -> WindowState {
        var state = WindowState()
        state.connected(snapshot: HelperSnapshot(projects: []), compatibility: compatibility)
        return state
    }

    // MARK: - Reading

    public var projects: [ProjectSnapshot] { snapshot.projects }
    public var selectedProject: ProjectSnapshot? { selectedProjectID.flatMap(snapshot.project) }
    public var selectedCommand: CommandSnapshot? {
        guard let command = selectedCommandID.flatMap(snapshot.command), command.projectID == selectedProjectID else {
            return nil
        }
        return command
    }

    /// True when a click can reach a Helper that understands it.
    public var canAct: Bool { link == .connected && compatibility.allowsRequests }

    public var notice: HelperNotice? {
        let restartLabel = "Restart Helper (stops all Processes)"
        switch link {
        case .connecting:
            return nil
        case .died:
            return HelperNotice(
                message: "The Helper stopped. Its Processes stopped with it, so everything shows as Stopped.",
                actionLabel: "Start Helper", action: .startHelper)
        case .unavailable(let reason):
            return HelperNotice(message: reason, actionLabel: "Try Again", action: .startHelper)
        case .connected:
            switch compatibility {
            case .current:
                return nil
            case .outdated:
                return HelperNotice(
                    message:
                        "The running Helper is outdated: it comes from another build of devdev. "
                        + "It keeps working. Restart it to use this build.",
                    actionLabel: restartLabel, action: .restartHelper)
            case .incompatible(let helperProtocol, let appProtocol):
                return HelperNotice(
                    message:
                        "The running Helper is outdated: it speaks protocol version \(helperProtocol) and this "
                        + "App speaks version \(appProtocol). The App cannot control it until the Helper restarts. "
                        + "Its Processes keep running.",
                    actionLabel: restartLabel, action: .restartHelper)
            }
        }
    }

    public func actions(for command: CommandSnapshot) -> CommandActions {
        guard canAct else { return CommandActions(start: false, restart: false, stop: false) }
        return CommandActions(
            start: command.status != .running, restart: true, stop: command.status != .stopped)
    }

    public func actions(for project: ProjectSnapshot) -> ProjectActions {
        guard canAct else { return ProjectActions(startAll: false, restartAll: false, stopAll: false) }
        return ProjectActions(
            startAll: project.commands.contains { $0.settings.includedInStartAll && $0.status != .running },
            restartAll: project.commands.contains { $0.status == .running },
            stopAll: project.commands.contains { $0.status != .stopped })
    }

    // MARK: - Changing

    public mutating func connecting() {
        link = .connecting
    }

    public mutating func connected(snapshot: HelperSnapshot, compatibility: HelperCompatibility) {
        link = .connected
        self.compatibility = compatibility
        self.snapshot = snapshot
        repairSelection()
    }

    public mutating func helperUnavailable(_ reason: String) {
        link = .unavailable(reason)
        snapshot = snapshot.withEverythingStopped
    }

    /// The Helper's Processes die with it, so everything is shown as Stopped.
    public mutating func helperDied() {
        link = .died
        snapshot = snapshot.withEverythingStopped
    }

    public mutating func apply(_ event: HelperEvent) {
        guard link == .connected else { return }
        switch event {
        case .configuration(let new):
            snapshot = new
            repairSelection()
        case .status(let change):
            guard
                let projectIndex = snapshot.projects.firstIndex(where: { $0.id == change.command.projectID }),
                let commandIndex = snapshot.projects[projectIndex].commands.firstIndex(where: {
                    $0.id == change.command.id
                })
            else { return }
            snapshot.projects[projectIndex].commands[commandIndex] = change.command
            snapshot.projects[projectIndex].status = change.projectStatus
        case .output, .outputReplay:
            break
        }
    }

    /// Shows a Project the Helper just answered with, before its configuration event arrives.
    public mutating func include(_ project: ProjectSnapshot) {
        guard link == .connected, snapshot.project(project.id) == nil else { return }
        snapshot.projects.append(project)
    }

    public mutating func select(project id: UUID?) {
        guard id != selectedProjectID else { return }
        selectedProjectID = id
        selectedCommandID = nil
        repairSelection()
    }

    public mutating func select(command id: UUID?) {
        selectedCommandID = id
        repairSelection()
    }

    /// Keeps the selection on things that exist: the first Project, and the first Command of the Project.
    private mutating func repairSelection() {
        if selectedProject == nil {
            selectedProjectID = snapshot.projects.first?.id
        }
        if selectedCommand == nil {
            selectedCommandID = selectedProject?.commands.first?.id
        }
    }
}

extension HelperSnapshot {
    /// The same Projects and Commands with no Process anywhere.
    var withEverythingStopped: HelperSnapshot {
        var copy = self
        for projectIndex in copy.projects.indices {
            copy.projects[projectIndex].status = .stopped
            for commandIndex in copy.projects[projectIndex].commands.indices {
                copy.projects[projectIndex].commands[commandIndex].status = .stopped
                copy.projects[projectIndex].commands[commandIndex].lastExit = nil
                copy.projects[projectIndex].commands[commandIndex].restartToApply = false
                copy.projects[projectIndex].commands[commandIndex].startedAt = nil
                copy.projects[projectIndex].commands[commandIndex].processID = nil
            }
        }
        return copy
    }
}

extension CommandStatus {
    /// The word from `GLOSSARY.md`.
    public var label: String {
        switch self {
        case .stopped: "Stopped"
        case .running: "Running"
        case .finished: "Finished"
        case .crashed: "Crashed"
        }
    }
}

extension ProjectStatus {
    /// The word from `GLOSSARY.md`.
    public var label: String {
        switch self {
        case .crashed: "Crashed"
        case .stopped: "Stopped"
        case .running: "Running"
        case .partlyRunning: "Partly Running"
        }
    }
}

extension CommandSnapshot {
    /// The status, with how the Process ended when it ended by itself.
    public var statusText: String {
        guard status == .finished || status == .crashed, let lastExit else { return status.label }
        if let code = lastExit.exitCode { return "\(status.label) (exit code \(code))" }
        return "\(status.label) (signal \(lastExit.signal ?? 0))"
    }

    public var deleteConfirmation: Confirmation {
        let running = status == .running
        return Confirmation(
            title: "Delete the Command “\(settings.name)”?",
            message: running
                ? "It is Running. It will be stopped first, then deleted." : "Its saved settings and output are lost.",
            confirmLabel: running ? "Stop and Delete" : "Delete")
    }
}

extension ProjectSnapshot {
    public var removeConfirmation: Confirmation {
        let running = commands.filter { $0.status == .running }.count
        let stopping =
            running == 0
            ? "" : "\(running) Running Command\(running == 1 ? "" : "s") will be stopped first. "
        return Confirmation(
            title: "Remove the Project “\(name)”?",
            message: "\(stopping)Its Commands are removed from devdev. The folder on disk is not touched.",
            confirmLabel: running == 0 ? "Remove" : "Stop and Remove")
    }
}

/// The Command form as the user types it.
public struct CommandDraft: Sendable, Equatable {
    public var name = ""
    public var commandLine = ""
    public var subfolder = ""
    public var environment: [EnvironmentVariable] = []
    public var includedInStartAll = true
    public var autoRestart = false
    /// One glob pattern per line.
    public var restartWhenFilesChange = ""

    public init() {}

    public init(_ settings: CommandSettings) {
        name = settings.name
        commandLine = settings.commandLine
        subfolder = settings.subfolder
        environment = settings.environment
        includedInStartAll = settings.includedInStartAll
        autoRestart = settings.autoRestart
        restartWhenFilesChange = settings.restartWhenFilesChange.joined(separator: "\n")
    }

    /// The settings to send. Blank variable names and blank pattern lines are dropped. The Helper checks the rest.
    public var settings: CommandSettings {
        CommandSettings(
            name: name,
            commandLine: commandLine,
            subfolder: subfolder.trimmingCharacters(in: .whitespaces),
            environment: environment.compactMap {
                let name = $0.name.trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : EnvironmentVariable(name: name, value: $0.value)
            },
            includedInStartAll: includedInStartAll,
            autoRestart: autoRestart,
            restartWhenFilesChange: restartWhenFilesChange.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
    }
}

/// Turns a drag in a list into the index `moveCommand` takes.
public enum CommandMove {
    /// `toOffset` counts rows with the dragged one still in place. The Helper counts them without it.
    public static func targetIndex(from: Int, toOffset: Int) -> Int {
        toOffset > from ? toOffset - 1 : toOffset
    }
}
