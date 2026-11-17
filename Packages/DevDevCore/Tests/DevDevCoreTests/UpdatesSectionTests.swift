import Foundation
import Testing

@testable import DevDevCore

/// The Updates section of Settings: what it shows in each build flavor, and where
/// `App/SettingsView.swift`, read as text, puts it.
@Suite struct UpdatesSectionTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theSectionIsTitledUpdates() {
        #expect(UpdatesSection.title == "Updates")
    }

    @Test(arguments: BuildFlavor.allCases)
    func everyBuildShowsTheCurrentVersion(flavor: BuildFlavor) {
        let section = UpdatesSection(flavor: flavor, short: "0.2.1", build: "0.2.1")
        #expect(section.versionLabel == "Version 0.2.1")
    }

    @Test func aReleaseBuildHasOneSwitchCheckForUpdatesAutomatically() {
        let section = UpdatesSection(flavor: .release, short: "0.2.1", build: "0.2.1")
        #expect(section.switches == [.automaticChecks])
        #expect(section.switches.map(\.label) == ["Check for updates automatically"])
    }

    @Test func aDebugBuildHasNoSwitch() {
        let section = UpdatesSection(flavor: .debug, short: "0.2.1", build: "0.2.1")
        #expect(section.switches.isEmpty)
    }

    @Test func noSwitchInstallsAutomatically() {
        for item in UpdatesSection.Switch.allCases {
            #expect(!item.label.localizedCaseInsensitiveContains("install"))
        }
    }

    // MARK: - App/SettingsView.swift, read as text

    /// The leading whitespace of the first line that holds `text`.
    private func indentation(of text: String, in source: String) throws -> String {
        let line = try #require(source.components(separatedBy: "\n").first { $0.contains(text) }, "no line holds \(text)")
        return String(line.prefix { $0 == " " })
    }

    @Test func settingsShowsTheUpdatesSectionWhetherOrNotTheHelperIsConnected() throws {
        let view = try read("App/SettingsView.swift")
        // The MCP section sits outside the branch that needs the Helper's settings. So does this one.
        let updates = try indentation(of: "Section(UpdatesSection.title)", in: view)
        #expect(updates == (try indentation(of: "Section(\"MCP\")", in: view)))
        #expect(updates.count < (try indentation(of: "Section(\"Notifications\")", in: view)).count)
        #expect(view.contains("updates.versionLabel"))
    }

    @Test func theSwitchReadsAndWritesSparklesOwnPreferenceAndNothingInstallsAutomatically() throws {
        let view = try read("App/SettingsView.swift")
        #expect(view.contains("updates.switches"))
        let updater = try read("App/AppUpdater.swift")
        #expect(updater.contains("controller.updater.automaticallyChecksForUpdates = "))
        for source in [view, updater] {
            #expect(!source.contains("automaticallyDownloadsUpdates"))
        }
        // The Helper stores its own settings, and this is not one of them.
        let helperSettings = try read("Packages/DevDevCore/Sources/DevDevCore/HelperSettings.swift")
        #expect(!helperSettings.localizedCaseInsensitiveContains("update"))
    }
}
