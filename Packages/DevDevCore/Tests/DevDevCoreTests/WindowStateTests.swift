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
            includedInStartAll: false, autoRestart: true, restartWhenFilesChange: ["app/**/*.php", "config/*.php"])
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

    @Test func draggingACommandInTheListGivesTheIndexTheHelperExpects() {
        // SwiftUI reports the row the item is dropped before, counted with the item still in place.
        #expect(CommandMove.targetIndex(from: 0, toOffset: 3) == 2)
        #expect(CommandMove.targetIndex(from: 2, toOffset: 0) == 0)
        #expect(CommandMove.targetIndex(from: 1, toOffset: 1) == 1)
        #expect(CommandMove.targetIndex(from: 1, toOffset: 2) == 1)
    }
}
