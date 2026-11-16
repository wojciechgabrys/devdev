import Foundation
import Testing

@testable import DevDevCore

/// Start All, Stop All and Restart All.
@Suite struct ProjectActionTests {
    private func settings(_ name: String, _ line: String, included: Bool = true) -> CommandSettings {
        CommandSettings(name: name, commandLine: line, includedInStartAll: included)
    }

    @Test func startAllStartsEveryIncludedCommandThatIsNotRunningInCommandOrder() async throws {
        try await withHarness([
            settings("A", Script.runsForever),
            settings("B", Script.runsForever, included: false),
            settings("C", Script.runsForever),
            settings("D", Script.runsForever),
        ]) { h in
            let running = try await h.engine.start(h.commandIDs[2], origin: .user)
            let log = await EventLog.listening(to: h.engine)

            let project = try await h.engine.startAll(h.projectID, origin: .agent)

            #expect(project.commands.map(\.status) == [.running, .stopped, .running, .running])
            #expect(project.status == .running)
            // C was Running already and is left alone.
            #expect(project.commands[2].processID == running.processID)
            // A then D, the order of the Commands.
            try await waitUntil("two status events arrived") { await log.statusChanges.count == 2 }
            let changes = await log.statusChanges
            #expect(changes.map(\.command.id) == [h.commandIDs[0], h.commandIDs[3]])
            #expect(changes.allSatisfy { $0.cause == .started && $0.origin == .agent && $0.projectAction == .startAll })
        }
    }

    @Test func startAllStartsFinishedAndCrashedCommandsAgain() async throws {
        let once = { (ending: String) in "if [ -e $0.m ]; then \(Script.runsForever); else touch $0.m; \(ending); fi" }
        try await withHarness([
            settings("A", once("exit 0").replacingOccurrences(of: "$0", with: "a")),
            settings("B", once("exit 1").replacingOccurrences(of: "$0", with: "b")),
        ]) { h in
            _ = try await h.engine.startAll(h.projectID, origin: .user)
            try await h.waitForStatus(h.commandIDs[0], .finished)
            try await h.waitForStatus(h.commandIDs[1], .crashed)
            let project = try await h.engine.startAll(h.projectID, origin: .user)
            #expect(project.commands.map(\.status) == [.running, .running])
        }
    }

    @Test func stopAllStopsEveryRunningCommandWhetherOrNotItIsIncludedInStartAll() async throws {
        try await withHarness([
            settings("A", Script.runsForever),
            settings("B", Script.runsForever, included: false),
        ]) { h in
            let a = try await h.engine.start(h.commandIDs[0], origin: .user)
            let b = try await h.engine.start(h.commandIDs[1], origin: .user)

            let project = try await h.engine.stopAll(h.projectID, origin: .user)

            #expect(project.commands.map(\.status) == [.stopped, .stopped])
            #expect(project.status == .stopped)
            #expect(!processIsAlive(try #require(a.processID)))
            #expect(!processIsAlive(try #require(b.processID)))
        }
    }

    @Test func stopAllSetsEveryCrashedOrFinishedCommandOfTheProjectToStoppedAsWellAsStoppingTheRunningOnes()
        async throws
    {
        try await withHarness([
            settings("Runs", Script.runsForever),
            settings("Crashes", "exit 2"),
            settings("Finishes", "exit 0"),
            settings("Never started", "exit 0"),
        ]) { h in
            for id in h.commandIDs.prefix(3) {
                _ = try await h.engine.start(id, origin: .user)
            }
            try await h.waitForStatus(h.commandIDs[1], .crashed)
            try await h.waitForStatus(h.commandIDs[2], .finished)
            #expect(try await h.project().status == .crashed)
            #expect(try await h.status(h.commandIDs[0]) == .running)

            let project = try await h.engine.stopAll(h.projectID, origin: .user)

            #expect(project.commands.map(\.status) == [.stopped, .stopped, .stopped, .stopped])
            #expect(project.status == .stopped)
        }
    }

    @Test func restartAllRestartsOnlyTheRunningCommandsAndNeverStartsAStoppedFinishedOrCrashedOne() async throws {
        try await withHarness([
            settings("Runs", Script.runsForever),
            settings("Stopped", Script.runsForever),
            settings("Finished", "exit 0"),
            settings("Crashed", "exit 2"),
            settings("Runs too", Script.runsForever, included: false),
        ]) { h in
            let ids = h.commandIDs
            let first = try await h.engine.start(ids[0], origin: .user)
            _ = try await h.engine.start(ids[2], origin: .user)
            _ = try await h.engine.start(ids[3], origin: .user)
            let last = try await h.engine.start(ids[4], origin: .user)
            try await h.waitForStatus(ids[2], .finished)
            try await h.waitForStatus(ids[3], .crashed)

            let project = try await h.engine.restartAll(h.projectID, origin: .user)

            #expect(project.commands.map(\.status) == [.running, .stopped, .finished, .crashed, .running])
            #expect(project.commands[0].processID != first.processID)
            #expect(project.commands[4].processID != last.processID)
            #expect(project.commands[1].processID == nil)
            #expect(!processIsAlive(try #require(first.processID)))
            #expect(!processIsAlive(try #require(last.processID)))
            // The untouched Commands were not run again: no new output, no banner.
            #expect(try await !h.plainOutput(ids[2]).contains("started"))
            #expect(try await h.plainOutput(ids[1]).isEmpty)
        }
    }

    @Test func anActionOnAnUnknownProjectIsAnError() async throws {
        try await withHarness("exit 0") { h in
            await #expect(throws: HelperError.self) {
                try await h.engine.startAll(UUID(), origin: .user)
            }
        }
    }
}
