import Foundation
import Testing

@testable import DevDevCore

/// Every Command status transition (`docs/spec.md` section 4, plus the feature spec's added decisions).
@Suite struct CommandStatusTests {
    @Test func aCommandThatWasNeverStartedIsStopped() async throws {
        try await withHarness("echo hi") { h in
            let status = try await h.status(h.first)
            #expect(status == .stopped)
        }
    }

    @Test func startingAStoppedCommandMakesItRunning() async throws {
        try await withHarness(Script.runsForever) { h in
            let started = try await h.engine.start(h.first, origin: .user)
            #expect(started.status == .running)
            #expect(try await h.status(h.first) == .running)
        }
    }

    @Test func startingARunningCommandIsANoOpThatReturnsTheCurrentStatus() async throws {
        try await withHarness(Script.runsForever) { h in
            let first = try await h.engine.start(h.first, origin: .user)
            let second = try await h.engine.start(h.first, origin: .user)
            #expect(second.status == .running)
            #expect(second.processID == first.processID)
            #expect(second.startedAt == first.startedAt)
        }
    }

    @Test func aProcessThatEndsByItselfWithExitCodeZeroLeavesTheCommandFinished() async throws {
        try await withHarness("exit 0") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .finished)
            #expect(try await h.command(h.first).lastExit == .exited(0))
        }
    }

    @Test func aProcessThatEndsByItselfWithANonZeroExitCodeLeavesTheCommandCrashed() async throws {
        try await withHarness("exit 3") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .crashed)
            #expect(try await h.command(h.first).lastExit == .exited(3))
        }
    }

    @Test func aProcessEndedByASignalItDidNotAskForLeavesTheCommandCrashed() async throws {
        try await withHarness("kill -KILL $$") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .crashed)
            #expect(try await h.command(h.first).lastExit == .signalled(SIGKILL))
        }
    }

    @Test(arguments: [
        Script.exitsOnTerm(code: 0),
        Script.exitsOnTerm(code: 7),
        Script.runsForever,
    ])
    func aRequestedStopEndsInStoppedWhateverTheExit(commandLine: String) async throws {
        try await withHarness(commandLine) { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")
            let stopped = try await h.engine.stop(h.first, origin: .user)
            #expect(stopped.status == .stopped)
            #expect(stopped.processID == nil)
            #expect(try await h.status(h.first) == .stopped)
        }
    }

    @Test func aRequestedStopReportsTheExitCodeButStaysStopped() async throws {
        try await withHarness(Script.exitsOnTerm(code: 7)) { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")
            let stopped = try await h.engine.stop(h.first, origin: .user)
            #expect(stopped.lastExit == .exited(7))
            #expect(stopped.status == .stopped)
        }
    }

    @Test func stopOnACrashedCommandSetsItToStopped() async throws {
        try await withHarness("exit 1") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .crashed)
            let stopped = try await h.engine.stop(h.first, origin: .user)
            #expect(stopped.status == .stopped)
            #expect(try await h.status(h.first) == .stopped)
        }
    }

    @Test func stopOnAFinishedCommandSetsItToStopped() async throws {
        try await withHarness("exit 0") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .finished)
            let stopped = try await h.engine.stop(h.first, origin: .user)
            #expect(stopped.status == .stopped)
        }
    }

    @Test func stopOnAStoppedCommandLeavesItStopped() async throws {
        try await withHarness("exit 0") { h in
            let stopped = try await h.engine.stop(h.first, origin: .user)
            #expect(stopped.status == .stopped)
        }
    }

    @Test(arguments: ["exit 0", "exit 1"])
    func aFinishedOrCrashedCommandCanBeStartedAgain(firstRun: String) async throws {
        // The first run ends at once. The marker file makes the second run stay up.
        let line = "if [ -e marker ]; then \(Script.runsForever); else touch marker; \(firstRun); fi"
        try await withHarness(line) { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await waitUntil("the first run ended") { try await h.status(h.first) != .running }
            let again = try await h.engine.start(h.first, origin: .user)
            #expect(again.status == .running)
            #expect(again.lastExit == nil)
        }
    }

    @Test func restartOfARunningCommandStopsItAndStartsANewProcess() async throws {
        try await withHarness(Script.runsForever) { h in
            let log = await EventLog.listening(to: h.engine)
            let first = try await h.engine.start(h.first, origin: .user)
            let firstPID = try #require(first.processID)
            let restarted = try await h.engine.restart(h.first, origin: .agent)
            #expect(restarted.status == .running)
            #expect(restarted.processID != nil)
            #expect(restarted.processID != firstPID)
            try await waitUntil("the old Process is gone") { !processIsAlive(firstPID) }

            try await waitUntil("three status events arrived") { await log.statusChanges.count == 3 }
            let changes = await log.statusChanges
            #expect(changes.map(\.cause) == [.started, .stoppedForRestart, .restarted])
            #expect(changes.map(\.command.status) == [.running, .stopped, .running])
            #expect(changes.map(\.origin) == [.user, .agent, .agent])
        }
    }

    @Test(arguments: ["", "exit 0", "exit 1"])
    func aSingleRestartOnACommandThatIsNotRunningStartsItAndIsReportedAsAStart(firstRun: String) async throws {
        // An empty first run means the Command was never started: it is Stopped.
        let line = "if [ -e marker ]; then \(Script.runsForever); else touch marker; \(firstRun); fi"
        try await withHarness(firstRun.isEmpty ? Script.runsForever : line) { h in
            if !firstRun.isEmpty {
                _ = try await h.engine.start(h.first, origin: .user)
                try await waitUntil("the first run ended") { try await h.status(h.first) != .running }
            }
            let log = await EventLog.listening(to: h.engine)
            let restarted = try await h.engine.restart(h.first, origin: .agent)
            #expect(restarted.status == .running)
            try await waitUntil("a status event arrived") { await !log.statusChanges.isEmpty }
            #expect(await log.statusChanges.map(\.cause) == [.started])
            #expect(try await !h.plainOutput(h.first).contains("restarted"))
        }
    }

    @Test func aStopRequestedWhileARestartIsStoppingTheProcessCancelsTheNewStart() async throws {
        try await withHarness("trap 'sleep 0.5; exit 0' TERM; \(Script.runsForever)") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")
            async let restarted = h.engine.restart(h.first, origin: .user)
            try await Task.sleep(for: .milliseconds(150))
            let stopped = try await h.engine.stop(h.first, origin: .user)
            #expect(stopped.status == .stopped)
            #expect(try await restarted.status == .stopped)
            #expect(try await h.status(h.first) == .stopped)
        }
    }

    @Test func anUnknownCommandIsAnErrorThatNamesTheProblem() async throws {
        try await withHarness("exit 0") { h in
            await #expect(throws: HelperError.self) {
                try await h.engine.start(UUID(), origin: .user)
            }
        }
    }
}
