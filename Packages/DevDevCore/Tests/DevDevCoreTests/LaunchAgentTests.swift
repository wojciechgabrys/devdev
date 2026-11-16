import Foundation
import Testing

@testable import DevDevCore

/// Launch at login as a LaunchAgent file. The login-item API fails after a reinstall
/// (`docs/spike-results.md` item 3), so this is the fallback the spike chose.
@Suite struct LaunchAgentTests {
    private func plist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func turningItOnWritesAnAgentThatStartsTheInstalledHelperOnlyAtLogin() throws {
        let home = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let agent = LaunchAgentLoginItem.forHelper(
            flavor: .release, runningHelperExecutable: URL(fileURLWithPath: "/tmp/elsewhere/devdevHelper"), home: home)

        try agent.apply(enabled: true)

        #expect(agent.file.path == home.path + "/Library/LaunchAgents/dev.devdev.helper.plist")
        let contents = try plist(at: agent.file)
        #expect(contents["Label"] as? String == "dev.devdev.helper")
        // Only the Helper, from /Applications, with no arguments: it starts no Process.
        #expect(
            contents["ProgramArguments"] as? [String] == [
                "/Applications/devdev.app/Contents/Helpers/devdevHelper.app/Contents/MacOS/devdevHelper"
            ])
        #expect(contents["RunAtLoad"] as? Bool == true)
        // Stop All and Quit must stay quit.
        #expect(contents["KeepAlive"] == nil)
        #expect(Set(contents.keys) == ["Label", "ProgramArguments", "RunAtLoad"])
    }

    @Test func turningItOffDeletesTheAgentFileAndOffTwiceIsFine() throws {
        let home = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let agent = LaunchAgentLoginItem.forHelper(
            flavor: .release, runningHelperExecutable: URL(fileURLWithPath: "/tmp/x"), home: home)
        try agent.apply(enabled: true)

        try agent.apply(enabled: false)
        #expect(!FileManager.default.fileExists(atPath: agent.file.path))
        try agent.apply(enabled: false)
    }

    @Test func aDebugHelperUsesItsOwnLabelAndItsOwnExecutable() throws {
        let home = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let running = URL(fileURLWithPath: "/tmp/Build/devdev.app/Contents/Helpers/devdevHelper.app/Contents/MacOS/devdevHelper")
        let agent = LaunchAgentLoginItem.forHelper(flavor: .debug, runningHelperExecutable: running, home: home)

        try agent.apply(enabled: true)

        #expect(agent.file.lastPathComponent == "dev.devdev.helper.debug.plist")
        let contents = try plist(at: agent.file)
        #expect(contents["Label"] as? String == "dev.devdev.helper.debug")
        #expect(contents["ProgramArguments"] as? [String] == [running.path])
    }

    @Test func theEngineTurnsLaunchAtLoginOnThroughTheAgentFile() async throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let agent = LaunchAgentLoginItem.forHelper(
            flavor: .release, runningHelperExecutable: URL(fileURLWithPath: "/tmp/x"), home: folder)
        let store = ConfigurationStore(file: folder.appendingPathComponent("configuration.json"))
        let engine = HelperEngine(configuration: Configuration(), store: store, shell: .plain, loginItem: agent)

        try await engine.updateSettings(HelperSettings(showMenubarIcon: true, launchAtLogin: true))
        #expect(FileManager.default.fileExists(atPath: agent.file.path))

        try await engine.updateSettings(HelperSettings(showMenubarIcon: true, launchAtLogin: false))
        #expect(!FileManager.default.fileExists(atPath: agent.file.path))
    }
}
