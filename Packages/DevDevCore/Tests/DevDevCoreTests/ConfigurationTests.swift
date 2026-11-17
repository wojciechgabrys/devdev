import Foundation
import Testing

@testable import DevDevCore

/// Saved configuration: Projects, Commands and edits.
@Suite struct ConfigurationTests {
    private func saved(_ h: Harness) throws -> Configuration {
        try h.store.load()
    }

    @Test func aNewProjectIsNamedAfterItsFolderAndSavedAtOnce() async throws {
        try await withHarness([]) { h in
            let project = try await h.project()
            #expect(project.name == "project")
            #expect(project.folder == h.projectFolder.path)
            #expect(project.status == .stopped)
            #expect(try saved(h).projects.map(\.folder) == [h.projectFolder.path])
        }
    }

    @Test func addingAFolderThatIsAlreadyAProjectGivesTheExistingProject() async throws {
        try await withHarness([]) { h in
            let again = try await h.engine.addProject(folder: h.projectFolder.path + "/", name: "Other name")
            #expect(again.id == h.projectID)
            #expect(again.name == "project")
            #expect(await h.engine.snapshot().projects.count == 1)
        }
    }

    @Test func aFolderThatDoesNotExistCannotBecomeAProject() async throws {
        try await withHarness([]) { h in
            await #expect(throws: HelperError.self) {
                try await h.engine.addProject(folder: h.folder.appendingPathComponent("nope").path)
            }
        }
    }

    @Test func aCommandKeepsEveryFieldAcrossASaveAndALoad() async throws {
        let settings = CommandSettings(
            name: "Queue",
            commandLine: "NODE_ENV=development npm run dev",
            subfolder: "frontend",
            environment: [EnvironmentVariable(name: "A", value: "1"), EnvironmentVariable(name: "B", value: "2")],
            includedInStartAll: false,
            autoRestart: true,
            restartWhenFilesChange: ["app/**/*.php", "config/*.php"],
            runInContainer: true,
            containerName: "laravel")
        try await withHarness([]) { h in
            let added = try await h.engine.addCommand(to: h.projectID, settings: settings, madeByDiscovery: true)
            let reloaded = try saved(h)
            #expect(reloaded.version == 1)
            let command = try #require(reloaded.projects.first?.commands.first)
            #expect(command.id == added.id)
            #expect(command.settings == settings)
            #expect(command.madeByDiscovery)

            // A Helper started on the saved file sees the same Command, Stopped.
            let second = HelperEngine(configuration: reloaded, store: h.store, shell: .plain)
            let snapshot = await second.snapshot()
            #expect(snapshot.command(added.id)?.settings == settings)
            #expect(snapshot.command(added.id)?.status == .stopped)
        }
    }

    @Test func aNewCommandIsIncludedInStartAllWithAutoRestartOff() {
        let settings = CommandSettings(name: "Vite", commandLine: "npm run dev")
        #expect(settings.includedInStartAll)
        #expect(!settings.autoRestart)
        #expect(settings.restartWhenFilesChange.isEmpty)
        #expect(settings.subfolder.isEmpty)
    }

    @Test func commandsKeepTheirOrderAndCanBeMoved() async throws {
        let commands = ["A", "B", "C"].map { CommandSettings(name: $0, commandLine: "true") }
        try await withHarness(commands) { h in
            #expect(try await h.project().commands.map(\.settings.name) == ["A", "B", "C"])
            let moved = try await h.engine.moveCommand(h.commandIDs[2], toIndex: 0)
            #expect(moved.commands.map(\.settings.name) == ["C", "A", "B"])
            #expect(try saved(h).projects[0].commands.map(\.settings.name) == ["C", "A", "B"])
        }
    }

    @Test func aCommandNameMustBeUniqueWithinItsProject() async throws {
        try await withHarness([CommandSettings(name: "Queue", commandLine: "true")]) { h in
            let error = await #expect(throws: HelperError.self) {
                try await h.engine.addCommand(
                    to: h.projectID, settings: CommandSettings(name: "queue", commandLine: "true"))
            }
            #expect(error?.message.contains("Queue") == true)
            let project = try await h.project()
            #expect(project.commands.count == 1)
        }
    }

    @Test func aCommandNeedsANameAndACommandLine() async throws {
        try await withHarness([]) { h in
            await #expect(throws: HelperError.self) {
                try await h.engine.addCommand(to: h.projectID, settings: CommandSettings(name: " ", commandLine: "x"))
            }
            await #expect(throws: HelperError.self) {
                try await h.engine.addCommand(to: h.projectID, settings: CommandSettings(name: "x", commandLine: ""))
            }
        }
    }

    @Test func aCommandThatRunsInAContainerNeedsAContainerName() async throws {
        try await withHarness([]) { h in
            let unnamed = CommandSettings(name: "Vite", commandLine: "npm run dev", runInContainer: true, containerName: " ")
            await #expect(throws: HelperError.self) {
                try await h.engine.addCommand(to: h.projectID, settings: unnamed)
            }
            // With the switch off, a blank name is fine: the Command runs on this Mac.
            var onTheMac = unnamed
            onTheMac.runInContainer = false
            _ = try await h.engine.addCommand(to: h.projectID, settings: onTheMac)
        }
    }

    @Test func anEditToARunningCommandIsSavedAtOnceDoesNotRestartItAndMarksItRestartToApplyUntilItsNextStart()
        async throws
    {
        try await withHarness("echo old; \(Script.runsForever)") { h in
            let started = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")
            #expect(!started.restartToApply)

            var edited = started.settings
            edited.commandLine = "echo new; \(Script.runsForever)"
            let after = try await h.engine.updateCommand(h.first, settings: edited)

            // Saved at once.
            #expect(try saved(h).projects[0].commands[0].settings.commandLine == edited.commandLine)
            // Not restarted.
            #expect(after.status == .running)
            #expect(after.processID == started.processID)
            #expect(processIsAlive(try #require(started.processID)))
            #expect(try await !h.plainOutput(h.first).contains("new"))
            // Marked, and the mark is in every snapshot.
            #expect(after.restartToApply)
            #expect(try await h.command(h.first).restartToApply)

            // The next start clears the mark and runs the new line.
            let restarted = try await h.engine.restart(h.first, origin: .user)
            #expect(!restarted.restartToApply)
            try await h.waitForOutput(h.first, containing: "new")
        }
    }

    @Test func theRestartToApplyMarkSurvivesAStopAndIsClearedByAStart() async throws {
        try await withHarness(Script.runsForever) { h in
            let started = try await h.engine.start(h.first, origin: .user)
            var edited = started.settings
            edited.environment = [EnvironmentVariable(name: "X", value: "1")]
            _ = try await h.engine.updateCommand(h.first, settings: edited)
            let stopped = try await h.engine.stop(h.first, origin: .user)
            #expect(stopped.restartToApply)
            #expect(try await !h.engine.start(h.first, origin: .user).restartToApply)
        }
    }

    @Test func anEditToACommandThatIsNotRunningNeedsNoRestart() async throws {
        try await withHarness("exit 0") { h in
            var edited = try await h.command(h.first).settings
            edited.commandLine = "exit 1"
            #expect(try await !h.engine.updateCommand(h.first, settings: edited).restartToApply)
        }
    }

    @Test func renamingARunningCommandNeedsNoRestart() async throws {
        try await withHarness(Script.runsForever) { h in
            let started = try await h.engine.start(h.first, origin: .user)
            var edited = started.settings
            edited.name = "Renamed"
            edited.autoRestart = true
            let after = try await h.engine.updateCommand(h.first, settings: edited)
            #expect(after.settings.name == "Renamed")
            #expect(!after.restartToApply)
        }
    }

    @Test func anEditByHandRemovesTheDiscoveryMark() async throws {
        try await withHarness([]) { h in
            let added = try await h.engine.addCommand(
                to: h.projectID, settings: CommandSettings(name: "serve", commandLine: "php artisan serve"),
                madeByDiscovery: true)
            #expect(added.madeByDiscovery)
            let same = try await h.engine.updateCommand(added.id, settings: added.settings)
            #expect(same.madeByDiscovery)
            var edited = added.settings
            edited.commandLine = "php artisan serve --port=8001"
            #expect(try await !h.engine.updateCommand(added.id, settings: edited).madeByDiscovery)
            #expect(try saved(h).projects[0].commands[0].madeByDiscovery == false)
        }
    }

    @Test func deletingARunningCommandStopsItThenDeletesIt() async throws {
        try await withHarness(Script.runsForever) { h in
            let started = try await h.engine.start(h.first, origin: .user)
            let pid = try #require(started.processID)

            try await h.engine.deleteCommand(h.first, origin: .user)

            #expect(!processIsAlive(pid))
            #expect(try await h.project().commands.isEmpty)
            #expect(try saved(h).projects[0].commands.isEmpty)
        }
    }

    @Test func removingAProjectStopsItsProcessesFirst() async throws {
        try await withHarness(Script.runsForever) { h in
            let started = try await h.engine.start(h.first, origin: .user)
            let pid = try #require(started.processID)

            try await h.engine.removeProject(h.projectID, origin: .user)

            #expect(!processIsAlive(pid))
            #expect(await h.engine.snapshot().projects.isEmpty)
            #expect(try saved(h).projects.isEmpty)
        }
    }

    @Test func everyConfigurationChangeIsPushedToSubscribers() async throws {
        try await withHarness([]) { h in
            let log = await EventLog.listening(to: h.engine)
            let added = try await h.engine.addCommand(
                to: h.projectID, settings: CommandSettings(name: "Vite", commandLine: "npm run dev"))
            _ = try await h.engine.renameProject(h.projectID, name: "Shop")
            try await waitUntil("two configuration events arrived") { await log.events.count == 2 }
            guard case .configuration(let first) = await log.events[0],
                case .configuration(let second) = await log.events[1]
            else {
                Issue.record("expected two configuration events")
                return
            }
            #expect(first.command(added.id)?.settings.name == "Vite")
            #expect(second.projects.map(\.name) == ["Shop"])
        }
    }

    @Test func aMissingConfigurationFileLoadsAsAnEmptyConfiguration() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ConfigurationStore(file: folder.appendingPathComponent("data/configuration.json"))
        #expect(try store.load() == Configuration())
        try store.save(Configuration(projects: [Project(name: "Shop", folder: "/tmp/shop")]))
        #expect(try store.load().projects.map(\.name) == ["Shop"])
    }
}
