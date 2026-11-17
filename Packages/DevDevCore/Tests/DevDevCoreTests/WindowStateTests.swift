import Foundation
import Testing

@testable import DevDevCore

/// What the main window shows, worked out from what the Helper reports.
@Suite struct WindowStateTests {
    private static let projectID = UUID()

    private static func command(
        _ name: String, _ status: CommandStatus, exit: ProcessExit? = nil, included: Bool = true,
        restartToApply: Bool = false
    ) -> CommandSnapshot {
        CommandSnapshot(
            id: UUID(), projectID: projectID,
            settings: CommandSettings(name: name, commandLine: "run \(name)", includedInStartAll: included),
            madeByDiscovery: false, status: status, lastExit: exit, restartToApply: restartToApply,
            startedAt: status == .running ? Date() : nil, processID: status == .running ? 42 : nil)
    }

    private static func project(_ commands: [CommandSnapshot], status: ProjectStatus) -> ProjectSnapshot {
        ProjectSnapshot(id: projectID, name: "shop", folder: "/tmp/shop", status: status, commands: commands)
    }

    private static func connected(_ projects: [ProjectSnapshot]) -> WindowState {
        var state = WindowState()
        state.connected(snapshot: HelperSnapshot(projects: projects), compatibility: .current)
        return state
    }

    @Test func whenTheHelperDiesEverythingShowsAsStoppedAndTheWindowOffersToStartItAgain() throws {
        let vite = Self.command("Vite", .running, restartToApply: true)
        let queue = Self.command("Queue", .crashed, exit: .exited(1))
        var state = Self.connected([Self.project([vite, queue], status: .crashed)])

        state.helperDied()

        #expect(state.link == .died)
        #expect(state.projects.map(\.status) == [.stopped])
        #expect(state.projects[0].commands.map(\.status) == [.stopped, .stopped])
        #expect(state.projects[0].commands.allSatisfy { $0.processID == nil && !$0.restartToApply })
        #expect(state.projects[0].commands.map(\.settings.name) == ["Vite", "Queue"])
        #expect(!state.canAct)
        let notice = try #require(state.notice)
        #expect(notice.action == .startHelper)
        #expect(notice.actionLabel == "Start Helper")
        #expect(notice.message.contains("Processes stopped with it"))
    }

    @Test func aHelperThatCannotBeReachedShowsTheReasonAndOffersToTryAgain() throws {
        var state = WindowState()
        #expect(state.notice == nil)
        state.helperUnavailable("The Helper did not start.")
        let notice = try #require(state.notice)
        #expect(notice.message == "The Helper did not start.")
        #expect(notice.action == .startHelper)
        #expect(!state.canAct)
    }

    @Test func aStatusEventUpdatesTheCommandAndItsProjectStatus() {
        let vite = Self.command("Vite", .stopped)
        var state = Self.connected([Self.project([vite], status: .stopped)])
        var running = vite
        running.status = .running

        state.apply(
            .status(
                StatusChange(
                    command: running, projectStatus: .running, cause: .started, origin: .user, projectAction: nil)))

        #expect(state.projects[0].status == .running)
        #expect(state.projects[0].commands[0].status == .running)
    }

    @Test func eventsThatArriveAfterTheHelperDiedChangeNothing() {
        let vite = Self.command("Vite", .running)
        var state = Self.connected([Self.project([vite], status: .running)])
        state.helperDied()
        state.apply(.configuration(HelperSnapshot(projects: [Self.project([vite], status: .running)])))
        #expect(state.projects[0].commands[0].status == .stopped)
    }

    @Test func theFirstProjectAndItsFirstCommandAreSelectedAndSelectionFollowsRemovals() {
        let vite = Self.command("Vite", .stopped)
        let queue = Self.command("Queue", .stopped)
        var state = Self.connected([Self.project([vite, queue], status: .stopped)])
        #expect(state.selectedProject?.id == Self.projectID)
        #expect(state.selectedCommand?.id == vite.id)

        state.select(command: queue.id)
        #expect(state.selectedCommand?.id == queue.id)

        state.apply(.configuration(HelperSnapshot(projects: [Self.project([vite], status: .stopped)])))
        #expect(state.selectedCommand?.id == vite.id)

        state.apply(.configuration(HelperSnapshot(projects: [])))
        #expect(state.selectedProject == nil)
        #expect(state.selectedCommand == nil)
    }

    @Test func theButtonsOfACommandFollowItsStatus() {
        let state = Self.connected([])
        // Restart on a Command that is not Running starts it, so Restart is always offered.
        #expect(state.actions(for: Self.command("a", .stopped)) == CommandActions(start: true, restart: true, stop: false))
        #expect(state.actions(for: Self.command("a", .running)) == CommandActions(start: false, restart: true, stop: true))
        // Stop on a Crashed or Finished Command sets it to Stopped.
        #expect(state.actions(for: Self.command("a", .crashed)) == CommandActions(start: true, restart: true, stop: true))
        #expect(state.actions(for: Self.command("a", .finished)) == CommandActions(start: true, restart: true, stop: true))
    }

    @Test func theAllButtonsOfAProjectFollowItsCommands() {
        let state = Self.connected([])
        let excluded = Self.command("Tinker", .stopped, included: false)
        let idle = Self.project([Self.command("Vite", .stopped), excluded], status: .stopped)
        #expect(state.actions(for: idle) == ProjectActions(startAll: true, restartAll: false, stopAll: false))

        let allUp = Self.project([Self.command("Vite", .running), excluded], status: .running)
        #expect(state.actions(for: allUp) == ProjectActions(startAll: false, restartAll: true, stopAll: true))

        let crashed = Self.project([Self.command("Vite", .crashed, exit: .exited(1))], status: .crashed)
        #expect(state.actions(for: crashed) == ProjectActions(startAll: true, restartAll: false, stopAll: true))

        #expect(state.actions(for: Self.project([], status: .stopped)) == ProjectActions(startAll: false, restartAll: false, stopAll: false))
    }

    @Test func noButtonIsOfferedWhileTheHelperIsNotConnected() {
        var state = Self.connected([])
        state.helperDied()
        #expect(state.actions(for: Self.command("a", .stopped)) == CommandActions(start: false, restart: false, stop: false))
        #expect(
            state.actions(for: Self.project([Self.command("a", .stopped)], status: .stopped))
                == ProjectActions(startAll: false, restartAll: false, stopAll: false))
    }

    @Test func theStatusTextCarriesTheExitOnlyForFinishedAndCrashed() {
        #expect(Self.command("a", .stopped).statusText == "Stopped")
        #expect(Self.command("a", .stopped, exit: .signalled(15)).statusText == "Stopped")
        #expect(Self.command("a", .running).statusText == "Running")
        #expect(Self.command("a", .finished, exit: .exited(0)).statusText == "Finished (exit code 0)")
        #expect(Self.command("a", .crashed, exit: .exited(1)).statusText == "Crashed (exit code 1)")
        #expect(Self.command("a", .crashed, exit: .signalled(9)).statusText == "Crashed (signal 9)")
        #expect(Self.command("a", .crashed).statusText == "Crashed")
        #expect(ProjectStatus.allCases.map(\.label) == ["Crashed", "Stopped", "Running", "Partly Running"])
    }

    @Test func deletingARunningCommandIsConfirmedWithAWarningThatItStopsFirst() {
        let running = Self.command("Vite", .running).deleteConfirmation
        #expect(running.title == "Delete the Command “Vite”?")
        #expect(running.message == "It is Running. It will be stopped first, then deleted.")
        #expect(running.confirmLabel == "Stop and Delete")

        let stopped = Self.command("Vite", .stopped).deleteConfirmation
        #expect(stopped.confirmLabel == "Delete")
        #expect(!stopped.message.contains("stopped first"))
    }

    @Test func removingAProjectIsConfirmedAndSaysItsProcessesStop() {
        let busy = Self.project([Self.command("Vite", .running)], status: .running).removeConfirmation
        #expect(busy.title == "Remove the Project “shop”?")
        #expect(busy.message.contains("1 Running Command will be stopped first"))
        #expect(busy.message.contains("folder on disk is not touched"))
        let idle = Self.project([], status: .stopped).removeConfirmation
        #expect(!idle.message.contains("stopped first"))
        #expect(idle.confirmLabel == "Remove")
    }

    @Test func aCommandDraftCarriesEveryFieldToSettingsAndBack() {
        let settings = CommandSettings(
            name: "Queue", commandLine: "php artisan queue:listen", subfolder: "api",
            environment: [EnvironmentVariable(name: "APP_ENV", value: "local")],
            includedInStartAll: false, autoRestart: true, restartWhenFilesChange: ["app/**/*.php", "config/*.php"],
            runInContainer: true, containerName: "laravel")
        let draft = CommandDraft(settings)
        #expect(draft.restartWhenFilesChange == "app/**/*.php\nconfig/*.php")
        #expect(draft.settings == settings)
    }

    @Test func aCommandDraftDropsBlankRowsAndStartsWithTheSectionFourDefaults() {
        var draft = CommandDraft()
        #expect(draft.includedInStartAll)
        #expect(!draft.autoRestart)
        draft.name = "Vite"
        draft.commandLine = "npm run dev"
        draft.environment = [EnvironmentVariable(name: " ", value: "x"), EnvironmentVariable(name: " A ", value: "1")]
        draft.restartWhenFilesChange = "\n  vite.config.js  \n\n"
        #expect(draft.settings.environment == [EnvironmentVariable(name: "A", value: "1")])
        #expect(draft.settings.restartWhenFilesChange == ["vite.config.js"])
    }

    @Test func aContainerCommandRunsThroughDockerExecAndPassesItsVariables() {
        var settings = CommandSettings(name: "Vite", commandLine: "npm run dev", containerName: "web app")
        #expect(settings.effectiveCommandLine == "npm run dev")
        settings.runInContainer = true
        #expect(settings.effectiveCommandLine == "docker exec -it 'web app' npm run dev")
        settings.containerName = "web"
        settings.environment = [EnvironmentVariable(name: "NODE_ENV", value: "development")]
        #expect(settings.effectiveCommandLine == "docker exec -it -e NODE_ENV web npm run dev")
    }

    @Test func settingsSavedBeforeContainersExistedRunOnThisMac() throws {
        let json = """
            {"name":"Vite","commandLine":"npm run dev","subfolder":"","environment":[],
             "includedInStartAll":true,"autoRestart":false,"restartWhenFilesChange":[]}
            """
        let settings = try JSONDecoder().decode(CommandSettings.self, from: Data(json.utf8))
        #expect(!settings.runInContainer)
        #expect(settings.containerName == "")
    }

    @Test func draggingACommandInTheListGivesTheIndexTheHelperExpects() {
        // SwiftUI reports the row the item is dropped before, counted with the item still in place.
        #expect(CommandMove.targetIndex(from: 0, toOffset: 3) == 2)
        #expect(CommandMove.targetIndex(from: 2, toOffset: 0) == 0)
        #expect(CommandMove.targetIndex(from: 1, toOffset: 1) == 1)
        #expect(CommandMove.targetIndex(from: 1, toOffset: 2) == 1)
    }

    @Test func anOpenLinkSelectsTheCommandAndItsProject() {
        let vite = Self.command("Vite", .running)
        let otherID = UUID()
        var server = Self.command("Server", .stopped)
        server.projectID = otherID
        let other = ProjectSnapshot(id: otherID, name: "blog", folder: "/tmp/blog", status: .stopped, commands: [server])
        var state = Self.connected([Self.project([vite], status: .running), other])
        #expect(state.selectedCommandID == vite.id)

        state.open(.command(server.id))

        #expect(state.selectedProjectID == otherID)
        #expect(state.selectedCommandID == server.id)
    }

    @Test func anOpenLinkThatArrivesBeforeTheHelperAnswersIsAppliedOnceItDoes() {
        let vite = Self.command("Vite", .running)
        let queue = Self.command("Queue", .running)
        var state = WindowState()

        state.open(.command(queue.id))
        state.connected(
            snapshot: HelperSnapshot(projects: [Self.project([vite, queue], status: .running)]), compatibility: .current)

        #expect(state.selectedCommandID == queue.id)
    }

    @Test func anOpenLinkToACommandThatNoLongerExistsKeepsTheSelection() {
        let vite = Self.command("Vite", .running)
        var state = Self.connected([Self.project([vite], status: .running)])

        state.open(.command(UUID()))

        #expect(state.selectedCommandID == vite.id)
    }

    // MARK: - Moving a tab

    /// Commands of one Project, each with a tab, in the order given. The first one is selected.
    private static func tabs(_ names: [String]) -> (state: WindowState, ids: [UUID]) {
        let commands = names.map { command($0, .stopped) }
        var state = connected([project(commands, status: .stopped)])
        for command in commands { state.select(tab: command.id) }
        state.select(tab: commands[0].id)
        return (state, commands.map(\.id))
    }

    @Test func movingATabLeftPutsItAtThatPlaceAndShiftsTheOthersRight() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d"])
        var state = initial

        state.moveTab(ids[2], to: 1)

        #expect(state.tabs == [ids[0], ids[2], ids[1], ids[3]])
    }

    @Test func movingATabRightPutsItAtThatPlaceAndShiftsTheOthersLeft() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d"])
        var state = initial

        state.moveTab(ids[0], to: 2)

        #expect(state.tabs == [ids[1], ids[2], ids[0], ids[3]])
    }

    @Test func aTabCanMoveToTheFirstAndToTheLastPlace() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d"])
        var state = initial

        state.moveTab(ids[2], to: 0)
        #expect(state.tabs == [ids[2], ids[0], ids[1], ids[3]])

        state.moveTab(ids[0], to: 3)
        #expect(state.tabs == [ids[2], ids[1], ids[3], ids[0]])
    }

    @Test func movingATabToItsOwnPlaceLeavesTheTabsUnchanged() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d"])
        var state = initial

        state.moveTab(ids[1], to: 1)

        #expect(state.tabs == ids)
    }

    @Test func aPlaceOutsideTheListIsClampedToTheFirstOrLastPlace() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d"])
        var state = initial

        state.moveTab(ids[1], to: 99)
        #expect(state.tabs == [ids[0], ids[2], ids[3], ids[1]])

        state.moveTab(ids[3], to: -5)
        #expect(state.tabs == [ids[3], ids[0], ids[2], ids[1]])

        state.moveTab(ids[3], to: -1)
        #expect(state.tabs == [ids[3], ids[0], ids[2], ids[1]])
    }

    @Test func movingAnUnknownTabDoesNothing() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d"])
        var state = initial

        state.moveTab(UUID(), to: 0)

        #expect(state.tabs == ids)
        #expect(state.selectedCommandID == ids[0])
    }

    @Test func movingATabNeverChangesTheSelectionEvenWhenTheSelectedTabMoves() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d"])
        var state = initial
        #expect(state.selectedCommandID == ids[0])
        #expect(state.selectedProjectID == Self.projectID)

        state.moveTab(ids[0], to: 3)
        #expect(state.selectedCommandID == ids[0])
        #expect(state.selectedProjectID == Self.projectID)

        state.moveTab(ids[2], to: 0)
        #expect(state.selectedCommandID == ids[0])
        #expect(state.selectedProjectID == Self.projectID)
        #expect(state.tabs == [ids[2], ids[1], ids[3], ids[0]])
    }

    @Test func afterAMoveCommandOneToNineCountFromTheLeftInTheNewOrderAndZeroIsTheLastTab() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"])
        var state = initial

        state.moveTab(ids[9], to: 0)
        state.moveTab(ids[4], to: 9)

        let order = [ids[9], ids[0], ids[1], ids[2], ids[3], ids[5], ids[6], ids[7], ids[8], ids[4]]
        #expect(state.tabs == order)
        #expect((1...9).map { state.tab(number: $0) } == Array(order[0..<9]))
        #expect(state.tab(number: 0) == ids[4])
    }

    @Test func afterAMoveClosingTheSelectedTabSelectsItsRightNeighbourInTheNewOrderElseItsLeft() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d"])
        var state = initial
        state.moveTab(ids[3], to: 1)
        #expect(state.tabs == [ids[0], ids[3], ids[1], ids[2]])

        state.closeTab(ids[0])
        #expect(state.selectedCommandID == ids[3])

        state.moveTab(ids[3], to: 2)
        #expect(state.tabs == [ids[1], ids[2], ids[3]])
        state.closeTab(ids[3])
        #expect(state.selectedCommandID == ids[2])
        #expect(state.tabs == [ids[1], ids[2]])
    }

    @Test func afterAMoveCommandWStillClosesTheSelectedTab() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d"])
        var state = initial

        state.moveTab(ids[0], to: 2)
        #expect(state.closeTarget == .tab(ids[0]))

        state.moveTab(ids[3], to: 0)
        #expect(state.closeTarget == .tab(ids[0]))
    }

    @Test func aTabOpenedAfterAMoveLandsAtTheRightEnd() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d"])
        var state = initial
        state.closeTab(ids[3])
        state.moveTab(ids[2], to: 0)

        state.select(tab: ids[3])

        #expect(state.tabs == [ids[2], ids[0], ids[1], ids[3]])
    }

    // MARK: - Ending a tab drag early

    /// Starts a drag of `tab` in a strip where every tab is 100 wide, pressed at x 1000.
    private static func drag(_ tab: UUID, in state: WindowState) -> TabDrag {
        let widths = Dictionary(uniqueKeysWithValues: state.tabs.map { ($0, 100.0) })
        return TabDrag(tab: tab, tabs: state.tabs, widths: widths, pressX: 1000)!
    }

    @Test func escapePutsTheDraggedTabBackSoTheOrderEqualsTheOrderBeforeTheDrag() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d"])
        var state = initial
        var drag = Self.drag(ids[1], in: state)
        // B goes right past C and D, then left past everyone, taking each place live.
        state.moveTab(ids[1], to: drag.follow(pointerX: 1250))
        state.moveTab(ids[1], to: drag.follow(pointerX: 800))
        #expect(state.tabs == [ids[1], ids[0], ids[2], ids[3]])

        state.moveTab(drag.tab, to: drag.startPlace)

        #expect(state.tabs == ids)
    }

    @Test func escapeDoesNotChangeTheSelection() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d"])
        var state = initial
        var drag = Self.drag(ids[2], in: state)
        state.moveTab(ids[2], to: drag.follow(pointerX: 700))

        state.moveTab(drag.tab, to: drag.startPlace)

        #expect(state.selectedCommandID == ids[0])
        #expect(state.selectedProjectID == initial.selectedProjectID)
    }

    @Test func escapeAfterTabsWereClosedDuringTheDragPutsTheTabAtTheLastPlace() {
        let (initial, ids) = Self.tabs(["a", "b", "c", "d"])
        var state = initial
        var drag = Self.drag(ids[3], in: state)
        state.moveTab(ids[3], to: drag.follow(pointerX: 700))
        state.closeTab(ids[1])
        state.closeTab(ids[2])
        #expect(state.tabs == [ids[3], ids[0]])

        state.moveTab(drag.tab, to: drag.startPlace)

        #expect(state.tabs == [ids[0], ids[3]])
    }

    @Test func aDragGoesOnWhileItsTabIsInTheStrip() {
        let (initial, ids) = Self.tabs(["a", "b", "c"])
        var state = initial
        var drag = Self.drag(ids[0], in: state)
        state.moveTab(ids[0], to: drag.follow(pointerX: 1250))

        #expect(drag.continues(in: state.tabs))
    }

    @Test func deletingTheDraggedTabsCommandEndsTheDragAndTheOtherTabsKeepTheOrderShown() {
        let commands = ["a", "b", "c", "d"].map { Self.command($0, .stopped) }
        let ids = commands.map(\.id)
        var state = Self.connected([Self.project(commands, status: .stopped)])
        for id in ids { state.select(tab: id) }
        var drag = Self.drag(ids[0], in: state)
        // A's centre starts at 50. Moved 210 right it is at 260, past C's middle at 250.
        state.moveTab(ids[0], to: drag.follow(pointerX: 1210))
        #expect(state.tabs == [ids[1], ids[2], ids[0], ids[3]])

        let left = commands.filter { $0.id != ids[0] }
        state.apply(.configuration(HelperSnapshot(projects: [Self.project(left, status: .stopped)])))

        #expect(!drag.continues(in: state.tabs))
        #expect(state.tabs == [ids[1], ids[2], ids[3]])
        // No stale drag is in the way: the next drag starts and moves a tab.
        var next = Self.drag(ids[3], in: state)
        state.moveTab(ids[3], to: next.follow(pointerX: 800))
        #expect(state.tabs == [ids[3], ids[1], ids[2]])
    }

    @Test func removingTheDraggedTabsProjectEndsTheDragAndTheTabDisappears() {
        let otherProject = UUID()
        let api = CommandSnapshot(
            id: UUID(), projectID: otherProject,
            settings: CommandSettings(name: "api", commandLine: "run api", includedInStartAll: true),
            madeByDiscovery: false, status: .stopped, lastExit: nil, restartToApply: false,
            startedAt: nil, processID: nil)
        let other = ProjectSnapshot(id: otherProject, name: "api", folder: "/tmp/api", status: .stopped, commands: [api])
        let shop = Self.project([Self.command("a", .stopped), Self.command("b", .stopped)], status: .stopped)
        var state = Self.connected([shop, other])
        for id in [shop.commands[0].id, api.id, shop.commands[1].id] { state.select(tab: id) }
        var drag = Self.drag(api.id, in: state)
        state.moveTab(api.id, to: drag.follow(pointerX: 1160))
        #expect(state.tabs == [shop.commands[0].id, shop.commands[1].id, api.id])

        state.apply(.configuration(HelperSnapshot(projects: [shop])))

        #expect(!drag.continues(in: state.tabs))
        #expect(state.tabs == [shop.commands[0].id, shop.commands[1].id])
    }
}
