import Foundation

/// One Command as clients see it: its saved fields plus what the Helper knows about its Process.
public struct CommandSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var projectID: UUID
    public var settings: CommandSettings
    public var madeByDiscovery: Bool
    public var status: CommandStatus
    /// How the last Process ended. Nil while Running and before the first run.
    public var lastExit: ProcessExit?
    /// True when the Command was edited while Running and still runs the old settings.
    public var restartToApply: Bool
    public var startedAt: Date?
    public var processID: Int32?
}

public struct ProjectSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var folder: String
    public var status: ProjectStatus
    public var commands: [CommandSnapshot]
}

public struct HelperSnapshot: Codable, Sendable, Equatable {
    public var projects: [ProjectSnapshot]

    public func project(_ id: UUID) -> ProjectSnapshot? {
        projects.first { $0.id == id }
    }

    public func command(_ id: UUID) -> CommandSnapshot? {
        for project in projects {
            if let command = project.commands.first(where: { $0.id == id }) { return command }
        }
        return nil
    }
}

/// Why a Command's status changed.
public enum StatusCause: String, Codable, Sendable {
    case started
    case restarted
    /// A requested stop.
    case stopped
    /// The stop half of a restart. A `restarted` change follows.
    case stoppedForRestart
    /// The Process ended by itself with exit code 0.
    case finished
    /// The Process ended by itself with a non-zero exit code or a signal, or could not start.
    case crashed
    /// Stop on a Crashed or Finished Command: it is now Stopped. No Process was involved.
    case cleared
}

/// The whole-Project action a status change was part of.
public enum ProjectAction: String, Codable, Sendable {
    case startAll
    case stopAll
    case restartAll
}

public struct StatusChange: Codable, Sendable, Equatable {
    public var command: CommandSnapshot
    public var projectStatus: ProjectStatus
    public var cause: StatusCause
    /// Who asked. Nil when the Process ended by itself.
    public var origin: Origin?
    public var projectAction: ProjectAction?
}

public struct OutputChunk: Codable, Sendable, Equatable {
    public var commandID: UUID
    public var data: Data
}

/// What the Helper pushes to its clients.
public enum HelperEvent: Codable, Sendable, Equatable {
    case status(StatusChange)
    /// Projects or Commands were added, edited, moved or removed.
    case configuration(HelperSnapshot)
    /// The stored output of a Command, sent once after subscribing to it.
    case outputReplay(OutputChunk)
    /// New output of a Command the client subscribed to.
    case output(OutputChunk)
}

/// An error the Helper reports. `message` is a sentence fit to show.
public struct HelperError: Error, Codable, Sendable, Equatable, CustomStringConvertible {
    public var code: String
    public var message: String

    public var description: String { message }

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public static let unknownProject = "unknownProject"
    public static let unknownCommand = "unknownCommand"
    public static let invalid = "invalid"
    public static let saveFailed = "saveFailed"
    public static let originRequired = "originRequired"
    public static let originNotAllowed = "originNotAllowed"
    public static let unknownRequest = "unknownRequest"
    public static let connectionClosed = "connectionClosed"
    public static let connectionFailed = "connectionFailed"
    public static let alreadyRunning = "alreadyRunning"
}
