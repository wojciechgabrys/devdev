import Foundation
import Testing

@testable import DevDevCore

/// The crash badge on the menubar icon (`docs/spec.md` section 8).
@Suite struct CrashBadgeTests {
    @Test func theBadgeShowsWhileAnyCommandIsCrashedAndStopAllClearsIt() async throws {
        try await withHarness([
            CommandSettings(name: "Queue", commandLine: "exit 3"),
            CommandSettings(name: "Vite", commandLine: Script.runsForever),
        ]) { h in
            #expect(MenubarPanel(snapshot: await h.engine.snapshot()).showsCrashBadge == false)

            _ = try await h.engine.startAll(h.projectID, origin: .user)
            try await h.waitForStatus(h.commandIDs[0], .crashed)
            #expect(MenubarPanel(snapshot: await h.engine.snapshot()).showsCrashBadge)

            _ = try await h.engine.stopAll(h.projectID, origin: .user)
            #expect(MenubarPanel(snapshot: await h.engine.snapshot()).showsCrashBadge == false)
        }
    }
}

/// The panel's rows, worked out from the Helper's state.
@Suite struct MenubarPanelTests {
    private func command(
        _ name: String, _ status: CommandStatus, exit: ProcessExit? = nil, included: Bool = true, in project: UUID
    ) -> CommandSnapshot {
        CommandSnapshot(
            id: UUID(), projectID: project,
            settings: CommandSettings(name: name, commandLine: "true", includedInStartAll: included),
            madeByDiscovery: false, status: status, lastExit: exit, restartToApply: false, startedAt: nil,
            processID: status == .running ? 42 : nil)
    }

    @Test func eachProjectIsARowWithItsNameStatusAndAllButtonsAndItsCommandsInOrder() {
        let shop = UUID()
        let blog = UUID()
        let snapshot = HelperSnapshot(projects: [
            ProjectSnapshot(
                id: shop, name: "shop", folder: "/tmp/shop", status: .crashed,
                commands: [
                    command("Vite", .running, in: shop),
                    command("Queue", .crashed, exit: .exited(1), in: shop),
                    command("Docs", .stopped, included: false, in: shop),
                ]),
            ProjectSnapshot(
                id: blog, name: "blog", folder: "/tmp/blog", status: .stopped,
                commands: [command("Server", .finished, exit: .exited(0), in: blog)]),
        ])

        let panel = MenubarPanel(snapshot: snapshot)

        #expect(panel.rows.map(\.name) == ["shop", "blog"])
        #expect(panel.rows.map(\.statusLabel) == ["Crashed", "Stopped"])
        #expect(panel.rows.map(\.status) == [.crashed, .stopped])
        #expect(panel.rows[0].actions == ProjectActions(startAll: true, restartAll: true, stopAll: true))
        #expect(panel.rows[1].actions == ProjectActions(startAll: true, restartAll: false, stopAll: true))

        let commands = panel.rows[0].commands
        #expect(commands.map(\.name) == ["Vite", "Queue", "Docs"])
        #expect(commands.map(\.statusText) == ["Running", "Crashed (exit code 1)", "Stopped"])
        #expect(commands.map(\.status) == [.running, .crashed, .stopped])
        #expect(commands[0].actions == CommandActions(start: false, restart: true, stop: true))
        #expect(commands[1].actions == CommandActions(start: true, restart: true, stop: true))
        #expect(commands[2].actions == CommandActions(start: true, restart: true, stop: false))
        #expect(panel.rows[1].commands.map(\.statusText) == ["Finished (exit code 0)"])
    }

    @Test func aPanelWithNoProjectsHasNoRowsAndNoBadge() {
        let panel = MenubarPanel(snapshot: HelperSnapshot(projects: []))
        #expect(panel.rows.isEmpty)
        #expect(panel.showsCrashBadge == false)
    }
}

/// The model behind the menubar panel, inside the Helper, against a real engine.
@MainActor @Suite struct MenubarModelTests {
    @Test func everyClickInThePanelCarriesTheOriginUser() async throws {
        try await withHarness(Script.runsForever) { h in
            let model = MenubarModel(engine: h.engine)
            await model.start()
            let log = await EventLog.listening(to: h.engine)

            await model.start(h.first)
            await model.restart(h.first)
            await model.stop(h.first)
            await model.startAll(h.projectID)
            await model.restartAll(h.projectID)
            await model.stopAll(h.projectID)

            try await waitUntil("all eight changes arrived") { await log.statusChanges.count == 8 }
            #expect(await log.statusChanges.allSatisfy { $0.origin == .user })
        }
    }

    @Test func thePanelFollowsTheHelpersStateAndTheBadgeFollowsCrashes() async throws {
        try await withHarness("exit 3") { h in
            let model = MenubarModel(engine: h.engine)
            await model.start()
            #expect(model.panel.rows.map(\.name) == ["project"])
            #expect(model.panel.rows[0].commands.map(\.name) == ["Main"])

            // Started from somewhere else, such as the App.
            _ = try await h.engine.start(h.first, origin: .agent)
            try await waitUntil("the panel shows Crashed") { model.panel.rows[0].commands[0].status == .crashed }
            #expect(model.panel.showsCrashBadge)

            await model.stopAll(h.projectID)
            try await waitUntil("the badge is gone") { !model.panel.showsCrashBadge }

            try await h.engine.addCommand(to: h.projectID, settings: CommandSettings(name: "Second", commandLine: "true"))
            try await waitUntil("the new Command shows") { model.panel.rows[0].commands.count == 2 }
        }
    }

    @Test func thePanelKnowsWhetherTheIconIsShown() async throws {
        try await withHarness([]) { h in
            let model = MenubarModel(engine: h.engine)
            await model.start()
            #expect(model.showsIcon)

            try await h.engine.updateSettings(HelperSettings(showMenubarIcon: false, launchAtLogin: false))

            try await waitUntil("the icon is hidden") { !model.showsIcon }
        }
    }

    @Test func thePanelShowsProjectsAndCommandsInTheHelpersSortedOrderAndFollowsARowThatMoves() async throws {
        let added = ["worker 10", "Build", "api", "worker 2"].map { CommandSettings(name: $0, commandLine: "true") }
        try await withHarness(added) { h in
            let admin = h.folder.appendingPathComponent("admin", isDirectory: true)
            try FileManager.default.createDirectory(at: admin, withIntermediateDirectories: true)
            _ = try await h.engine.addProject(folder: admin.path, name: "Admin")
            let model = MenubarModel(engine: h.engine)
            await model.start()

            // The harness Project is named "project".
            #expect(model.panel.rows.map(\.name) == ["Admin", "project"])
            #expect(model.panel.rows[1].commands.map(\.name) == ["api", "Build", "worker 2", "worker 10"])

            var renamed = added[2]
            renamed.name = "zebra"
            _ = try await h.engine.updateCommand(h.commandIDs[2], settings: renamed)
            _ = try await h.engine.renameProject(h.projectID, name: "aardvark")

            try await waitUntil("the panel shows the moved rows") {
                model.panel.rows.map(\.name) == ["aardvark", "Admin"]
            }
            #expect(model.panel.rows[0].commands.map(\.name) == ["Build", "worker 2", "worker 10", "zebra"])
            #expect(model.panel.rows[0].commands[3].id == h.commandIDs[2])
        }
    }
}
