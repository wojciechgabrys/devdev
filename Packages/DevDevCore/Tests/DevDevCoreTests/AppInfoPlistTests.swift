import Foundation
import Testing

/// The updater's settings in the App's Info.plist, read from `Config/App-Info.plist` in the repo.
/// Sparkle reads these keys at launch; `docs/spike-results.md` records what each one does.
@Suite struct AppInfoPlistTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func plist() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("Config/App-Info.plist"))
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(parsed as? [String: Any])
    }

    @Test func theFeedIsTheAppcastOfTheNewestGitHubRelease() throws {
        #expect(
            try plist()["SUFeedURL"] as? String
                == "https://github.com/wojciechgabrys/devdev/releases/latest/download/appcast.xml")
    }

    @Test func automaticChecksAreOnFromTheFirstLaunchOnceADayWithNoPermissionPrompt() throws {
        let plist = try plist()
        // Set to true, Sparkle checks without asking; unset, it would ask on the second launch.
        #expect(plist["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(plist["SUScheduledCheckInterval"] as? Int == 24 * 60 * 60)
        // This key only works while SUEnableAutomaticChecks is unset.
        #expect(plist["SUPromptUserOnFirstLaunch"] == nil)
    }

    @Test func nothingDownloadsOrInstallsSilentlyAndTheWindowOffersNoAutomaticInstall() throws {
        let plist = try plist()
        #expect(plist["SUAutomaticallyUpdate"] as? Bool == false)
        #expect(plist["SUAllowsAutomaticUpdates"] as? Bool == false)
    }
}
