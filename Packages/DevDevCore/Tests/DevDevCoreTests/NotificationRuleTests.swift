import Foundation
import Testing

@testable import DevDevCore

/// Which notification the Helper sends for a change, and its text (`docs/spec.md` section 9).
@Suite struct NotificationRuleTests {
    private let project = NotificationRule.Subject(projectID: UUID(), projectName: "shop")
    private let queue = UUID()
    private let vite = UUID()

    private func send(_ trigger: NotificationTrigger, _ settings: NotificationSettings = NotificationSettings())
        -> SystemNotification?
    {
        NotificationRule.notification(for: trigger, in: project, settings: settings)
    }

    @Test func aUserOriginSendsNoStartedRestartedOrStoppedNotification() {
        let one = [NotificationTrigger.Target(id: queue, name: "Queue")]
        #expect(send(.started(one, origin: .user, action: nil)) == nil)
        #expect(send(.restarted(one, origin: .user, action: nil)) == nil)
        #expect(send(.stopped(one, origin: .user, action: nil)) == nil)
        #expect(send(.started(one, origin: .user, action: .startAll)) == nil)
        #expect(send(.restarted(one, origin: .user, action: .restartAll)) == nil)
        #expect(send(.stopped(one, origin: .user, action: .stopAll)) == nil)
    }

    @Test func aCrashAlwaysSendsOneWithTheExitCode() {
        let notification = send(.crashed(.init(id: queue, name: "Queue"), exit: .exited(1), autoRestarting: false))
        #expect(notification == SystemNotification(
            kind: .crashed, title: "shop", body: "Queue crashed (exit 1)", projectID: project.projectID, commandID: queue))
    }

    @Test func aCrashBySignalOrAFailedStartNamesThatInstead() {
        let target = NotificationTrigger.Target(id: queue, name: "Queue")
        #expect(send(.crashed(target, exit: .signalled(9), autoRestarting: false))?.body == "Queue crashed (signal 9)")
        #expect(send(.crashed(target, exit: nil, autoRestarting: false))?.body == "Queue crashed (could not start)")
    }

    @Test func aCrashThatAutoRestartsSaysSo() {
        let notification = send(.crashed(.init(id: queue, name: "Queue"), exit: .exited(1), autoRestarting: true))
        #expect(notification?.body == "Queue crashed (exit 1), auto-restarting")
    }

    @Test func finishedAlwaysNotifiesWhateverTheOrigin() {
        let notification = send(.finished(.init(id: vite, name: "Vite")))
        #expect(notification == SystemNotification(
            kind: .stoppedOrFinished, title: "shop", body: "Vite finished", projectID: project.projectID,
            commandID: vite))
    }

    @Test func theTextNamesTheCause() {
        let queueOnly = [NotificationTrigger.Target(id: queue, name: "Queue")]
        let viteOnly = [NotificationTrigger.Target(id: vite, name: "Vite")]
        #expect(send(.restarted(queueOnly, origin: .agent, action: nil))?.body == "Queue restarted by an agent")
        #expect(send(.restarted(viteOnly, origin: .fileChange, action: nil))?.body == "Vite restarted, files changed")
        #expect(send(.started(queueOnly, origin: .agent, action: nil))?.body == "Queue started by an agent")
        #expect(send(.stopped(queueOnly, origin: .agent, action: nil))?.body == "Queue stopped by an agent")
    }

    @Test func autoRestartSendsNoSeparateStartedOrRestarted() {
        let one = [NotificationTrigger.Target(id: queue, name: "Queue")]
        #expect(send(.started(one, origin: .autoRestart, action: nil)) == nil)
        #expect(send(.restarted(one, origin: .autoRestart, action: nil)) == nil)
    }

    @Test func aWholeProjectActionIsOneNotificationForTheProjectThatOpensItsFirstCommand() {
        let both = [
            NotificationTrigger.Target(id: queue, name: "Queue"), NotificationTrigger.Target(id: vite, name: "Vite"),
        ]
        #expect(send(.started(both, origin: .agent, action: .startAll)) == SystemNotification(
            kind: .started, title: "shop", body: "Start All by an agent: Queue and Vite started",
            projectID: project.projectID, commandID: queue))
        #expect(send(.restarted(both, origin: .agent, action: .restartAll))?.body
            == "Restart All by an agent: Queue and Vite restarted")
        #expect(send(.stopped(both, origin: .agent, action: .stopAll))?.body
            == "Stop All by an agent: Queue and Vite stopped")
    }

    @Test func aProjectActionThatChangedNothingSendsNothing() {
        #expect(send(.started([], origin: .agent, action: .startAll)) == nil)
        #expect(send(.stopped([], origin: .agent, action: .stopAll)) == nil)
    }

    @Test func eachSwitchThatIsOffSuppressesItsKind() {
        let one = [NotificationTrigger.Target(id: queue, name: "Queue")]
        let triggers: [NotificationKind: NotificationTrigger] = [
            .crashed: .crashed(one[0], exit: .exited(1), autoRestarting: false),
            .started: .started(one, origin: .agent, action: nil),
            .restarted: .restarted(one, origin: .agent, action: nil),
            .stoppedOrFinished: .stopped(one, origin: .agent, action: nil),
        ]
        for kind in NotificationKind.allCases {
            var settings = NotificationSettings()
            settings[kind] = false
            for (sentKind, trigger) in triggers {
                #expect((send(trigger, settings) == nil) == (sentKind == kind), "switch \(kind), trigger \(sentKind)")
            }
        }
        var noFinished = NotificationSettings()
        noFinished[.stoppedOrFinished] = false
        #expect(send(.finished(one[0]), noFinished) == nil)
    }

    @Test func everySwitchIsOnByDefaultAndAnOlderFileKeepsTheDefaults() throws {
        #expect(NotificationKind.allCases.allSatisfy { NotificationSettings()[$0] })
        let json = #"{"showMenubarIcon": true, "launchAtLogin": false}"#
        let settings = try JSONDecoder().decode(HelperSettings.self, from: Data(json.utf8))
        #expect(settings.notifications == NotificationSettings())
    }
}
