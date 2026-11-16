import Foundation

/// The Helper socket protocol: one JSON object per line, in both directions.
///
/// A client sends `{"id": 1, "origin": "user", "request": {...}}`. The Helper answers with
/// `{"id": 1, "response": {...}}` and pushes `{"event": {...}}` lines whenever something changes.
public enum HelperProtocol {
    /// Raised whenever a message changes in a way an older program cannot read.
    public static let version = 1
}

public enum HelperRequest: Codable, Sendable, Equatable {
    /// Sent first. The answer carries the Helper's protocol version.
    case hello(protocolVersion: Int, client: String)
    case snapshot

    case start(commandID: UUID)
    case stop(commandID: UUID)
    case restart(commandID: UUID)
    case startAll(projectID: UUID)
    case stopAll(projectID: UUID)
    case restartAll(projectID: UUID)

    /// Stops every Process of every Project, then the Helper itself exits.
    case stopAllAndQuit

    /// Replays the stored output as one `outputReplay` event, then pushes `output` events.
    case subscribeOutput(commandID: UUID)
    case unsubscribeOutput(commandID: UUID)
    /// The stored output with escape sequences removed.
    case plainOutput(commandID: UUID, lastLines: Int?)
    case resize(commandID: UUID, columns: UInt16, rows: UInt16)

    case addProject(folder: String, name: String?)
    case renameProject(projectID: UUID, name: String)
    case removeProject(projectID: UUID)
    case addCommand(projectID: UUID, settings: CommandSettings, madeByDiscovery: Bool? = nil)
    case updateCommand(commandID: UUID, settings: CommandSettings)
    case deleteCommand(commandID: UUID)
    case moveCommand(commandID: UUID, toIndex: Int)

    /// The Settings the Helper stores. Answered with `settings`.
    case settings
    /// Saves the Settings and acts on them. Every client gets a `settings` event.
    case updateSettings(HelperSettings)

    /// True for requests that change Processes or configuration. They must carry an origin.
    public var changesState: Bool {
        switch self {
        case .hello, .snapshot, .subscribeOutput, .unsubscribeOutput, .plainOutput, .resize, .settings:
            false
        case .start, .stop, .restart, .startAll, .stopAll, .restartAll, .stopAllAndQuit, .addProject, .renameProject,
            .removeProject, .addCommand, .updateCommand, .deleteCommand, .moveCommand, .updateSettings:
            true
        }
    }

    /// True for requests that wait for a Process to end.
    var waitsForAProcess: Bool {
        switch self {
        case .stop, .restart, .stopAll, .restartAll, .stopAllAndQuit, .removeProject, .deleteCommand: true
        default: false
        }
    }
}

public enum HelperResponse: Codable, Sendable, Equatable {
    case hello(protocolVersion: Int, helperVersion: String)
    case ok
    case snapshot(HelperSnapshot)
    case command(CommandSnapshot)
    case project(ProjectSnapshot)
    case plainOutput(String)
    case settings(HelperSettings)
    case failure(HelperError)
}

struct RequestEnvelope: Codable {
    var id: Int
    var origin: Origin?
    var request: HelperRequest
}

/// A line from the Helper: a response when `id` is set, otherwise an event.
struct ServerEnvelope: Codable {
    var id: Int?
    var response: HelperResponse?
    var event: HelperEvent?
}

enum Wire {
    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from line: Data) -> T? {
        try? JSONDecoder().decode(type, from: line)
    }
}

extension HelperEngine {
    /// Answers one request from a client. `subscriber` is the client's event subscription.
    public nonisolated func respond(
        to request: HelperRequest, origin: Origin?, subscriber: UUID
    ) async -> HelperResponse {
        var actingOrigin = Origin.user
        if request.changesState {
            guard let origin else {
                return .failure(
                    HelperError(
                        code: HelperError.originRequired,
                        message: "A request that changes something must say who asks: user or agent."))
            }
            guard !origin.isInternal else {
                return .failure(
                    HelperError(
                        code: HelperError.originNotAllowed,
                        message: "Only the Helper may use the origin '\(origin.rawValue)'. Use user or agent."))
            }
            actingOrigin = origin
        }
        do {
            switch request {
            case .hello:
                return .hello(protocolVersion: HelperProtocol.version, helperVersion: helperVersion)
            case .snapshot:
                return .snapshot(await snapshot())
            case .start(let commandID):
                return .command(try await start(commandID, origin: actingOrigin))
            case .stop(let commandID):
                return .command(try await stop(commandID, origin: actingOrigin))
            case .restart(let commandID):
                return .command(try await restart(commandID, origin: actingOrigin))
            case .startAll(let projectID):
                return .project(try await startAll(projectID, origin: actingOrigin))
            case .stopAll(let projectID):
                return .project(try await stopAll(projectID, origin: actingOrigin))
            case .restartAll(let projectID):
                return .project(try await restartAll(projectID, origin: actingOrigin))
            case .stopAllAndQuit:
                await stopAllAndQuit(origin: actingOrigin)
                return .ok
            case .subscribeOutput(let commandID):
                try await subscribeOutput(commandID, subscriber: subscriber)
                return .ok
            case .unsubscribeOutput(let commandID):
                await unsubscribeOutput(commandID, subscriber: subscriber)
                return .ok
            case .plainOutput(let commandID, let lastLines):
                return .plainOutput(try await plainOutput(commandID, lastLines: lastLines))
            case .resize(let commandID, let columns, let rows):
                try await resize(commandID, to: TerminalSize(columns: columns, rows: rows))
                return .ok
            case .addProject(let folder, let name):
                return .project(try await addProject(folder: folder, name: name))
            case .renameProject(let projectID, let name):
                return .project(try await renameProject(projectID, name: name))
            case .removeProject(let projectID):
                try await removeProject(projectID, origin: actingOrigin)
                return .ok
            case .addCommand(let projectID, let settings, let madeByDiscovery):
                return .command(
                    try await addCommand(to: projectID, settings: settings, madeByDiscovery: madeByDiscovery ?? false))
            case .updateCommand(let commandID, let settings):
                return .command(try await updateCommand(commandID, settings: settings))
            case .deleteCommand(let commandID):
                try await deleteCommand(commandID, origin: actingOrigin)
                return .ok
            case .moveCommand(let commandID, let toIndex):
                return .project(try await moveCommand(commandID, toIndex: toIndex))
            case .settings:
                return .settings(await settings())
            case .updateSettings(let settings):
                return .settings(try await updateSettings(settings))
            }
        } catch let error as HelperError {
            return .failure(error)
        } catch {
            return .failure(HelperError(code: HelperError.invalid, message: error.localizedDescription))
        }
    }
}
