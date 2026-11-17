import DevDevCore
import Sparkle
import SwiftUI

/// Sparkle's standard updater, for the builds that have one. `BuildFlavor.hasUpdater` decides:
/// a Debug build makes no `AppUpdater`, so it starts no updater and makes no check.
///
/// The feed, the daily check and the rule that nothing installs by itself are set in
/// `Config/App-Info.plist`. The update replaces the App only; it never touches the Helper.
@MainActor
@Observable
final class AppUpdater {
    /// Made, and so started, once at launch. `nil` in a build without an updater.
    static let forThisBuild: AppUpdater? = BuildFlavor.current().hasUpdater ? AppUpdater() : nil

    /// False while Sparkle cannot start a check: it failed to start, or a check is already running.
    private(set) var canCheckForUpdates = false

    /// Sparkle's own stored preference for the daily check. Settings shows it; the Helper never stores it.
    private(set) var automaticallyChecksForUpdates = false

    private let controller: SPUStandardUpdaterController
    private var observations: [NSKeyValueObservation] = []

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        canCheckForUpdates = controller.updater.canCheckForUpdates
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in self?.canCheckForUpdates = value }
            },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in self?.automaticallyChecksForUpdates = value }
            },
        ]
    }

    /// Turns the daily check on or off. Sparkle stores the choice in the App's own defaults.
    func setAutomaticallyChecksForUpdates(_ on: Bool) {
        controller.updater.automaticallyChecksForUpdates = on
        automaticallyChecksForUpdates = on
    }

    /// Asks Sparkle to check now and show its standard window.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// **Check for Updates…**, directly below **About DevDev**. Absent in a build without an updater.
struct UpdateCommands: Commands {
    let updater: AppUpdater?

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if let updater {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}
