import Foundation
import Testing

@testable import DevDevCore

/// A login item that records what it was asked to do.
final class RecordingLoginItem: LoginItem, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [Bool] = []
    private var failure: Error?

    var requests: [Bool] { lock.withLock { calls } }

    func fail(with error: Error?) {
        lock.withLock { failure = error }
    }

    func apply(enabled: Bool) throws {
        try lock.withLock {
            if let failure { throw failure }
            calls.append(enabled)
        }
    }
}

/// The two Settings switches the Helper stores: Show menubar icon and Launch at login.
@Suite struct HelperSettingsTests {
    private func makeEngine(_ folder: URL, loginItem: (any LoginItem)? = nil) throws -> (HelperEngine, ConfigurationStore) {
        let store = ConfigurationStore(file: folder.appendingPathComponent("configuration.json"))
        return (HelperEngine(configuration: try store.load(), store: store, shell: .plain, loginItem: loginItem), store)
    }

    @Test func theMenubarIconIsOnAndLaunchAtLoginIsOffByDefault() async throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (engine, _) = try makeEngine(folder)
        #expect(await engine.settings() == HelperSettings(showMenubarIcon: true, launchAtLogin: false))
    }

    @Test func aConfigurationFileSavedBeforeSettingsExistedLoadsWithTheDefaults() throws {
        let json = #"{"version": 1, "projects": []}"#
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
        #expect(configuration.settings == HelperSettings())
    }

    @Test func changedSettingsAreSavedAndPushedToEveryClientAsAnEvent() async throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (engine, store) = try makeEngine(folder, loginItem: RecordingLoginItem())
        let log = await EventLog.listening(to: engine)
        let wanted = HelperSettings(showMenubarIcon: false, launchAtLogin: true)

        let answer = try await engine.updateSettings(wanted)

        #expect(answer == wanted)
        #expect(try store.load().settings == wanted)
        try await waitUntil("the settings event arrived") {
            await log.events.contains(.settings(wanted))
        }
        // A new Helper reads them back.
        let (reloaded, _) = try makeEngine(folder)
        #expect(await reloaded.settings() == wanted)
    }

    @Test func settingsTravelOverTheSocketAndReachOtherClientsAsEvents() async throws {
        try await withHarness([]) { h in
            let socketPath = h.folder.appendingPathComponent("h.sock").path
            let server = HelperServer(engine: h.engine, socketPath: socketPath)
            try server.start()
            defer { server.stop() }
            let app = try await HelperClient.connect(socketPath: socketPath, clientName: "app")
            let other = try await HelperClient.connect(socketPath: socketPath, clientName: "other")
            defer {
                app.close()
                other.close()
            }

            #expect(try await app.send(.settings) == .settings(HelperSettings()))
            let wanted = HelperSettings(showMenubarIcon: false, launchAtLogin: false)
            #expect(try await app.send(.updateSettings(wanted), origin: .user) == .settings(wanted))

            for await event in other.events {
                if event == .settings(wanted) { break }
            }
            #expect(try await other.send(.settings) == .settings(wanted))
        }
    }

    @Test func changingSettingsNeedsAnOrigin() async throws {
        try await withHarness([]) { h in
            let response = await h.engine.respond(
                to: .updateSettings(HelperSettings()), origin: nil, subscriber: UUID())
            guard case .failure(let error) = response else {
                Issue.record("expected a failure, got \(response)")
                return
            }
            #expect(error.code == HelperError.originRequired)
        }
    }

    @Test func turningLaunchAtLoginOnAndOffAsksTheLoginItemAndNothingElseRuns() async throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let loginItem = RecordingLoginItem()
        let (engine, _) = try makeEngine(folder, loginItem: loginItem)
        let projectFolder = folder.appendingPathComponent("shop", isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        let project = try await engine.addProject(folder: projectFolder.path)
        try await engine.addCommand(to: project.id, settings: CommandSettings(name: "Main", commandLine: "sleep 5"))

        try await engine.updateSettings(HelperSettings(showMenubarIcon: true, launchAtLogin: true))
        // Only the icon changes: the login item is left alone.
        try await engine.updateSettings(HelperSettings(showMenubarIcon: false, launchAtLogin: true))
        try await engine.updateSettings(HelperSettings(showMenubarIcon: false, launchAtLogin: false))

        #expect(loginItem.requests == [true, false])
        #expect(await engine.snapshot().projects[0].commands.map(\.status) == [.stopped])
    }

    @Test func aLoginItemThatFailsLeavesTheSettingUnchangedAndSaysWhy() async throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let loginItem = RecordingLoginItem()
        loginItem.fail(with: CocoaError(.fileWriteNoPermission))
        let (engine, store) = try makeEngine(folder, loginItem: loginItem)

        await #expect(throws: HelperError.self) {
            try await engine.updateSettings(HelperSettings(showMenubarIcon: true, launchAtLogin: true))
        }

        #expect(await engine.settings().launchAtLogin == false)
        #expect(try store.load().settings.launchAtLogin == false)
    }
}
