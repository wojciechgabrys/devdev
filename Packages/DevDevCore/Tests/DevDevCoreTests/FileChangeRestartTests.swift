import Foundation
import Testing

@testable import DevDevCore

/// "Restart when files change" (`docs/spec.md` section 4), with a shortened settle time.
@Suite struct FileChangeRestartTests {
    private static let settleTime = Duration.milliseconds(300)
    private static let timings = Timings(killEscalation: .seconds(3), fileChangeSettle: settleTime)

    /// A Command that appends a line to `runs` each time it starts, then runs until stopped.
    private func vite(_ h: Harness, globs: [String], then rest: String = Script.runsForever) -> CommandSettings {
        CommandSettings(
            name: "Vite", commandLine: "echo run >> '\(h.folder.path)/runs'; \(rest)", restartWhenFilesChange: globs)
    }

    private func runs(_ h: Harness) -> Int {
        let text = (try? String(contentsOf: h.folder.appendingPathComponent("runs"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").count
    }

    private func path(_ h: Harness, _ relative: String) -> String {
        h.projectFolder.appendingPathComponent(relative).path
    }

    @Test func aMatchingChangeRestartsARunningCommandOnceAfterTheSettleTime() async throws {
        let poster = RecordingPoster()
        try await withHarness([CommandSettings(name: "Vite", commandLine: "true")], timings: Self.timings, poster: poster) { h in
            try await h.engine.updateCommand(h.first, settings: vite(h, globs: ["app/**/*.php"]))
            let log = await EventLog.listening(to: h.engine)
            try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")

            // A save-all: several changes, each less than the settle time apart.
            for name in ["User", "Post", "Comment"] {
                await h.engine.filesChanged([path(h, "app/Models/\(name).php")])
                try await Task.sleep(for: .milliseconds(100))
            }
            try await Task.sleep(for: .milliseconds(100))
            #expect(runs(h) == 1, "no restart before the changes have been quiet for the settle time")

            try await waitUntil("the Command restarted") { runs(h) == 2 }
            try await h.waitForStatus(h.first, .running)
            try await Task.sleep(for: Self.settleTime * 2)
            #expect(runs(h) == 2)

            let restarted = await log.statusChanges.filter { $0.cause == .restarted }
            #expect(restarted.map(\.origin) == [.fileChange])
            #expect(poster.notifications.map(\.body) == ["Vite restarted, files changed"])
        }
    }

    @Test func aNonMatchingChangeDoesNothing() async throws {
        try await withHarness([CommandSettings(name: "Vite", commandLine: "true")], timings: Self.timings) { h in
            try await h.engine.updateCommand(h.first, settings: vite(h, globs: ["app/*.php"]))
            try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")
            let pid = try await h.command(h.first).processID

            await h.engine.filesChanged([
                path(h, "app/app.js"), path(h, "app/Models/User.php"), path(h, "routes/app/web.php"),
            ])
            try await Task.sleep(for: Self.settleTime * 2)

            #expect(runs(h) == 1)
            #expect(try await h.command(h.first).processID == pid)
        }
    }

    @Test func globsAreMatchedRelativeToTheProjectFolder() async throws {
        try await withHarness([CommandSettings(name: "Vite", commandLine: "true")], timings: Self.timings) { h in
            try await h.engine.updateCommand(h.first, settings: vite(h, globs: ["config/*.php"]))
            try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")

            // Same relative name, but outside the Project folder.
            await h.engine.filesChanged([h.folder.appendingPathComponent("config/app.php").path])
            try await Task.sleep(for: Self.settleTime * 2)
            #expect(runs(h) == 1)

            await h.engine.filesChanged([path(h, "config/app.php")])
            try await waitUntil("the Command restarted") { runs(h) == 2 }
        }
    }

    @Test func aChangeNeverStartsACommandThatIsNotRunning() async throws {
        try await withHarness(
            [CommandSettings(name: "Stopped", commandLine: "true"), CommandSettings(name: "Crashed", commandLine: "true"),
             CommandSettings(name: "Finished", commandLine: "true")],
            timings: Self.timings
        ) { h in
            let (stopped, crashed, finished) = (h.commandIDs[0], h.commandIDs[1], h.commandIDs[2])
            var settings = vite(h, globs: ["**"])
            settings.name = "Stopped"
            try await h.engine.updateCommand(stopped, settings: settings)
            settings = vite(h, globs: ["**"], then: "exit 1")
            settings.name = "Crashed"
            try await h.engine.updateCommand(crashed, settings: settings)
            settings = vite(h, globs: ["**"], then: "exit 0")
            settings.name = "Finished"
            try await h.engine.updateCommand(finished, settings: settings)
            try await h.engine.start(crashed, origin: .user)
            try await h.engine.start(finished, origin: .user)
            try await h.waitForStatus(crashed, .crashed)
            try await h.waitForStatus(finished, .finished)

            await h.engine.filesChanged([path(h, "index.php")])
            try await Task.sleep(for: Self.settleTime * 2)

            #expect(runs(h) == 2)
            #expect(try await h.status(stopped) == .stopped)
            #expect(try await h.status(crashed) == .crashed)
            #expect(try await h.status(finished) == .finished)
        }
    }

    @Test func aCommandStoppedDuringTheSettleTimeIsNotStartedAgain() async throws {
        try await withHarness([CommandSettings(name: "Vite", commandLine: "true")], timings: Self.timings) { h in
            try await h.engine.updateCommand(h.first, settings: vite(h, globs: ["**"]))
            try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")

            await h.engine.filesChanged([path(h, "index.php")])
            try await h.engine.stop(h.first, origin: .user)
            try await Task.sleep(for: Self.settleTime * 2)

            #expect(runs(h) == 1)
            #expect(try await h.status(h.first) == .stopped)
        }
    }

    @Test func aRealFileWrittenInTheProjectFolderRestartsTheCommand() async throws {
        try await withHarness([CommandSettings(name: "Vite", commandLine: "true")], timings: Self.timings) { h in
            // The globs as the edit form sends them: one pattern per line.
            var draft = CommandDraft(try await h.command(h.first).settings)
            draft.commandLine = vite(h, globs: []).commandLine
            draft.restartWhenFilesChange = "app/**/*.php\n\n  resources/*.css  \n"
            try await h.engine.updateCommand(h.first, settings: draft.settings)
            #expect(try await h.command(h.first).settings.restartWhenFilesChange == ["app/**/*.php", "resources/*.css"])

            try FileManager.default.createDirectory(
                at: h.projectFolder.appendingPathComponent("app/Models"), withIntermediateDirectories: true)
            try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")
            // Let the folder watch begin before the write.
            try await Task.sleep(for: .milliseconds(300))

            try Data("<?php\n".utf8).write(to: h.projectFolder.appendingPathComponent("app/Models/User.php"))
            try await waitUntil("the Command restarted") { runs(h) == 2 }
        }
    }
}
