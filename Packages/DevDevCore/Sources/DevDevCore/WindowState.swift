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

    /// The buttons that do something for the Command in its current status.
    public static func available(for command: CommandSnapshot) -> CommandActions {
        CommandActions(start: command.status != .running, restart: true, stop: command.status != .stopped)
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

    /// The "All" buttons that do something for the Project in its current state (`docs/spec.md` section 4).
    public static func available(for project: ProjectSnapshot) -> ProjectActions {
        ProjectActions(
            startAll: project.commands.contains { $0.settings.includedInStartAll && $0.status != .running },
            restartAll: project.commands.contains { $0.status == .running },
            stopAll: project.commands.contains { $0.status != .stopped })
    }
}

/// Everything the main window shows, worked out from what the Helper reports. Views only draw it.
public struct WindowState: Sendable, Equatable {
    public private(set) var link = HelperLink.connecting
    public private(set) var compatibility = HelperCompatibility.current
    public private(set) var snapshot = HelperSnapshot(projects: [])
    public private(set) var selectedProjectID: UUID?
    public private(set) var selectedCommandID: UUID?
    /// The output tabs, left to right. The selected Command always has one. Tabs may hold
    /// Commands of other Projects; selecting such a tab selects its Project too.
    public private(set) var tabs: [UUID] = []
    /// A link that arrived before the Helper's state did. Applied once it arrives.
    private var pendingLink: OpenLink?

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
                        "The running Helper is outdated: it comes from another build of DevDev. "
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
        return CommandActions.available(for: command)
    }

    public func actions(for project: ProjectSnapshot) -> ProjectActions {
        guard canAct else { return ProjectActions(startAll: false, restartAll: false, stopAll: false) }
        return ProjectActions.available(for: project)
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
        if let link = pendingLink {
            pendingLink = nil
            open(link)
        }
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
            snapshot.apply(change)
        case .output, .outputReplay, .settings:
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

    /// Selects what the link points at. A link to a Command that does not exist changes nothing.
    public mutating func open(_ openLink: OpenLink) {
        switch openLink {
        case .command(let id):
            guard let command = snapshot.command(id) else {
                if link != .connected { pendingLink = openLink }
                return
            }
            selectedProjectID = command.projectID
            selectedCommandID = command.id
            openTab(command.id)
        }
    }

    /// Shows a tab's Command, from whichever Project it belongs to.
    public mutating func select(tab id: UUID) {
        open(.command(id))
    }

    /// Closes a tab. Closing the selected one selects the tab to its right, else the one to its left.
    /// Closing the last tab leaves no Command selected until the user picks one.
    public mutating func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(of: id) else { return }
        tabs.remove(at: index)
        guard id == selectedCommandID else { return }
        if tabs.isEmpty {
            selectedCommandID = nil
        } else {
            open(.command(tabs[min(index, tabs.count - 1)]))
        }
    }

    /// Moves a tab to a place counted from the left, starting at 0. The tabs between slide over by one.
    /// A place outside the list means the first or the last place. An unknown tab changes nothing.
    /// Only the order changes: the selection stays as it is.
    public mutating func moveTab(_ id: UUID, to index: Int) {
        guard let from = tabs.firstIndex(of: id) else { return }
        let place = min(max(index, 0), tabs.count - 1)
        guard place != from else { return }
        tabs.remove(at: from)
        tabs.insert(id, at: place)
    }

    /// The tab Cmd-1 to Cmd-9 show, counting from the left. Cmd-0 (number 0) shows the last tab.
    /// Nil when there is no tab with that number.
    public func tab(number: Int) -> UUID? {
        if number == 0 { return tabs.last }
        return tabs.indices.contains(number - 1) ? tabs[number - 1] : nil
    }

    /// The tab Cmd-Shift-] (`delta` 1) and Cmd-Shift-[ (`delta` -1) show: the neighbour of the
    /// selected tab in the order shown, wrapping at the ends. Nil when no tab is open.
    public func tab(steppingBy delta: Int) -> UUID? {
        guard !tabs.isEmpty else { return nil }
        let current = selectedCommandID.flatMap(tabs.firstIndex(of:)) ?? 0
        return tabs[((current + delta) % tabs.count + tabs.count) % tabs.count]
    }

    /// What Cmd-W closes.
    public enum CloseTarget: Equatable, Sendable {
        case tab(UUID)
        case window
    }

    /// Cmd-W closes the selected tab. With no tab open it closes the window.
    public var closeTarget: CloseTarget {
        if let id = selectedCommandID, tabs.contains(id) { return .tab(id) }
        return .window
    }

    private mutating func openTab(_ id: UUID) {
        if !tabs.contains(id) { tabs.append(id) }
    }

    /// The Helper connection in a few words, for the status bar.
    public var linkLabel: String {
        switch link {
        case .connecting: "Connecting to the Helper…"
        case .died: "Helper stopped"
        case .unavailable: "Helper unavailable"
        case .connected:
            switch compatibility {
            case .current: "Helper connected"
            case .outdated: "Helper outdated"
            case .incompatible: "Helper incompatible"
            }
        }
    }

    public mutating func select(command id: UUID?) {
        selectedCommandID = id
        repairSelection()
    }

    /// Keeps the selection on things that exist: the first Project, and the first Command of the Project.
    private mutating func repairSelection() {
        tabs.removeAll { snapshot.command($0) == nil }
        if selectedProject == nil {
            selectedProjectID = snapshot.projects.first?.id
        }
        if selectedCommand == nil {
            selectedCommandID = selectedProject?.commands.first?.id
        }
        if let selectedCommandID { openTab(selectedCommandID) }
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
            message: "\(stopping)Its Commands are removed from DevDev. The folder on disk is not touched.",
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
    public var runInContainer = false
    public var containerName = ""

    public init() {}

    public init(_ settings: CommandSettings) {
        name = settings.name
        commandLine = settings.commandLine
        subfolder = settings.subfolder
        environment = settings.environment
        includedInStartAll = settings.includedInStartAll
        autoRestart = settings.autoRestart
        restartWhenFilesChange = settings.restartWhenFilesChange.joined(separator: "\n")
        runInContainer = settings.runInContainer
        containerName = settings.containerName
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
                .filter { !$0.isEmpty },
            runInContainer: runInContainer,
            containerName: containerName.trimmingCharacters(in: .whitespaces))
    }
}
