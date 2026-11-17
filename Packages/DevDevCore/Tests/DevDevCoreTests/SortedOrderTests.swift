import Foundation
import Testing

@testable import DevDevCore

/// Projects and Commands are always in order of name. The Helper keeps them so.
@Suite struct SortedOrderTests {
    private func settings(_ name: String, _ line: String = "true") -> CommandSettings {
        CommandSettings(name: name, commandLine: line)
    }

    private func commandNames(_ h: Harness) async throws -> [String] {
        try await h.project().commands.map(\.settings.name)
    }

    private func savedCommandNames(_ h: Harness) throws -> [String] {
        let project = try #require(try h.store.load().projects.first { $0.id == h.projectID })
        return project.commands.map(\.settings.name)
    }

    /// Makes the folder inside the harness folder and adds it as a Project with this name.
    private func addProject(_ h: Harness, folder: String, name: String) async throws -> ProjectSnapshot {
        let url = h.folder.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return try await h.engine.addProject(folder: url.path, name: name)
    }

    // MARK: - The rule

    @Test func namesCompareWithoutRegardToCase() {
        #expect(["cron", "Build", "api"].sorted(by: NameOrder.areInIncreasingOrder) == ["api", "Build", "cron"])
        #expect(["Cron", "build", "API"].sorted(by: NameOrder.areInIncreasingOrder) == ["API", "build", "Cron"])
    }

    @Test func numbersInsideNamesCompareByValue() {
        #expect(
            ["worker 10", "worker 2", "worker 1"].sorted(by: NameOrder.areInIncreasingOrder)
                == ["worker 1", "worker 2", "worker 10"])
    }

    @Test func aConfigurationSortsItsProjectsAndEveryProjectsCommandsWithTheOneRule() {
        let configuration = Configuration(projects: [
            Project(
                name: "shop 10", folder: "/tmp/c",
                commands: ["cron", "Build", "api"].map { Command(settings: settings($0)) }),
            Project(name: "Shop 2", folder: "/tmp/b"),
            Project(
                name: "admin", folder: "/tmp/a",
                commands: ["worker 10", "worker 2"].map { Command(settings: settings($0)) }),
        ])

        let sorted = configuration.sortedByName()

        #expect(sorted.projects.map(\.name) == ["admin", "Shop 2", "shop 10"])
        #expect(sorted.projects[0].commands.map(\.settings.name) == ["worker 2", "worker 10"])
        #expect(sorted.projects[2].commands.map(\.settings.name) == ["api", "Build", "cron"])
        #expect(sorted.version == configuration.version)
        #expect(sorted.settings == configuration.settings)
    }

    @Test func projectsWithEqualNamesKeepTheirRelativeOrderWhenAConfigurationIsSorted() {
        // Enough equal names, spread among others, that an unstable sort would be caught.
        var projects: [Project] = []
        for index in 0..<200 {
            projects.append(Project(name: "Same", folder: "/tmp/same-\(index)"))
            projects.append(Project(name: index.isMultiple(of: 2) ? "Zeta" : "alpha", folder: "/tmp/other-\(index)"))
        }

        let sorted = Configuration(projects: projects).sortedByName()

        var expectedNames: [String] = Array(repeating: "alpha", count: 100)
        expectedNames += Array(repeating: "Same", count: 200)
        expectedNames += Array(repeating: "Zeta", count: 100)
        let names: [String] = sorted.projects.map(\.name)
        #expect(names == expectedNames)
        let expectedFolders: [String] = (0..<200).map { "/tmp/same-\($0)" }
        let folders: [String] = sorted.projects.filter { $0.name == "Same" }.map(\.folder)
        #expect(folders == expectedFolders)
    }

    // MARK: - Commands

    @Test func commandsAddedOutOfOrderAreServedAndSavedInOrderOfName() async throws {
        try await withHarness(["cron", "worker 10", "Build", "worker 2", "api"].map { settings($0) }) { h in
            let served = try await commandNames(h)
            let saved = try savedCommandNames(h)
            #expect(served == ["api", "Build", "cron", "worker 2", "worker 10"])
            #expect(saved == ["api", "Build", "cron", "worker 2", "worker 10"])
        }
    }

    @Test func aCommandAddedWithTheFormLandsAtItsSortedPlaceInTheSameChange() async throws {
        try await withHarness(["api", "cron"].map { settings($0) }) { h in
            let log = await EventLog.listening(to: h.engine)

            let added = try await h.engine.addCommand(to: h.projectID, settings: settings("Build"))

            #expect(added.settings.name == "Build")
            #expect(try await commandNames(h) == ["api", "Build", "cron"])
            try await waitUntil("the configuration event arrived") { await log.events.count == 1 }
            guard case .configuration(let pushed) = await log.events[0] else {
                Issue.record("expected a configuration event")
                return
            }
            #expect(pushed.project(h.projectID)?.commands.map(\.settings.name) == ["api", "Build", "cron"])
        }
    }

    @Test func commandsAddedFromDiscoverysChecklistAndFromARescanLandAtTheirSortedPlaces() async throws {
        let folder = try projectFixture("laravel-dev-list")
        try await withHarness([], devList: try FakeDevListRunner(fixture: "default.json")) { h in
            let project = try await h.engine.addProject(folder: folder.path)
            let names = { try #require(await h.engine.snapshot().project(project.id)).commands.map(\.settings.name) }

            // The checklist of a new Project: the user ticks the first two proposals.
            let checklist = try await h.engine.discover(project.id)
            #expect(checklist.add.map(\.settings.name) == ["server", "queue", "logs", "vite"])
            for proposal in checklist.add.prefix(2) {
                _ = try await h.engine.addCommand(to: project.id, settings: proposal.settings, madeByDiscovery: true)
            }
            #expect(try await names() == ["queue", "server"])

            // A Rescan offers the rest.
            let rescan = try await h.engine.discover(project.id)
            #expect(rescan.add.map(\.settings.name) == ["logs", "vite"])
            for proposal in rescan.add.reversed() {
                _ = try await h.engine.addCommand(to: project.id, settings: proposal.settings, madeByDiscovery: true)
            }
            #expect(try await names() == ["logs", "queue", "server", "vite"])
            let saved = try #require(try h.store.load().projects.first { $0.id == project.id })
            #expect(saved.commands.map(\.settings.name) == ["logs", "queue", "server", "vite"])
        }
    }

    @Test func renamingACommandMovesItInTheChangeThatSavesTheName() async throws {
        try await withHarness(["api", "Build", "cron"].map { settings($0) }) { h in
            let log = await EventLog.listening(to: h.engine)
            var edited = try await h.command(h.commandIDs[0]).settings
            edited.name = "web"

            let renamed = try await h.engine.updateCommand(h.commandIDs[0], settings: edited)

            #expect(renamed.id == h.commandIDs[0])
            #expect(renamed.settings.name == "web")
            #expect(try await commandNames(h) == ["Build", "cron", "web"])
            #expect(try await h.project().commands.map(\.id) == [h.commandIDs[1], h.commandIDs[2], h.commandIDs[0]])
            #expect(try savedCommandNames(h) == ["Build", "cron", "web"])
            // One change: the event that carries the new name carries the new place.
            try await waitUntil("the configuration event arrived") { await log.events.count == 1 }
            guard case .configuration(let pushed) = await log.events[0] else {
                Issue.record("expected a configuration event")
                return
            }
            #expect(pushed.project(h.projectID)?.commands.map(\.settings.name) == ["Build", "cron", "web"])
        }
    }

    // MARK: - Projects

    @Test func aNewProjectLandsAtItsSortedPlace() async throws {
        // The harness Project is named "project".
        try await withHarness([]) { h in
            let zeta = try await addProject(h, folder: "one", name: "Zeta")
            #expect(zeta.name == "Zeta")
            let shop10 = try await addProject(h, folder: "two", name: "shop 10")
            let alpha = try await addProject(h, folder: "three", name: "alpha")
            let shop2 = try await addProject(h, folder: "four", name: "Shop 2")

            let projects = await h.engine.snapshot().projects
            #expect(projects.map(\.name) == ["alpha", "project", "Shop 2", "shop 10", "Zeta"])
            #expect(projects.map(\.id) == [alpha.id, h.projectID, shop2.id, shop10.id, zeta.id])
            #expect(try h.store.load().projects.map(\.name) == ["alpha", "project", "Shop 2", "shop 10", "Zeta"])
        }
    }

    @Test func renamingAProjectMovesItAndTheAnswerCarriesTheRenamedProject() async throws {
        try await withHarness([settings("only here")]) { h in
            let alpha = try await addProject(h, folder: "one", name: "alpha")
            let zeta = try await addProject(h, folder: "two", name: "Zeta")
            #expect(await h.engine.snapshot().projects.map(\.id) == [alpha.id, h.projectID, zeta.id])

            // Moves from the first place to the last: its old index now holds the harness Project.
            let renamed = try await h.engine.renameProject(alpha.id, name: " zz top ")

            #expect(renamed.id == alpha.id)
            #expect(renamed.name == "zz top")
            #expect(renamed.folder == alpha.folder)
            #expect(renamed.commands.isEmpty)
            let projects = await h.engine.snapshot().projects
            #expect(projects.map(\.name) == ["project", "Zeta", "zz top"])
            #expect(projects.map(\.id) == [h.projectID, zeta.id, alpha.id])
            #expect(try h.store.load().projects.map(\.name) == ["project", "Zeta", "zz top"])

            // And from the last place to the first.
            let back = try await h.engine.renameProject(alpha.id, name: "Alpha")
            #expect(back.id == alpha.id)
            #expect(back.name == "Alpha")
            #expect(await h.engine.snapshot().projects.map(\.id) == [alpha.id, h.projectID, zeta.id])
        }
    }

    @Test func projectsWithTheSameNameKeepTheirRelativeOrderInTheHelper() async throws {
        try await withHarness([]) { h in
            let first = try await addProject(h, folder: "one", name: "Same")
            let second = try await addProject(h, folder: "two", name: "Same")
            let other = try await addProject(h, folder: "three", name: "alpha")
            let third = try await addProject(h, folder: "four", name: "Same")
            #expect(
                await h.engine.snapshot().projects.map(\.id) == [other.id, h.projectID, first.id, second.id, third.id])

            // A later change sorts again and still keeps them as they were.
            _ = try await h.engine.renameProject(other.id, name: "Zeta")
            #expect(
                await h.engine.snapshot().projects.map(\.id) == [h.projectID, first.id, second.id, third.id, other.id])
            // A Project renamed to the shared name goes after the ones it now ties with, by its old place.
            _ = try await h.engine.renameProject(h.projectID, name: "Same")
            #expect(
                await h.engine.snapshot().projects.map(\.id) == [h.projectID, first.id, second.id, third.id, other.id])
        }
    }

    // MARK: - A saved configuration

    @Test func aConfigurationSavedOutOfOrderIsServedSortedWithNoVersionChange() async throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ConfigurationStore(file: folder.appendingPathComponent("configuration.json"))
        let outOfOrder = Configuration(projects: [
            Project(
                name: "shop", folder: folder.path,
                commands: ["cron", "worker 10", "Build", "worker 2", "api"].map { Command(settings: settings($0)) }),
            Project(name: "Admin", folder: "/tmp/admin", commands: ["b", "a"].map { Command(settings: settings($0)) }),
        ])
        try store.save(outOfOrder)
        let onDisk = try Data(contentsOf: store.file)

        let engine = HelperEngine(configuration: try store.load(), store: store, shell: .plain)

        let snapshot = await engine.snapshot()
        #expect(snapshot.projects.map(\.name) == ["Admin", "shop"])
        #expect(snapshot.projects[0].commands.map(\.settings.name) == ["a", "b"])
        #expect(snapshot.projects[1].commands.map(\.settings.name) == ["api", "Build", "cron", "worker 2", "worker 10"])
        #expect(snapshot.projects[1].commands.map(\.id) == [4, 2, 0, 3, 1].map { outOfOrder.projects[0].commands[$0].id })
        // Loading rewrites nothing.
        #expect(try Data(contentsOf: store.file) == onDisk)

        // The next saved change writes the file sorted, at the same version.
        _ = try await engine.renameProject(outOfOrder.projects[0].id, name: "Shop")
        let saved = try store.load()
        #expect(saved.version == outOfOrder.version)
        #expect(saved.version == 1)
        #expect(saved.projects.map(\.name) == ["Admin", "Shop"])
        #expect(saved.projects[1].commands.map(\.settings.name) == ["api", "Build", "cron", "worker 2", "worker 10"])
    }

    // MARK: - Start All and Restart All

    @Test func startAllStartsTheIncludedCommandsInOrderOfName() async throws {
        var skipped = settings("beta", Script.runsForever)
        skipped.includedInStartAll = false
        try await withHarness([
            settings("cron", Script.runsForever), settings("worker 10", Script.runsForever), skipped,
            settings("Build", Script.runsForever), settings("worker 2", Script.runsForever),
            settings("api", Script.runsForever),
        ]) { h in
            let log = await EventLog.listening(to: h.engine)

            _ = try await h.engine.startAll(h.projectID, origin: .user)

            try await waitUntil("five status events arrived") { await log.statusChanges.count == 5 }
            let changes = await log.statusChanges
            #expect(changes.map(\.command.settings.name) == ["api", "Build", "cron", "worker 2", "worker 10"])
            #expect(changes.allSatisfy { $0.cause == .started && $0.projectAction == .startAll })
        }
    }

    @Test func restartAllStartsTheCommandsAgainInOrderOfName() async throws {
        try await withHarness(
            ["cron", "worker 10", "Build", "worker 2", "api"].map { settings($0, Script.runsForever) }
        ) { h in
            _ = try await h.engine.startAll(h.projectID, origin: .user)
            let log = await EventLog.listening(to: h.engine)

            _ = try await h.engine.restartAll(h.projectID, origin: .user)

            try await waitUntil("every Command was started again") {
                await log.statusChanges.filter { $0.cause == .restarted }.count == 5
            }
            let restarted = await log.statusChanges.filter { $0.cause == .restarted }
            #expect(restarted.map(\.command.settings.name) == ["api", "Build", "cron", "worker 2", "worker 10"])
            #expect(restarted.allSatisfy { $0.projectAction == .restartAll })
        }
    }
}
