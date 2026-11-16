import Foundation
import Testing

@testable import DevDevCore

struct TimedOut: Error, CustomStringConvertible {
    var description: String
}

/// Polls until the condition holds. Fails the test when it does not hold in time.
func waitUntil(
    _ what: String,
    timeout: Duration = .seconds(10),
    isolation: isolated (any Actor)? = #isolation,
    _ condition: () async throws -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw TimedOut(description: "timed out waiting until \(what)")
}

/// True while a process with this ID exists and is not a zombie waiting to be collected.
func processIsAlive(_ pid: Int32) -> Bool {
    guard kill(pid, 0) == 0 else { return false }
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
    return info.pbi_status != UInt32(SZOMB)
}

/// A short temporary folder. Unix socket paths must stay under about 104 bytes.
func makeTemporaryFolder() throws -> URL {
    let folder = URL(fileURLWithPath: "/tmp/dd-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// A Helper engine on a temporary folder, with one Project whose Commands run through `/bin/sh`.
struct Harness {
    let folder: URL
    let projectFolder: URL
    let store: ConfigurationStore
    let engine: HelperEngine
    let projectID: UUID
    let commandIDs: [UUID]

    var first: UUID { commandIDs[0] }

    func command(_ id: UUID) async throws -> CommandSnapshot {
        try #require(await engine.snapshot().command(id))
    }

    func status(_ id: UUID) async throws -> CommandStatus {
        try await command(id).status
    }

    func project() async throws -> ProjectSnapshot {
        try #require(await engine.snapshot().project(projectID))
    }

    func plainOutput(_ id: UUID) async throws -> String {
        try await engine.plainOutput(id, lastLines: nil)
    }

    func waitForStatus(_ id: UUID, _ status: CommandStatus) async throws {
        try await waitUntil("the Command is \(status)") { try await self.status(id) == status }
    }

    func waitForOutput(_ id: UUID, containing text: String) async throws {
        try await waitUntil("the output contains \(text)") { try await plainOutput(id).contains(text) }
    }
}

/// Runs the body with a fresh `Harness`, then stops every Process and removes the folder.
func withHarness(
    _ commands: [CommandSettings],
    timings: Timings = Timings(killEscalation: .seconds(3)),
    shell: Shell = .plain,
    poster: (any NotificationPoster)? = nil,
    isolation: isolated (any Actor)? = #isolation,
    _ body: (Harness) async throws -> Void
) async throws {
    let folder = try makeTemporaryFolder()
    let projectFolder = folder.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
    let store = ConfigurationStore(file: folder.appendingPathComponent("configuration.json"))
    let engine = HelperEngine(
        configuration: Configuration(), store: store, shell: shell, timings: timings, notifications: poster)
    let project = try await engine.addProject(folder: projectFolder.path)
    var ids: [UUID] = []
    for settings in commands {
        ids.append(try await engine.addCommand(to: project.id, settings: settings).id)
    }
    let harness = Harness(
        folder: folder, projectFolder: projectFolder, store: store, engine: engine,
        projectID: project.id, commandIDs: ids)
    do {
        try await body(harness)
    } catch {
        await engine.stopEverything(origin: .user)
        try? FileManager.default.removeItem(at: folder)
        throw error
    }
    await engine.stopEverything(origin: .user)
    try? FileManager.default.removeItem(at: folder)
}

func withHarness(
    _ commandLine: String,
    timings: Timings = Timings(killEscalation: .seconds(3)),
    isolation: isolated (any Actor)? = #isolation,
    _ body: (Harness) async throws -> Void
) async throws {
    try await withHarness([CommandSettings(name: "Main", commandLine: commandLine)], timings: timings, body)
}

/// Collects the events one subscriber is sent.
actor EventLog {
    private(set) var events: [HelperEvent] = []

    func add(_ event: HelperEvent) { events.append(event) }

    var statusChanges: [StatusChange] {
        events.compactMap { if case .status(let change) = $0 { change } else { nil } }
    }

    static func listening(to engine: HelperEngine) async -> EventLog {
        let log = EventLog()
        let subscription = await engine.subscribe()
        Task {
            for await event in subscription.events { await log.add(event) }
        }
        return log
    }
}

/// Scripts used as command lines.
enum Script {
    static let runsForever = "echo ready; while :; do sleep 0.1; done"
    static func exitsOnTerm(code: Int) -> String { "trap 'exit \(code)' TERM; \(runsForever)" }
    static let ignoresTerm = "trap '' TERM; \(runsForever)"
}
