import Foundation
import Testing

@testable import DevDevCore

/// Auto-restart after a crash (`docs/spec.md` section 4), with shortened timings.
@Suite struct AutoRestartTests {
    private static let delay = Duration.milliseconds(400)
    private static let timings = Timings(
        killEscalation: .seconds(3), autoRestartDelay: delay, crashWindow: .seconds(30),
        fileChangeSettle: .milliseconds(100))

    private func queue(_ line: String, autoRestart: Bool = true) -> CommandSettings {
        CommandSettings(name: "Queue", commandLine: line, autoRestart: autoRestart)
    }

    /// Counts how many times the Command's Process has been started, through a file the script appends to.
    private func countingScript(_ h: Harness, then rest: String) -> String {
        "echo run >> '\(h.folder.path)/runs'; \(rest)"
    }

    /// Exits 1 on its first run. Every later run keeps running.
    private func crashesOnlyTheFirstTime(_ h: Harness) -> String {
        countingScript(
            h, then: "if [ $(wc -l < '\(h.folder.path)/runs') -lt 2 ]; then exit 1; fi; \(Script.runsForever)")
    }

    private func runs(_ h: Harness) -> Int {
        let text = (try? String(contentsOf: h.folder.appendingPathComponent("runs"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").count
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    @Test func theStandardTimingsAreOneSecondSixtySecondsAndHalfASecond() {
        #expect(Timings.standard.autoRestartDelay == .seconds(1))
        #expect(Timings.standard.crashWindow == .seconds(60))
        #expect(Timings.standard.fileChangeSettle == .milliseconds(500))
    }

    @Test func aCrashWithAutoRestartOnSendsOneCrashNotificationAndNoStartedOrRestarted() async throws {
        let poster = RecordingPoster()
        try await withHarness([queue("true")], timings: Self.timings, poster: poster) { h in
            try await h.engine.updateCommand(h.first, settings: queue(crashesOnlyTheFirstTime(h)))

            try await h.engine.start(h.first, origin: .agent)
            try await waitUntil("the Command ran twice") { runs(h) == 2 }
            try await h.waitForStatus(h.first, .running)
            try await settle()

            let agentStart = "Queue started by an agent"
            #expect(poster.notifications.map(\.body) == [agentStart, "Queue crashed (exit 1), auto-restarting"])
            #expect(poster.notifications.filter { $0.kind == .started || $0.kind == .restarted }.map(\.body) == [agentStart])
        }
    }

    /// The times come from the Process itself, not from when a subscriber got the events: under load
    /// the crash event can arrive late and make the wait look shorter than it was.
    @Test func autoRestartWaitsTheDelayAfterTheCrash() async throws {
        try await withHarness([queue("true")], timings: Self.timings) { h in
            let times = h.folder.appendingPathComponent("times")
            let stamp = "/usr/bin/perl -MTime::HiRes=time -e 'printf \"%.6f\\n\", time' >> '\(times.path)'"
            // Each run writes its start time, then lives 0.2 seconds, then crashes.
            try await h.engine.updateCommand(
                h.first, settings: queue(countingScript(h, then: "\(stamp); sleep 0.2; exit 1")))
            let log = await EventLog.listening(to: h.engine)
            try await h.engine.start(h.first, origin: .user)
            func starts() -> [Double] {
                let text = (try? String(contentsOf: times, encoding: .utf8)) ?? ""
                return text.split(separator: "\n").compactMap { Double($0) }
            }
            try await waitUntil("the Command started again") { starts().count >= 2 }

            let changes = await log.statusChanges
            let crash = try #require(changes.firstIndex { $0.cause == .crashed })
            let again = try #require(changes[crash...].firstIndex { $0.command.status == .running })
            #expect(changes[again].origin == .autoRestart)
            // The second run can start no sooner than the first run's 0.2 seconds plus the delay.
            let delay = Double(Self.delay.components.seconds) + Double(Self.delay.components.attoseconds) / 1e18
            let recorded = starts()
            #expect(recorded[1] - recorded[0] >= 0.2 + delay)
        }
    }

    @Test func autoRestartPausesAfterFiveCrashesInTheWindowWithOneExtraNotification() async throws {
        let poster = RecordingPoster()
        let timings = Timings(
            killEscalation: .seconds(3), autoRestartDelay: .milliseconds(50), crashWindow: .seconds(30))
        try await withHarness([queue("true")], timings: timings, poster: poster) { h in
            try await h.engine.updateCommand(h.first, settings: queue(countingScript(h, then: "exit 1")))
            try await h.engine.start(h.first, origin: .user)
            try await waitUntil("the Command ran five times") { runs(h) == 5 }
            try await h.waitForStatus(h.first, .crashed)
            try await Task.sleep(for: .milliseconds(500))

            #expect(runs(h) == 5)
            #expect(try await h.status(h.first) == .crashed)
            let bodies = poster.notifications.map(\.body)
            #expect(bodies.count == 6)
            #expect(bodies.prefix(4).allSatisfy { $0 == "Queue crashed (exit 1), auto-restarting" })
            #expect(bodies[4] == "Queue crashed (exit 1)")
            #expect(bodies[5] == "Queue auto-restart paused after 5 crashes")
            #expect(poster.notifications.allSatisfy { $0.kind == .crashed })
        }
    }

    @Test func crashesOutsideTheWindowDoNotCountTowardThePause() async throws {
        let timings = Timings(
            killEscalation: .seconds(3), autoRestartDelay: .milliseconds(10), crashWindow: .milliseconds(400))
        try await withHarness([queue("true")], timings: timings) { h in
            try await h.engine.updateCommand(
                h.first, settings: queue(countingScript(h, then: "sleep 0.15; exit 1")))
            try await h.engine.start(h.first, origin: .user)
            try await waitUntil("the Command ran eight times", timeout: .seconds(15)) { runs(h) >= 8 }
        }
    }

    @Test func aManualStartResetsTheCounter() async throws {
        let timings = Timings(
            killEscalation: .seconds(3), autoRestartDelay: .milliseconds(50), crashWindow: .seconds(30))
        try await withHarness([queue("true")], timings: timings) { h in
            try await h.engine.updateCommand(h.first, settings: queue(countingScript(h, then: "exit 1")))
            try await h.engine.start(h.first, origin: .user)
            try await waitUntil("the Command ran five times") { runs(h) == 5 }
            try await h.waitForStatus(h.first, .crashed)
            try await Task.sleep(for: .milliseconds(300))
            #expect(runs(h) == 5)

            try await h.engine.start(h.first, origin: .agent)
            try await waitUntil("the Command ran five more times") { runs(h) == 10 }
            try await Task.sleep(for: .milliseconds(300))
            #expect(runs(h) == 10)
            #expect(try await h.status(h.first) == .crashed)
        }
    }

    @Test func aStopDuringTheWaitCancelsTheAutoRestart() async throws {
        try await withHarness([queue("true")], timings: Self.timings) { h in
            try await h.engine.updateCommand(h.first, settings: queue(countingScript(h, then: "exit 1")))
            try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .crashed)
            try await h.engine.stop(h.first, origin: .user)
            try await Task.sleep(for: Self.delay * 2)

            #expect(runs(h) == 1)
            #expect(try await h.status(h.first) == .stopped)
        }
    }

    @Test func aManualStartDuringTheWaitCancelsTheAutoRestart() async throws {
        try await withHarness([queue("true")], timings: Self.timings) { h in
            try await h.engine.updateCommand(
                h.first,
                settings: queue(crashesOnlyTheFirstTime(h)))
            try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .crashed)
            try await h.engine.start(h.first, origin: .user)
            let pid = try await h.command(h.first).processID
            try await Task.sleep(for: Self.delay * 2)

            #expect(runs(h) == 2)
            #expect(try await h.status(h.first) == .running)
            #expect(try await h.command(h.first).processID == pid)
        }
    }

    @Test func autoRestartNeverActsOnAFinishedCommand() async throws {
        let poster = RecordingPoster()
        try await withHarness([queue("true")], timings: Self.timings, poster: poster) { h in
            try await h.engine.updateCommand(h.first, settings: queue(countingScript(h, then: "exit 0")))
            try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .finished)
            try await Task.sleep(for: Self.delay * 2)

            #expect(runs(h) == 1)
            #expect(try await h.status(h.first) == .finished)
            #expect(poster.notifications.map(\.body) == ["Queue finished"])
        }
    }

    @Test func autoRestartNeverActsOnAStoppedCommand() async throws {
        try await withHarness([queue("true")], timings: Self.timings) { h in
            // Exits 1 on SIGTERM: a requested stop is Stopped, never Crashed.
            try await h.engine.updateCommand(
                h.first, settings: queue(countingScript(h, then: Script.exitsOnTerm(code: 1))))
            try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")
            try await h.engine.stop(h.first, origin: .user)
            try await Task.sleep(for: Self.delay * 2)

            #expect(runs(h) == 1)
            #expect(try await h.status(h.first) == .stopped)
        }
    }

    @Test func aCrashWithAutoRestartOffStaysCrashed() async throws {
        try await withHarness([queue("true")], timings: Self.timings) { h in
            try await h.engine.updateCommand(
                h.first, settings: queue(countingScript(h, then: "exit 1"), autoRestart: false))
            try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .crashed)
            try await Task.sleep(for: Self.delay * 2)

            #expect(runs(h) == 1)
            #expect(try await h.status(h.first) == .crashed)
        }
    }

    @Test func theSwitchSavedFromTheEditFormTurnsAutoRestartOn() async throws {
        try await withHarness([queue("true")], timings: Self.timings) { h in
            var draft = CommandDraft(try await h.command(h.first).settings)
            draft.commandLine = crashesOnlyTheFirstTime(h)
            draft.autoRestart = false
            try await h.engine.updateCommand(h.first, settings: draft.settings)
            draft.autoRestart = true
            try await h.engine.updateCommand(h.first, settings: draft.settings)

            #expect(try await h.command(h.first).settings.autoRestart)
            try await h.engine.start(h.first, origin: .user)
            try await waitUntil("the Command ran twice") { runs(h) == 2 }
            try await h.waitForStatus(h.first, .running)
        }
    }
}
