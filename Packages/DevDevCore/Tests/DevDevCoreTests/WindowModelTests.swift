import Foundation
import Testing

@testable import DevDevCore

/// A stand-in for the Helper program: a real Helper on a temporary data folder that the test starts and ends.
final class HelperStandIn: @unchecked Sendable {
    let root: URL
    let paths: HelperPaths
    let projectFolder: URL
    private let lock = NSLock()
    private var host: HelperHost?
    private var launchCount = 0
    private var version = DevDevCore.version

    init() throws {
        root = try makeTemporaryFolder()
        paths = HelperPaths(dataFolder: root.appendingPathComponent("d", isDirectory: true))
        projectFolder = root.appendingPathComponent("shop", isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
    }

    var launches: Int { lock.withLock { launchCount } }
    var running: HelperHost? { lock.withLock { host } }

    /// The build the next started Helper reports.
    func setVersion(_ version: String) {
        lock.withLock { self.version = version }
    }

    /// What the App does to start the Helper.
    func launch() throws {
        let version = lock.withLock {
            launchCount += 1
            return self.version
        }
        try start(version: version)
    }

    func start(version: String? = nil) throws {
        let host = try HelperHost.start(
            paths: paths, shell: .plain, timings: Timings(killEscalation: .seconds(3)),
            helperVersion: version ?? lock.withLock { self.version })
        lock.withLock { self.host = host }
        // Like the Helper program: exit when Stop All and Quit asks for it.
        Task { [weak self] in
            for await _ in host.engine.quitRequests {
                host.server.stop()
                self?.lock.withLock { if self?.host === host { self?.host = nil } }
            }
        }
    }

    /// The Helper dies: its socket closes and its Processes end.
    func die() async {
        guard let host = lock.withLock({ self.host }) else { return }
        lock.withLock { self.host = nil }
        host.server.stop()
        await host.engine.stopEverything(origin: .user)
    }

    func cleanUp() async {
        await die()
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor func makeModel(expecting build: String = DevDevCore.version) -> WindowModel {
        WindowModel(
            socketPath: paths.socketPath, expectedHelperBuild: build, launchWait: .seconds(5),
            launchHelper: { [self] in try launch() })
    }
}

/// The model behind the main window, against a real Helper over a real socket.
@MainActor @Suite struct WindowModelTests {
    private func withStandIn(_ body: (HelperStandIn) async throws -> Void) async throws {
        let helper = try HelperStandIn()
        do {
            try await body(helper)
        } catch {
            await helper.cleanUp()
            throw error
        }
        await helper.cleanUp()
    }

    /// Connects, adds the Project and one Command, and waits until the window shows them.
    private func modelWithCommand(_ helper: HelperStandIn, _ line: String) async throws -> (WindowModel, UUID) {
        let model = helper.makeModel()
        await model.connect()
        await model.addProject(folder: helper.projectFolder)
        let projectID = try #require(model.state.selectedProject?.id)
        var draft = CommandDraft()
        draft.name = "Main"
        draft.commandLine = line
        let answer1 = await model.addCommand(to: projectID, draft: draft)
        #expect(answer1)
        try await waitUntil("the Command shows") { model.state.selectedCommand != nil }
        return (model, try #require(model.state.selectedCommand?.id))
    }

    @Test func onLaunchTheAppStartsTheHelperWhenItIsNotRunningAndConnects() async throws {
        try await withStandIn { helper in
            let model = helper.makeModel()
            await model.connect()
            #expect(helper.launches == 1)
            #expect(model.state.link == .connected)
            #expect(model.state.compatibility == .current)
            #expect(model.state.notice == nil)
        }
    }

    @Test func onLaunchTheAppConnectsToARunningHelperWithoutStartingAnother() async throws {
        try await withStandIn { helper in
            try helper.start()
            let model = helper.makeModel()
            await model.connect()
            #expect(helper.launches == 0)
            #expect(model.state.link == .connected)
        }
    }

    @Test func aHelperThatCannotBeStartedIsShownWithTheReason() async throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = WindowModel(
            socketPath: folder.appendingPathComponent("h.sock").path, expectedHelperBuild: "x",
            launchWait: .milliseconds(100),
            launchHelper: { throw HelperError(code: HelperError.connectionFailed, message: "There is no Helper.") })
        await model.connect()
        #expect(model.state.link == .unavailable("There is no Helper."))
    }

    @Test func everyRequestFromTheAppCarriesTheOriginUser() async throws {
        try await withStandIn { helper in
            let (model, commandID) = try await modelWithCommand(helper, Script.runsForever)
            let projectID = try #require(model.state.selectedProject?.id)
            let log = await EventLog.listening(to: try #require(helper.running).engine)

            await model.start(commandID)
            await model.restart(commandID)
            await model.stop(commandID)
            await model.startAll(projectID)
            await model.restartAll(projectID)
            await model.stopAll(projectID)

            try await waitUntil("all eight changes arrived") { await log.statusChanges.count == 8 }
            let changes = await log.statusChanges
            #expect(
                changes.map(\.cause) == [
                    .started, .stoppedForRestart, .restarted, .stopped, .started, .stoppedForRestart, .restarted,
                    .stopped,
                ])
            #expect(changes.allSatisfy { $0.origin == .user })
            #expect(model.errorMessage == nil)
        }
    }

    @Test func theWindowFollowsStatusChangesPushedByTheHelper() async throws {
        try await withStandIn { helper in
            let (model, commandID) = try await modelWithCommand(helper, "exit 3")
            // Started by someone else, such as the menubar panel.
            _ = try await #require(helper.running).engine.start(commandID, origin: .agent)
            try await waitUntil("the window shows Crashed") { model.state.selectedCommand?.status == .crashed }
            #expect(model.state.selectedCommand?.statusText == "Crashed (exit code 3)")
            #expect(model.state.selectedProject?.status == .crashed)
        }
    }

    @Test func addingAFolderThatIsAlreadyAProjectSelectsThatProject() async throws {
        try await withStandIn { helper in
            let other = helper.root.appendingPathComponent("blog", isDirectory: true)
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            let model = helper.makeModel()
            await model.connect()
            await model.addProject(folder: helper.projectFolder)
            let shop = try #require(model.state.selectedProject?.id)
            await model.addProject(folder: other)
            #expect(model.state.selectedProject?.name == "blog")

            await model.addProject(folder: helper.projectFolder)

            #expect(model.state.selectedProject?.id == shop)
            try await waitUntil("both Projects show") { model.state.projects.count == 2 }
            #expect(model.state.projects.map(\.name) == ["shop", "blog"])
        }
    }

    @Test func aRefusedEditKeepsTheFormOpenAndShowsTheHelpersSentence() async throws {
        try await withStandIn { helper in
            let (model, _) = try await modelWithCommand(helper, Script.runsForever)
            let projectID = try #require(model.state.selectedProject?.id)
            var draft = CommandDraft()
            draft.name = "main"
            draft.commandLine = "true"
            let answer2 = await model.addCommand(to: projectID, draft: draft)
            #expect(answer2 == false)
            #expect(model.errorMessage == "Project 'shop' already has a Command named 'Main'.")
        }
    }

    @Test func editingARunningCommandShowsTheRestartToApplyHintTheHelperReports() async throws {
        try await withStandIn { helper in
            let (model, commandID) = try await modelWithCommand(helper, Script.runsForever)
            await model.start(commandID)
            var draft = CommandDraft(try #require(model.state.selectedCommand).settings)
            draft.commandLine = "echo changed; \(Script.runsForever)"
            let answer3 = await model.updateCommand(commandID, draft: draft)
            #expect(answer3)
            try await waitUntil("the hint shows") { model.state.selectedCommand?.restartToApply == true }
            #expect(model.state.selectedCommand?.status == .running)

            await model.restart(commandID)
            try await waitUntil("the hint is gone") { model.state.selectedCommand?.restartToApply == false }
        }
    }

    @Test func deletingARunningCommandStopsItsProcessAndThenDeletesIt() async throws {
        try await withStandIn { helper in
            let (model, commandID) = try await modelWithCommand(helper, Script.runsForever)
            await model.start(commandID)
            try await waitUntil("it runs") { model.state.selectedCommand?.processID != nil }
            let pid = try #require(model.state.selectedCommand?.processID)

            await model.deleteCommand(commandID)

            #expect(!processIsAlive(pid))
            try await waitUntil("the Command is gone") { model.state.selectedProject?.commands.isEmpty == true }
        }
    }

    @Test func draggingACommandReordersItInTheHelper() async throws {
        try await withStandIn { helper in
            let (model, first) = try await modelWithCommand(helper, "true")
            let projectID = try #require(model.state.selectedProject?.id)
            var draft = CommandDraft()
            draft.name = "Second"
            draft.commandLine = "true"
            let answer4 = await model.addCommand(to: projectID, draft: draft)
            #expect(answer4)

            await model.moveCommand(first, from: 0, toOffset: 2)

            try await waitUntil("the order changed") {
                model.state.selectedProject?.commands.map(\.settings.name) == ["Second", "Main"]
            }
        }
    }

    @Test func theOutputOfTheSelectedCommandIsReplayedThenStreamedAndTheViewSizeReachesTheHelper() async throws {
        try await withStandIn { helper in
            let line = "echo early; while [ ! -f go ]; do sleep 0.05; done; stty size; \(Script.runsForever)"
            let (model, commandID) = try await modelWithCommand(helper, line)
            let engine = try #require(helper.running).engine
            await model.start(commandID)
            try await waitUntil("early is stored") { try await engine.plainOutput(commandID, lastLines: nil).contains("early") }

            // The App is closed and opened again: a new model on the same Helper.
            let reopened = helper.makeModel()
            await reopened.connect()
            try await waitUntil("the replay arrived") { reopened.output != nil }
            let session = try #require(reopened.output)
            var shown = ""
            session.attach { shown += PlainText.strip($0) }
            #expect(shown == "early\n")

            await reopened.outputViewResized(columns: 91, rows: 17)
            FileManager.default.createFile(atPath: helper.projectFolder.appendingPathComponent("go").path, contents: nil)
            try await waitUntil("new output arrived") { shown.contains("ready") }
            #expect(shown == "early\n17 91\nready\n")
            #expect(reopened.output === session)
        }
    }

    @Test func whenTheHelperDiesTheWindowShowsItAndStartingItAgainReconnects() async throws {
        try await withStandIn { helper in
            let (model, commandID) = try await modelWithCommand(helper, Script.runsForever)
            await model.start(commandID)
            try await waitUntil("it runs") { model.state.selectedCommand?.status == .running }

            await helper.die()

            try await waitUntil("the window shows the Helper died") { model.state.link == .died }
            #expect(model.state.selectedCommand?.status == .stopped)
            #expect(model.state.selectedProject?.status == .stopped)
            #expect(model.state.notice?.action == .startHelper)
            await model.start(commandID)
            #expect(helper.running == nil, "a click must not start the Helper by itself")

            await model.connect()

            #expect(model.state.link == .connected)
            #expect(helper.launches == 2)
            #expect(model.state.selectedCommand?.id == commandID)
            #expect(model.state.selectedCommand?.status == .stopped)
        }
    }

    @Test func anOutdatedHelperIsNeverRestartedByItselfAndRestartHelperStopsItsProcessesFirst() async throws {
        try await withStandIn { helper in
            try helper.start(version: "0.1.0+old")
            let (model, commandID) = try await modelWithCommand(helper, Script.runsForever)
            #expect(model.state.compatibility == .outdated)
            #expect(model.state.notice?.action == .restartHelper)

            // The App keeps working against the older Helper.
            await model.start(commandID)
            try await waitUntil("it runs") { model.state.selectedCommand?.processID != nil }
            let pid = try #require(model.state.selectedCommand?.processID)
            #expect(helper.launches == 0)
            #expect(processIsAlive(pid))

            await model.restartHelper()

            #expect(!processIsAlive(pid))
            #expect(helper.launches == 1)
            #expect(model.state.link == .connected)
            #expect(model.state.compatibility == .current)
            #expect(model.state.notice == nil)
            #expect(model.state.selectedCommand?.status == .stopped)
        }
    }

    @Test func stopAllAndQuitStopsEveryProcessAndQuitsTheHelperWithoutShowingItAsDied() async throws {
        try await withStandIn { helper in
            let (model, commandID) = try await modelWithCommand(helper, Script.runsForever)
            await model.start(commandID)
            try await waitUntil("it runs") { model.state.selectedCommand?.processID != nil }
            let pid = try #require(model.state.selectedCommand?.processID)

            let answer5 = await model.stopAllAndQuit()
            #expect(answer5)

            #expect(!processIsAlive(pid))
            #expect(helper.running == nil)
            #expect(model.state.link != .died)
        }
    }

    @Test func stopAllAndQuitWithNoHelperRunningJustLetsTheAppQuit() async throws {
        try await withStandIn { helper in
            let model = helper.makeModel()
            let answer6 = await model.stopAllAndQuit()
            #expect(answer6)
            #expect(helper.launches == 0)
        }
    }

    @Test func theSettingsWindowShowsTheHelpersSettingsAndSavesASwitchThroughTheHelper() async throws {
        try await withStandIn { helper in
            let model = helper.makeModel()
            await model.connect()
            #expect(model.settings == HelperSettings(showMenubarIcon: true, launchAtLogin: false))

            await model.setShowMenubarIcon(false)

            #expect(model.settings?.showMenubarIcon == false)
            let engine = try #require(helper.running).engine
            #expect(await engine.settings().showMenubarIcon == false)
            #expect(model.errorMessage == nil)
        }
    }

    @Test func aSettingChangedByAnotherClientReachesTheSettingsWindow() async throws {
        try await withStandIn { helper in
            let model = helper.makeModel()
            await model.connect()
            let engine = try #require(helper.running).engine

            try await engine.updateSettings(HelperSettings(showMenubarIcon: false, launchAtLogin: false))

            try await waitUntil("the window shows the icon off") { model.settings?.showMenubarIcon == false }
        }
    }

    @Test func anOpenLinkShowsThatCommandsOutput() async throws {
        try await withStandIn { helper in
            let (model, first) = try await modelWithCommand(helper, "echo first; \(Script.runsForever)")
            let projectID = try #require(model.state.selectedProject?.id)
            var draft = CommandDraft()
            draft.name = "Second"
            draft.commandLine = "echo second; \(Script.runsForever)"
            let added = await model.addCommand(to: projectID, draft: draft)
            #expect(added)
            try await waitUntil("both Commands show") { model.state.selectedProject?.commands.count == 2 }
            await model.select(command: first)
            let second = try #require(model.state.selectedProject?.commands.last?.id)
            #expect(second != first)

            await model.open(.command(second))

            #expect(model.state.selectedCommandID == second)
            try await waitUntil("the output of the second Command arrives") { model.output?.commandID == second }
        }
    }
}
