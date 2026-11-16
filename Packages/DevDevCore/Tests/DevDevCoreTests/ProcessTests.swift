import Foundation
import Testing

@testable import DevDevCore

/// Running and stopping real child processes through `/bin/sh`.
@Suite struct ProcessTests {
    @Test func stoppingAProcessThatIgnoresSIGTERMEndsWithSIGKILLToItsGroupAfterTheEscalationTime() async throws {
        let escalation = Duration.milliseconds(400)
        try await withHarness(Script.ignoresTerm, timings: Timings(killEscalation: escalation)) { h in
            let started = try await h.engine.start(h.first, origin: .user)
            let pid = try #require(started.processID)
            try await h.waitForOutput(h.first, containing: "ready")

            let clock = ContinuousClock()
            var stopped: CommandSnapshot?
            let elapsed = try await clock.measure {
                stopped = try await h.engine.stop(h.first, origin: .user)
            }

            #expect(elapsed >= escalation)
            #expect(elapsed < .seconds(3))
            #expect(stopped?.status == .stopped)
            #expect(stopped?.lastExit == .signalled(SIGKILL))
            #expect(!processIsAlive(pid))
            // Nothing is left in the group the Process led.
            #expect(kill(-pid, 0) == -1)
        }
    }

    @Test func stoppingAProcessThatObeysSIGTERMDoesNotWaitForTheEscalationTime() async throws {
        try await withHarness(Script.exitsOnTerm(code: 0), timings: Timings(killEscalation: .seconds(30))) { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")
            let elapsed = try await ContinuousClock().measure {
                _ = try await h.engine.stop(h.first, origin: .user)
            }
            #expect(elapsed < .seconds(5))
            #expect(try await h.command(h.first).lastExit == .exited(0))
        }
    }

    @Test func stoppingACommandAlsoKillsAChildOfItsChildProcess() async throws {
        let line = "/bin/sh -c 'sleep 300 & echo grandchild=$!; echo ready; wait' & echo child=$!; wait"
        try await withHarness(line) { h in
            let started = try await h.engine.start(h.first, origin: .user)
            let pid = try #require(started.processID)
            try await h.waitForOutput(h.first, containing: "ready")
            let output = try await h.plainOutput(h.first)
            let child = try #require(pidNamed("child", in: output))
            let grandchild = try #require(pidNamed("grandchild", in: output))
            #expect(Set([pid, child, grandchild]).count == 3)
            #expect(processIsAlive(child))
            #expect(processIsAlive(grandchild))

            _ = try await h.engine.stop(h.first, origin: .user)

            try await waitUntil("the child of the child is gone") { !processIsAlive(grandchild) }
            #expect(!processIsAlive(child))
            #expect(!processIsAlive(pid))
        }
    }

    @Test func stoppingACommandAlsoKillsAJobTheShellPutInAnotherProcessGroup() async throws {
        // `set -m` is what an interactive login shell does: each job gets a process group of its own.
        let line = "set -m; sleep 300 & echo job=$!; echo ready; wait"
        try await withHarness(line) { h in
            let started = try await h.engine.start(h.first, origin: .user)
            let pid = try #require(started.processID)
            try await h.waitForOutput(h.first, containing: "ready")
            let job = try #require(pidNamed("job", in: try await h.plainOutput(h.first)))
            #expect(getpgid(job) != getpgid(pid))

            _ = try await h.engine.stop(h.first, origin: .user)

            try await waitUntil("the job is gone") { !processIsAlive(job) }
        }
    }

    @Test func theProcessRunsInTheSubfolderWithTheEnvironmentVariablesAndOnAPseudoTerminal() async throws {
        let settings = CommandSettings(
            name: "Main",
            commandLine: "echo \"dir=$(pwd -P)\"; echo \"var=$DEVDEV_TEST_VALUE\"; [ -t 1 ] && echo terminal=yes; stty size",
            subfolder: "sub/folder",
            environment: [EnvironmentVariable(name: "DEVDEV_TEST_VALUE", value: "hello there")])
        try await withHarness([settings]) { h in
            let sub = h.projectFolder.appendingPathComponent("sub/folder")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .finished)
            let output = try await h.plainOutput(h.first)
            #expect(output.contains("/\(h.folder.lastPathComponent)/project/sub/folder\n"))
            #expect(output.contains("var=hello there\n"))
            #expect(output.contains("terminal=yes\n"))
            // The default size for a Process nobody is watching: 40 rows, 120 columns.
            #expect(output.contains("\n40 120\n"))
        }
    }

    @Test func resizingChangesThePseudoTerminalOfTheRunningProcessAndOfTheNextOne() async throws {
        try await withHarness("trap 'stty size' WINCH; stty size; \(Script.runsForever)") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")
            try await h.engine.resize(h.first, to: TerminalSize(columns: 100, rows: 30))
            try await h.waitForOutput(h.first, containing: "30 100")
            _ = try await h.engine.restart(h.first, origin: .user)
            try await waitUntil("the new Process printed its size") {
                try await h.plainOutput(h.first).components(separatedBy: "30 100").count >= 3
            }
        }
    }

    @Test func aCommandWhoseFolderIsMissingIsCrashedAndSaysWhy() async throws {
        let settings = CommandSettings(name: "Main", commandLine: "echo hi", subfolder: "missing")
        try await withHarness([settings]) { h in
            let started = try await h.engine.start(h.first, origin: .user)
            #expect(started.status == .crashed)
            #expect(try await h.plainOutput(h.first).contains("could not start"))
        }
    }

    private func pidNamed(_ name: String, in output: String) -> Int32? {
        for line in output.split(separator: "\n") where line.hasPrefix("\(name)=") {
            return Int32(line.dropFirst(name.count + 1))
        }
        return nil
    }
}
