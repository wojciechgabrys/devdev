import Foundation
import Testing

@testable import DevDevCore

/// A notification poster that records what the Helper posts.
final class RecordingPoster: NotificationPoster, @unchecked Sendable {
    private let lock = NSLock()
    private var posted: [SystemNotification] = []

    var notifications: [SystemNotification] { lock.withLock { posted } }

    func post(_ notification: SystemNotification) {
        lock.withLock { posted.append(notification) }
    }
}

/// The notifications the Helper sends for real Processes, with each origin.
@Suite struct HelperNotificationTests {
    private func settings(_ name: String, _ line: String) -> CommandSettings {
        CommandSettings(name: name, commandLine: line)
    }

    /// Lets any late notification arrive before checking that none did.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    @Test func aUserOriginSendsNoStartedRestartedOrStoppedNotification() async throws {
        let poster = RecordingPoster()
        try await withHarness([settings("Queue", Script.runsForever)], poster: poster) { h in
            try await h.engine.start(h.first, origin: .user)
            try await h.engine.restart(h.first, origin: .user)
            try await h.engine.stop(h.first, origin: .user)
            try await h.engine.startAll(h.projectID, origin: .user)
            try await h.engine.restartAll(h.projectID, origin: .user)
            try await h.engine.stopAll(h.projectID, origin: .user)
            try await h.engine.restart(h.first, origin: .user)
            try await settle()
            #expect(poster.notifications.isEmpty)
        }
    }

    @Test func aCrashAlwaysSendsOneWithTheExitCodeEvenAfterAUserStart() async throws {
        let poster = RecordingPoster()
        try await withHarness([settings("Queue", "sleep 0.1; exit 1")], poster: poster) { h in
            try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .crashed)
            try await waitUntil("the crash notification arrived") { !poster.notifications.isEmpty }
            try await settle()
            #expect(poster.notifications.map(\.kind) == [.crashed])
            #expect(poster.notifications.first?.body == "Queue crashed (exit 1)")
            #expect(poster.notifications.first?.commandID == h.first)
        }
    }

    @Test func startAllFromANonUserOriginSendsExactlyOne() async throws {
        let poster = RecordingPoster()
        try await withHarness(
            [settings("Queue", Script.runsForever), settings("Vite", Script.runsForever),
             settings("Server", Script.runsForever)],
            poster: poster
        ) { h in
            try await h.engine.startAll(h.projectID, origin: .agent)
            try await settle()
            #expect(poster.notifications.count == 1)
            #expect(poster.notifications.first?.kind == .started)
            #expect(poster.notifications.first?.body == "Start All by an agent: Queue, Server and Vite started")
            #expect(poster.notifications.first?.commandID == h.commandIDs[0])
        }
    }

    @Test func restartAllAndStopAllFromANonUserOriginEachSendOne() async throws {
        let poster = RecordingPoster()
        try await withHarness(
            [settings("Queue", Script.runsForever), settings("Vite", Script.runsForever)], poster: poster
        ) { h in
            try await h.engine.startAll(h.projectID, origin: .user)
            try await h.engine.restartAll(h.projectID, origin: .agent)
            try await settle()
            #expect(poster.notifications.map(\.kind) == [.restarted])
            #expect(poster.notifications.last?.body == "Restart All by an agent: Queue and Vite restarted")

            try await h.engine.stopAll(h.projectID, origin: .agent)
            try await settle()
            #expect(poster.notifications.map(\.kind) == [.restarted, .stoppedOrFinished])
            #expect(poster.notifications.last?.body == "Stop All by an agent: Queue and Vite stopped")
        }
    }

    @Test func stopOnACrashedOrFinishedCommandSetsItToStoppedAndSendsNoNotification() async throws {
        let poster = RecordingPoster()
        try await withHarness(
            [settings("Queue", "exit 3"), settings("Once", "exit 0")], poster: poster
        ) { h in
            let crashed = h.commandIDs[0]
            let finished = h.commandIDs[1]
            try await h.engine.start(crashed, origin: .agent)
            try await h.engine.start(finished, origin: .agent)
            try await h.waitForStatus(crashed, .crashed)
            try await h.waitForStatus(finished, .finished)
            try await settle()
            let before = poster.notifications.count

            #expect(try await h.engine.stop(crashed, origin: .agent).status == .stopped)
            #expect(try await h.engine.stop(finished, origin: .agent).status == .stopped)
            try await settle()

            #expect(poster.notifications.count == before)
        }
    }

    @Test func finishedNotifiesEvenAfterAUserStart() async throws {
        let poster = RecordingPoster()
        try await withHarness([settings("Once", "exit 0")], poster: poster) { h in
            try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .finished)
            try await waitUntil("the notification arrived") { !poster.notifications.isEmpty }
            #expect(poster.notifications.map(\.body) == ["Once finished"])
        }
    }

    @Test func aSingleRestartOnANotRunningCommandFromANonUserOriginSendsStartedNotRestarted() async throws {
        let poster = RecordingPoster()
        try await withHarness([settings("Queue", Script.runsForever)], poster: poster) { h in
            try await h.engine.restart(h.first, origin: .agent)
            try await settle()
            #expect(poster.notifications.map(\.kind) == [.started])
            #expect(poster.notifications.first?.body == "Queue started by an agent")
        }
    }

    @Test func singleActionsFromAnAgentEachSendOneNamingTheAgent() async throws {
        let poster = RecordingPoster()
        try await withHarness([settings("Queue", Script.runsForever)], poster: poster) { h in
            try await h.engine.start(h.first, origin: .agent)
            try await h.engine.restart(h.first, origin: .agent)
            try await h.engine.stop(h.first, origin: .agent)
            try await settle()
            #expect(poster.notifications.map(\.body) == [
                "Queue started by an agent", "Queue restarted by an agent", "Queue stopped by an agent",
            ])
        }
    }

    @Test func aFileChangeRestartNamesTheCause() async throws {
        let poster = RecordingPoster()
        try await withHarness([settings("Vite", Script.runsForever)], poster: poster) { h in
            try await h.engine.start(h.first, origin: .user)
            try await h.engine.restart(h.first, origin: .fileChange)
            try await settle()
            #expect(poster.notifications.map(\.body) == ["Vite restarted, files changed"])
        }
    }

    @Test func aSwitchTurnedOffInSettingsSuppressesItsKind() async throws {
        let poster = RecordingPoster()
        try await withHarness([settings("Queue", Script.runsForever)], poster: poster) { h in
            var changed = await h.engine.settings()
            changed.notifications.started = false
            try await h.engine.updateSettings(changed)

            try await h.engine.start(h.first, origin: .agent)
            try await h.engine.stop(h.first, origin: .agent)
            try await settle()
            #expect(poster.notifications.map(\.kind) == [.stoppedOrFinished])
        }
    }
}
