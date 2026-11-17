import Foundation
import Testing

@testable import DevDevCore

/// The state behind the Graphite window: output tabs, Go to Command, the menubar filter and the
/// short texts beside each Command.
@Suite struct GraphiteStateTests {
    private static func command(
        _ name: String, in projectID: UUID, _ status: CommandStatus = .stopped, line: String? = nil,
        exit: ProcessExit? = nil, startedAt: Date? = nil
    ) -> CommandSnapshot {
        CommandSnapshot(
            id: UUID(), projectID: projectID,
            settings: CommandSettings(name: name, commandLine: line ?? "run \(name)"),
            madeByDiscovery: false, status: status, lastExit: exit, restartToApply: false,
            startedAt: startedAt, processID: nil)
    }

    /// shop: serve, queue, vite. billing: serve, horizon.
    private struct Fixture {
        let shopID = UUID()
        let billingID = UUID()
        let serve: CommandSnapshot
        let queue: CommandSnapshot
        let vite: CommandSnapshot
        let billingServe: CommandSnapshot
        let horizon: CommandSnapshot

        init() {
            serve = GraphiteStateTests.command("serve", in: shopID, line: "php artisan serve")
            queue = GraphiteStateTests.command("queue", in: shopID, line: "php artisan queue:listen")
            vite = GraphiteStateTests.command("vite", in: shopID, .running, line: "npm run dev")
            billingServe = GraphiteStateTests.command("serve", in: billingID, line: "php artisan serve --port=8010")
            horizon = GraphiteStateTests.command("horizon", in: billingID, .crashed, exit: .exited(255))
        }

        func snapshot(dropping dropped: UUID? = nil) -> HelperSnapshot {
            HelperSnapshot(projects: [
                ProjectSnapshot(
                    id: shopID, name: "acme-shop", folder: "/tmp/shop", status: .partlyRunning,
                    commands: [serve, queue, vite].filter { $0.id != dropped }),
                ProjectSnapshot(
                    id: billingID, name: "billing-api", folder: "/tmp/billing", status: .crashed,
                    commands: [billingServe, horizon].filter { $0.id != dropped }),
            ])
        }

        func connected() -> WindowState {
            var state = WindowState()
            state.connected(snapshot: snapshot(), compatibility: .current)
            return state
        }
    }

    // MARK: - Output tabs

    @Test func theSelectedCommandAlwaysHasATabAndTabsSpanProjects() {
        let f = Fixture()
        var state = f.connected()
        #expect(state.tabs == [f.serve.id])

        state.select(command: f.vite.id)
        state.select(tab: f.horizon.id)

        #expect(state.tabs == [f.serve.id, f.vite.id, f.horizon.id])
        #expect(state.selectedProjectID == f.billingID)
        #expect(state.selectedCommand?.id == f.horizon.id)

        state.select(tab: f.serve.id)
        #expect(state.selectedProjectID == f.shopID)
        #expect(state.tabs.count == 3)
    }

    @Test func closingTheSelectedTabSelectsItsRightNeighbourThenItsLeft() {
        let f = Fixture()
        var state = f.connected()
        state.select(command: f.queue.id)
        state.select(command: f.vite.id)
        state.select(tab: f.queue.id)

        state.closeTab(f.queue.id)
        #expect(state.tabs == [f.serve.id, f.vite.id])
        #expect(state.selectedCommand?.id == f.vite.id)

        state.closeTab(f.vite.id)
        #expect(state.selectedCommand?.id == f.serve.id)

        state.closeTab(f.serve.id)
        #expect(state.tabs.isEmpty)
        #expect(state.selectedCommand == nil)
    }

    @Test func closingAnotherTabKeepsTheSelection() {
        let f = Fixture()
        var state = f.connected()
        state.select(command: f.vite.id)
        state.closeTab(f.serve.id)
        #expect(state.tabs == [f.vite.id])
        #expect(state.selectedCommand?.id == f.vite.id)
    }

    @Test func commandNumberPicksATabFromTheLeftAndZeroPicksTheLast() {
        let f = Fixture()
        var state = f.connected()
        state.select(tab: f.vite.id)
        state.select(tab: f.horizon.id)

        #expect(state.tab(number: 1) == f.serve.id)
        #expect(state.tab(number: 3) == f.horizon.id)
        #expect(state.tab(number: 4) == nil)
        #expect(state.tab(number: 9) == nil)
        #expect(state.tab(number: 0) == f.horizon.id)
        #expect(WindowState().tab(number: 0) == nil)
    }

    @Test func commandWClosesTheSelectedTabThenTheWindow() {
        let f = Fixture()
        var state = f.connected()
        state.select(tab: f.vite.id)
        #expect(state.closeTarget == .tab(f.vite.id))

        state.closeTab(f.vite.id)
        state.closeTab(f.serve.id)
        #expect(state.closeTarget == .window)
    }

    @Test func aDeletedCommandLosesItsTab() {
        let f = Fixture()
        var state = f.connected()
        state.select(tab: f.horizon.id)
        state.select(tab: f.vite.id)

        state.apply(.configuration(f.snapshot(dropping: f.horizon.id)))

        #expect(state.tabs == [f.serve.id, f.vite.id])
    }

    @Test func theStatusBarNamesTheHelperLink() {
        var state = WindowState()
        #expect(state.linkLabel == "Connecting to the Helper…")
        state.connected(snapshot: HelperSnapshot(projects: []), compatibility: .outdated)
        #expect(state.linkLabel == "Helper outdated")
        state.helperDied()
        #expect(state.linkLabel == "Helper stopped")
    }

    // MARK: - Go to Command

    @Test func anEmptyQueryListsEveryCommandInWindowOrder() {
        let f = Fixture()
        let names = CommandSearch.results(for: "  ", in: f.snapshot()).map(\.commandName)
        #expect(names == ["serve", "queue", "vite", "serve", "horizon"])
    }

    @Test func goToCommandResultsWithEqualScoresComeOutInSnapshotOrder() {
        let shopID = UUID()
        let billingID = UUID()
        // Not in order of name, so a second sort by name here would show.
        let snapshot = HelperSnapshot(projects: [
            ProjectSnapshot(
                id: shopID, name: "shop", folder: "/tmp/shop", status: .stopped,
                commands: ["zeta worker", "mail", "alpha worker"].map { Self.command($0, in: shopID) }),
            ProjectSnapshot(
                id: billingID, name: "billing", folder: "/tmp/billing", status: .stopped,
                commands: ["beta worker", "worker one"].map { Self.command($0, in: billingID) }),
        ])

        let names = CommandSearch.results(for: "worker", in: snapshot).map(\.commandName)

        // "worker one" starts with the word, so it scores better. The other three score the same.
        #expect(names == ["worker one", "zeta worker", "alpha worker", "beta worker"])
    }

    @Test func everyWordMustMatchAndNameMatchesComeFirst() {
        let f = Fixture()
        let snapshot = f.snapshot()

        #expect(CommandSearch.results(for: "serve bill", in: snapshot).map(\.commandID) == [f.billingServe.id])
        #expect(CommandSearch.results(for: "HOR", in: snapshot).map(\.commandID) == [f.horizon.id])
        // "artisan" is only in command lines; "queue" also in a name, so that one ranks first.
        #expect(CommandSearch.results(for: "artisan", in: snapshot).count == 3)
        #expect(CommandSearch.results(for: "queue", in: snapshot).first?.commandID == f.queue.id)
        // A Project-name match ranks below a name match.
        let ranked = CommandSearch.results(for: "s", in: snapshot).map(\.commandID)
        #expect(ranked.prefix(2) == [f.serve.id, f.billingServe.id])
        #expect(CommandSearch.results(for: "nothing", in: snapshot).isEmpty)
    }

    // MARK: - Menubar filter

    @Test func theMenubarFilterKeepsMatchingCommandsOrWholeMatchingProjects() {
        let f = Fixture()
        let panel = MenubarPanel(snapshot: f.snapshot())

        #expect(panel.filtered(by: "") == panel)

        let byCommand = panel.filtered(by: "serve")
        #expect(byCommand.rows.map(\.name) == ["acme-shop", "billing-api"])
        #expect(byCommand.rows.map { $0.commands.map(\.name) } == [["serve"], ["serve"]])

        let byProject = panel.filtered(by: "billing")
        #expect(byProject.rows.map(\.name) == ["billing-api"])
        #expect(byProject.rows[0].commands.count == 2)

        let both = panel.filtered(by: "billing hor")
        #expect(both.rows.map { $0.commands.map(\.name) } == [["horizon"]])

        #expect(panel.filtered(by: "nothing").rows.isEmpty)
        #expect(panel.runningCount == 1)
        #expect(panel.crashedCount == 1)
    }

    // MARK: - Short texts

    @Test func theShortTextSaysHowLongItRanOrHowItEnded() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        func running(_ seconds: TimeInterval) -> String {
            CommandDetail.short(status: .running, lastExit: nil, startedAt: now - seconds, now: now)
        }
        #expect(running(20) == "<1m")
        #expect(running(38 * 60) == "38m")
        #expect(running(2 * 3600 + 4 * 60) == "2h 04m")
        #expect(running(3 * 86400 + 5 * 3600) == "3d 5h")
        #expect(CommandDetail.short(status: .crashed, lastExit: .exited(255), startedAt: nil, now: now) == "exit 255")
        #expect(CommandDetail.short(status: .crashed, lastExit: .signalled(9), startedAt: nil, now: now) == "signal 9")
        #expect(CommandDetail.short(status: .stopped, lastExit: nil, startedAt: nil, now: now) == "stopped")
    }

    @Test func theSnapshotCountsRunningAndCrashedCommands() {
        let snapshot = Fixture().snapshot()
        #expect(snapshot.runningCount == 1)
        #expect(snapshot.crashedCount == 1)
    }
}
