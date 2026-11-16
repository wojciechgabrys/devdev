import Foundation

/// The status of one Command. See `GLOSSARY.md`.
public enum CommandStatus: String, Codable, Sendable, CaseIterable {
    case stopped
    case running
    case finished
    case crashed
}

/// The status of a Project, worked out from its Commands.
public enum ProjectStatus: String, Codable, Sendable, CaseIterable {
    case crashed
    case stopped
    case running
    case partlyRunning

    /// The Project status table of `docs/spec.md` section 4, in its evaluation order.
    public static func evaluate(_ commands: [(status: CommandStatus, includedInStartAll: Bool)]) -> ProjectStatus {
        if commands.contains(where: { $0.status == .crashed }) { return .crashed }
        if !commands.contains(where: { $0.status == .running }) { return .stopped }
        if commands.allSatisfy({ !$0.includedInStartAll || $0.status == .running }) { return .running }
        return .partlyRunning
    }
}

/// Who asked for a change. Clients send `user` or `agent`; the Helper adds the other two itself.
public enum Origin: String, Codable, Sendable, CaseIterable {
    case user
    case agent
    case autoRestart
    case fileChange

    /// True for the origins only the Helper may use.
    public var isInternal: Bool { self == .autoRestart || self == .fileChange }
}

public struct EnvironmentVariable: Codable, Sendable, Equatable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// The editable fields of a Command (`docs/spec.md` section 4).
public struct CommandSettings: Codable, Sendable, Equatable {
    public var name: String
    public var commandLine: String
    /// Relative to the Project folder. Empty means the Project folder.
    public var subfolder: String
    public var environment: [EnvironmentVariable]
    public var includedInStartAll: Bool
    public var autoRestart: Bool
    /// Glob patterns relative to the Project folder. Empty means off.
    public var restartWhenFilesChange: [String]

    public init(
        name: String,
        commandLine: String,
        subfolder: String = "",
        environment: [EnvironmentVariable] = [],
        includedInStartAll: Bool = true,
        autoRestart: Bool = false,
        restartWhenFilesChange: [String] = []
    ) {
        self.name = name
        self.commandLine = commandLine
        self.subfolder = subfolder
        self.environment = environment
        self.includedInStartAll = includedInStartAll
        self.autoRestart = autoRestart
        self.restartWhenFilesChange = restartWhenFilesChange
    }

    /// True when the two differ in a field that only takes effect at the next start.
    func runsDifferently(from other: CommandSettings) -> Bool {
        commandLine != other.commandLine || subfolder != other.subfolder || environment != other.environment
    }
}

public struct Command: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var settings: CommandSettings
    /// True while the Command is exactly as Discovery made it. A hand-written or edited Command is false.
    public var madeByDiscovery: Bool

    public init(id: UUID = UUID(), settings: CommandSettings, madeByDiscovery: Bool = false) {
        self.id = id
        self.settings = settings
        self.madeByDiscovery = madeByDiscovery
    }
}

public struct Project: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    /// Absolute path of the Project folder.
    public var folder: String
    /// In the user's order. Start All follows it.
    public var commands: [Command]

    public init(id: UUID = UUID(), name: String, folder: String, commands: [Command] = []) {
        self.id = id
        self.name = name
        self.folder = folder
        self.commands = commands
    }
}

/// Everything the Helper saves to disk.
public struct Configuration: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var projects: [Project]

    public init(version: Int = Configuration.currentVersion, projects: [Project] = []) {
        self.version = version
        self.projects = projects
    }
}

/// How a Process ended: an exit code, or the signal that ended it.
public struct ProcessExit: Codable, Sendable, Equatable {
    public var exitCode: Int32?
    public var signal: Int32?

    public static func exited(_ code: Int32) -> ProcessExit { ProcessExit(exitCode: code, signal: nil) }
    public static func signalled(_ signal: Int32) -> ProcessExit { ProcessExit(exitCode: nil, signal: signal) }

    /// Decodes the status value `waitpid` gives.
    init(waitStatus status: Int32) {
        let low = status & 0x7f
        if low == 0 {
            self = .exited((status >> 8) & 0xff)
        } else {
            self = .signalled(low)
        }
    }

    init(exitCode: Int32?, signal: Int32?) {
        self.exitCode = exitCode
        self.signal = signal
    }

    /// The status of a Command whose Process ended by itself this way.
    public var statusWhenEndedByItself: CommandStatus { exitCode == 0 ? .finished : .crashed }
}

/// Size of a pseudo-terminal in character cells.
public struct TerminalSize: Codable, Sendable, Equatable {
    public var columns: UInt16
    public var rows: UInt16

    public init(columns: UInt16, rows: UInt16) {
        self.columns = columns
        self.rows = rows
    }

    /// Used for a Process nobody is watching.
    public static let standard = TerminalSize(columns: 120, rows: 40)
}

/// Every wait the Helper makes, so tests can shorten them.
public struct Timings: Sendable, Equatable {
    /// Time between SIGTERM and SIGKILL when stopping.
    public var killEscalation: Duration
    /// Wait after a crash before an auto-restart.
    public var autoRestartDelay: Duration
    /// Window in which crashes are counted for pausing auto-restart.
    public var crashWindow: Duration
    /// Quiet time after a file change before a restart.
    public var fileChangeSettle: Duration
    /// Wait after an MCP start or restart before answering.
    public var mcpWait: Duration

    public init(
        killEscalation: Duration = .seconds(5),
        autoRestartDelay: Duration = .seconds(1),
        crashWindow: Duration = .seconds(60),
        fileChangeSettle: Duration = .milliseconds(500),
        mcpWait: Duration = .seconds(1)
    ) {
        self.killEscalation = killEscalation
        self.autoRestartDelay = autoRestartDelay
        self.crashWindow = crashWindow
        self.fileChangeSettle = fileChangeSettle
        self.mcpWait = mcpWait
    }

    public static let standard = Timings()
}

/// The shell that runs a command line. Tests swap in `/bin/sh`.
public struct Shell: Sendable, Equatable {
    public var executable: String
    /// Arguments placed before the command line, which is always the last argument.
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    /// The user's `$SHELL` as a login, interactive shell that runs the command line as a string.
    public static func userLogin(environment: [String: String] = ProcessInfo.processInfo.environment) -> Shell {
        let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        return Shell(executable: shell, arguments: ["-l", "-i", "-c"])
    }

    /// `/bin/sh -c`, with no profile files read.
    public static let plain = Shell(executable: "/bin/sh", arguments: ["-c"])
}
